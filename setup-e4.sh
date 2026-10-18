#!/usr/bin/env bash
# NOVA AI - Engine phase E4: Google recognizer fed with our own audio (Android 13+).
# Additive: new GoogleRecognizerBridge; MicLabController and MicLabCard are rewritten
# with every E1 and E2 feature kept.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"

for required in \
  "$BASE/audio/SpeechDetector.kt" \
  "$BASE/audio/MicLabController.kt" \
  "$BASE/ui/components/MicLabCard.kt" \
  "$BASE/voice/SpeechErrorMapper.kt" \
  "$BASE/ui/theme/AppSettings.kt" \
  "$BASE/time/TimeText.kt"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after E1 and E2 are installed." >&2
    exit 1
  fi
done

# ---------- A. New strings file ----------
cat > app/src/main/res/values/strings_e4.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="rec_title">Google-এ কথা চেনা (ইঞ্জিন E4)</string>
    <string name="rec_note">ধরা প্রতিটি কথা নিজের অডিও হিসেবে Google-এর ভয়েস সার্ভিসে পাঠিয়ে লেখা আনা হয়। পাঠানোর সময় বিপ শোনা যায় কি না খেয়াল করো।</string>
    <string name="rec_privacy">ইন্টারনেট মোডে তোমার কথার অডিও Google-এর সার্ভারে যায়। অফলাইন মোডে ফোনের ভেতরেই থাকে।</string>
    <string name="rec_support_ok">নিজের অডিও পাঠানোর সুবিধা: এই ফোনের Android সমর্থন করে (Android 13 বা তার বেশি)।</string>
    <string name="rec_support_no">নিজের অডিও পাঠানোর সুবিধা: এই ফোনের Android-এ নেই (Android 13 বা তার বেশি লাগে)।</string>
    <string name="rec_ondevice_yes">ফোনে অফলাইন ভয়েস সার্ভিস: আছে</string>
    <string name="rec_ondevice_no">ফোনে অফলাইন ভয়েস সার্ভিস: নেই</string>
    <string name="rec_auto_label">ধরা কথা নিজে Google-এ পাঠাও</string>
    <string name="rec_engine_title">কোন সার্ভিসে পাঠাব</string>
    <string name="rec_engine_online">ইন্টারনেট (সবচেয়ে নির্ভুল)</string>
    <string name="rec_engine_on_device">ফোনের অফলাইন সার্ভিস</string>
    <string name="rec_send">Google-এ পাঠাও</string>
    <string name="rec_resend">আবার পাঠাও</string>
    <string name="rec_sending">পাঠানো হচ্ছে...</string>
    <string name="rec_result">লেখা: %1$s (সময়: %2$s সেকেন্ড)</string>
    <string name="rec_failed">চেনা যায়নি: %1$s (সময়: %2$s সেকেন্ড)</string>
    <string name="rec_empty">কিছু বোঝা যায়নি।</string>
</resources>
EOF

# ---------- 1. GoogleRecognizerBridge.kt ----------
cat > "$BASE/audio/GoogleRecognizerBridge.kt" <<'EOF'
package com.nova.ai.audio

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaError
import com.nova.ai.logging.NovaLogger
import com.nova.ai.settings.AppLanguage
import com.nova.ai.voice.SpeechErrorMapper
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Sends our own recorded sound to Android's speech recognizer (Google's service)
 * instead of letting it open the microphone. The sound travels through a private
 * pipe; the recognizer reads it and returns the text. This needs Android 13 or newer,
 * and the recognizer service must support it (the test shows whether it does).
 *
 * One request at a time. Use from the main thread. Sound and text are never logged.
 */
class GoogleRecognizerBridge(
    context: Context,
    private val scope: CoroutineScope
) {

    /** Which recognizer service gets the sound. */
    enum class Service {
        /** Google's online service: the most accurate. The sound goes to Google's servers. */
        ONLINE,

        /** The recognizer inside the phone: works without internet if the language is installed. */
        ON_DEVICE
    }

    /** The result of one request: text, or an error, and how long it took. */
    data class Outcome(val text: String?, val error: NovaError?, val latencyMs: Long)

    private val appContext: Context = context.applicationContext
    private val handler: Handler = Handler(Looper.getMainLooper())
    private var activeSession: Session? = null

    /** True if this Android version can feed our own sound to the recognizer. */
    fun isFeedSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    /** True if the phone has an offline recognizer. */
    fun isOnDeviceAvailable(): Boolean = try {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(appContext)
    } catch (e: Exception) {
        NovaLogger.e(TAG, "Failed to check the offline recognizer", e)
        false
    }

    /** Sends [samples] (16 kHz, mono) to the chosen [service] and reports the result to [onResult]. */
    fun recognize(
        samples: ShortArray,
        service: Service,
        language: AppLanguage,
        onResult: (Outcome) -> Unit
    ) {
        cancel()

        if (!isFeedSupported()) {
            onResult(failure(ErrorCode.NOT_AVAILABLE, MSG_UNSUPPORTED_OS))
            return
        }
        if (samples.isEmpty()) {
            onResult(failure(ErrorCode.INVALID_INPUT, MSG_AUDIO_ERROR))
            return
        }

        val recognizer: SpeechRecognizer = createRecognizer(service) ?: run {
            onResult(failure(ErrorCode.NOT_AVAILABLE, MSG_NO_SERVICE))
            return
        }

        val pipe = try {
            ParcelFileDescriptor.createPipe()
        } catch (e: IOException) {
            NovaLogger.e(TAG, "Failed to create the audio pipe", e)
            destroyQuietly(recognizer)
            onResult(failure(ErrorCode.EXECUTION_FAILED, MSG_AUDIO_ERROR))
            return
        }

        val session = Session(recognizer, pipe[0], pipe[1], samples, onResult)
        activeSession = session
        session.begin(languageTagOf(language))
    }

    /** Stops the request in progress without reporting a result. */
    fun cancel() {
        activeSession?.abort()
        activeSession = null
    }

    private fun createRecognizer(service: Service): SpeechRecognizer? = try {
        when (service) {
            Service.ONLINE ->
                if (SpeechRecognizer.isRecognitionAvailable(appContext)) {
                    SpeechRecognizer.createSpeechRecognizer(appContext)
                } else {
                    null
                }
            Service.ON_DEVICE ->
                if (isOnDeviceAvailable()) {
                    SpeechRecognizer.createOnDeviceSpeechRecognizer(appContext)
                } else {
                    null
                }
        }
    } catch (e: Exception) {
        NovaLogger.e(TAG, "Failed to create the recognizer", e)
        null
    }

    private fun languageTagOf(language: AppLanguage): String = when (language) {
        AppLanguage.ENGLISH -> TAG_ENGLISH
        AppLanguage.BANGLA, AppLanguage.MIXED -> TAG_BANGLA
    }

    private fun failure(code: ErrorCode, message: String): Outcome =
        Outcome(text = null, error = NovaError(code, message), latencyMs = 0L)

    private fun destroyQuietly(recognizer: SpeechRecognizer) {
        try {
            recognizer.destroy()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to release the recognizer", e)
        }
    }

    private fun closeQuietly(descriptor: ParcelFileDescriptor) {
        try {
            descriptor.close()
        } catch (e: IOException) {
            NovaLogger.w(TAG, "Failed to close a pipe end", e)
        }
    }

    /** One request: the recognizer, the pipe, and the writer that feeds the sound. */
    private inner class Session(
        private val recognizer: SpeechRecognizer,
        private val readSide: ParcelFileDescriptor,
        private val writeSide: ParcelFileDescriptor,
        private val samples: ShortArray,
        private val onResult: (Outcome) -> Unit
    ) : RecognitionListener {

        private val startedAtMs: Long = SystemClock.elapsedRealtime()
        private var finished: Boolean = false
        private var writerJob: Job? = null
        private val timeoutTask = Runnable {
            complete(
                text = null,
                error = NovaError(ErrorCode.TIMEOUT, MSG_TIMEOUT),
                notify = true
            )
        }

        fun begin(languageTag: String) {
            recognizer.setRecognitionListener(this)
            val sendMs: Long = samples.size * 1000L / AudioConfig.SAMPLE_RATE_HZ
            handler.postDelayed(timeoutTask, TIMEOUT_BASE_MS + sendMs)

            try {
                recognizer.startListening(buildIntent(languageTag))
            } catch (e: Exception) {
                NovaLogger.e(TAG, "Failed to start the recognizer", e)
                complete(null, NovaError(ErrorCode.EXECUTION_FAILED, MSG_AUDIO_ERROR), notify = true)
                return
            }
            writerJob = scope.launch(Dispatchers.IO) { writeSound() }
        }

        /** Ends this request without reporting anything. */
        fun abort() {
            complete(text = null, error = null, notify = false)
        }

        private fun buildIntent(languageTag: String): Intent =
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, appContext.packageName)
                // These keys tell the recognizer to read our sound instead of the microphone.
                putExtra(KEY_AUDIO_SOURCE, readSide)
                putExtra(KEY_AUDIO_SAMPLING_RATE, AudioConfig.SAMPLE_RATE_HZ)
                putExtra(KEY_AUDIO_CHANNEL_COUNT, 1)
                putExtra(KEY_AUDIO_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            }

        // Runs on a background thread. Closing the stream tells the recognizer the sound is over.
        private fun writeSound() {
            try {
                ParcelFileDescriptor.AutoCloseOutputStream(writeSide).use { stream ->
                    stream.write(toBytes(samples))
                }
            } catch (e: IOException) {
                // Normal when the request ends early and the pipe is closed.
                NovaLogger.w(TAG, "Sound feed ended early", e)
            }
        }

        private fun toBytes(source: ShortArray): ByteArray {
            val padSamples: Int = AudioConfig.SAMPLE_RATE_HZ * SILENCE_PAD_MS / 1000
            val buffer: ByteBuffer = ByteBuffer
                .allocate((source.size + padSamples) * AudioConfig.BYTES_PER_SAMPLE)
                .order(ByteOrder.LITTLE_ENDIAN)
            buffer.asShortBuffer().put(source)
            // The bytes after the sound stay zero: a short quiet end helps the recognizer finish.
            return buffer.array()
        }

        private fun complete(text: String?, error: NovaError?, notify: Boolean) {
            if (finished) return
            finished = true

            handler.removeCallbacks(timeoutTask)
            writerJob?.cancel()
            closeQuietly(writeSide)
            closeQuietly(readSide)
            destroyQuietly(recognizer)
            if (activeSession === this) activeSession = null

            if (notify) {
                val latency: Long = SystemClock.elapsedRealtime() - startedAtMs
                onResult(Outcome(text, error, latency))
            }
        }

        override fun onResults(results: Bundle?) {
            val text: String? = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?.trim()
            complete(text = text, error = null, notify = true)
        }

        override fun onError(error: Int) {
            NovaLogger.w(TAG, "Recognizer error $error")
            complete(null, SpeechErrorMapper.toNovaError(error), notify = true)
        }

        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onPartialResults(partialResults: Bundle?) = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    private companion object {
        const val TAG: String = "GoogleRecognizerBridge"
        const val TAG_BANGLA: String = "bn-BD"
        const val TAG_ENGLISH: String = "en-US"

        // Keys of the Android 13 feature that feeds our own sound to the recognizer.
        const val KEY_AUDIO_SOURCE: String = "android.speech.extra.AUDIO_SOURCE"
        const val KEY_AUDIO_SAMPLING_RATE: String = "android.speech.extra.AUDIO_SOURCE_SAMPLING_RATE"
        const val KEY_AUDIO_CHANNEL_COUNT: String = "android.speech.extra.AUDIO_SOURCE_CHANNEL_COUNT"
        const val KEY_AUDIO_ENCODING: String = "android.speech.extra.AUDIO_SOURCE_ENCODING"

        const val SILENCE_PAD_MS: Int = 300
        const val TIMEOUT_BASE_MS: Long = 15_000L

        const val MSG_UNSUPPORTED_OS: String = "নিজের অডিও পাঠানোর জন্য Android 13 বা তার বেশি লাগে।"
        const val MSG_NO_SERVICE: String = "ফোনে এই ভয়েস চেনার সার্ভিস পাওয়া যায়নি।"
        const val MSG_AUDIO_ERROR: String = "অডিও পাঠাতে সমস্যা হয়েছে।"
        const val MSG_TIMEOUT: String =
            "সময় শেষ: Google সাড়া দেয়নি। হয়তো এই ফোনে নিজের অডিও সমর্থিত নয়।"
    }
}
EOF

# ---------- 2. MicLabController.kt (E1 and E2 kept; Google recognition added) ----------
cat > "$BASE/audio/MicLabController.kt" <<'EOF'
package com.nova.ai.audio

import android.content.Context
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.R
import com.nova.ai.core.NovaError
import com.nova.ai.core.NovaResult
import com.nova.ai.settings.AppLanguage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** What the test card is doing with the sound. */
enum class LabPhase { IDLE, RECORDING, PLAYING }

/** What happened when a piece of speech was sent to the recognizer. */
sealed class RecognitionStatus {
    object NotSent : RecognitionStatus()
    object Sending : RecognitionStatus()
    data class Done(val text: String, val latencyMs: Long) : RecognitionStatus()
    data class Failed(val message: String, val latencyMs: Long) : RecognitionStatus()
}

/** One detected piece of speech, kept for replay and recognition in the test card. */
class Utterance(
    val id: Int,
    val durationMs: Long,
    val samples: ShortArray,
    val endReason: SegmentEnd
) {
    /** The recognizer's answer for this piece. */
    var recognition: RecognitionStatus by mutableStateOf<RecognitionStatus>(RecognitionStatus.NotSent)
}

/**
 * Screen-side holder for the microphone test card: starts and stops the
 * microphone, shows the level, finds pieces of speech, sends them to Google's
 * recognizer, records a 5-second clip and plays sounds back.
 * [languageProvider] gives the language chosen in settings. Use from the main thread.
 */
class MicLabController(
    context: Context,
    private val scope: CoroutineScope,
    private val languageProvider: () -> AppLanguage = { AppLanguage.BANGLA }
) {

    private val appContext: Context = context.applicationContext
    private val engine = AudioCaptureEngine(appContext)
    private val detector = SpeechDetector(engine)
    private val player = ClipPlayer()
    private val bridge = GoogleRecognizerBridge(appContext, scope)

    private var clipJob: Job? = null
    private var lastClip: ShortArray? = null
    private var lastSignalMs: Long = 0L
    private var nextUtteranceId: Int = 1
    private val utteranceList = mutableStateListOf<Utterance>()

    private val recognitionQueue = ArrayDeque<Utterance>()
    private var inFlight: Utterance? = null

    var isRunning: Boolean by mutableStateOf(false)
        private set

    var meterLevel: Float by mutableStateOf(0f)
        private set

    var profile: CaptureProfile by mutableStateOf(CaptureProfile.CLEAN)
        private set

    var effects: AudioEffectsStatus? by mutableStateOf<AudioEffectsStatus?>(null)
        private set

    var phase: LabPhase by mutableStateOf(LabPhase.IDLE)
        private set

    var clipSeconds: Int by mutableStateOf(0)
        private set

    var silentWarning: Boolean by mutableStateOf(false)
        private set

    var errorMessage: String? by mutableStateOf<String?>(null)
        private set

    // ---- speech detection state ----

    var speaking: Boolean by mutableStateOf(false)
        private set

    var noiseFloorDb: Float by mutableStateOf(0f)
        private set

    var sensitivity: VadSensitivity by mutableStateOf(VadSensitivity.NORMAL)
        private set

    var pause: PauseTolerance by mutableStateOf(PauseTolerance.NORMAL)
        private set

    var detectedCount: Int by mutableStateOf(0)
        private set

    var discardedCount: Int by mutableStateOf(0)
        private set

    var playingUtteranceId: Int? by mutableStateOf<Int?>(null)
        private set

    // ---- recognition state ----

    /** True if this Android version can feed our own sound to the recognizer. */
    val feedSupported: Boolean = bridge.isFeedSupported()

    /** True if the phone has an offline recognizer. */
    val onDeviceAvailable: Boolean = bridge.isOnDeviceAvailable()

    var autoRecognize: Boolean by mutableStateOf(true)
        private set

    var recognitionService: GoogleRecognizerBridge.Service by
        mutableStateOf(GoogleRecognizerBridge.Service.ONLINE)
        private set

    /** The newest detected pieces of speech, newest first. */
    val utterances: List<Utterance>
        get() = utteranceList

    private val engineListener = object : AudioCaptureEngine.Listener {
        override fun onLevel(level: Float, peak: Float) {
            meterLevel = level
            speaking = detector.isSpeaking()
            noiseFloorDb = detector.noiseFloorDb()

            val now: Long = SystemClock.elapsedRealtime()
            if (peak > SILENCE_PEAK) {
                lastSignalMs = now
                silentWarning = false
            } else if (now - lastSignalMs > SILENT_WARNING_MS) {
                silentWarning = true
            }
        }

        override fun onError(error: NovaError) {
            errorMessage = error.message
            stop()
        }
    }

    private val speechListener = object : SpeechDetector.Listener {
        override fun onSpeechStarted() {
            speaking = true
        }

        override fun onSpeechEnded(segment: SpeechSegment) {
            // A piece cut for length means the speaker is probably still talking.
            speaking = segment.endReason == SegmentEnd.MAX_LENGTH
            detectedCount += 1

            val item = Utterance(nextUtteranceId, segment.durationMs, segment.samples, segment.endReason)
            nextUtteranceId += 1
            utteranceList.add(0, item)
            while (utteranceList.size > MAX_KEPT_UTTERANCES) {
                utteranceList.removeAt(utteranceList.lastIndex)
            }

            if (autoRecognize && feedSupported) enqueueRecognition(item)
        }

        override fun onSpeechDiscarded(durationMs: Long) {
            speaking = false
            discardedCount += 1
        }
    }

    /** Opens the microphone with the chosen [profile] and starts watching for speech. */
    fun start() {
        errorMessage = null
        when (val result: NovaResult<Unit> = engine.start(profile, engineListener)) {
            is NovaResult.Success -> {
                isRunning = true
                effects = engine.effectsStatus
                lastSignalMs = SystemClock.elapsedRealtime()
                silentWarning = false
                detector.updateConfig(VadConfig(sensitivity = sensitivity, pause = pause))
                detector.attach(speechListener)
            }
            is NovaResult.Failure -> {
                isRunning = false
                errorMessage = result.error.message
            }
        }
    }

    /** Closes the microphone and stops any recording or playback. Sending to Google continues. */
    fun stop() {
        clipJob?.cancel()
        clipJob = null
        player.stop()
        engine.stop()
        detector.detach()
        isRunning = false
        meterLevel = 0f
        speaking = false
        silentWarning = false
        phase = LabPhase.IDLE
        playingUtteranceId = null
    }

    /** Switches the microphone type; restarts the microphone if it is running. */
    fun selectProfile(newProfile: CaptureProfile) {
        if (newProfile == profile) return
        val wasRunning: Boolean = isRunning
        if (wasRunning) stop()
        profile = newProfile
        if (wasRunning) start()
    }

    /** Changes how easily speech is detected. Applies at once. */
    fun selectSensitivity(value: VadSensitivity) {
        sensitivity = value
        detector.updateConfig(VadConfig(sensitivity = value, pause = pause))
    }

    /** Changes how long a pause must be to end a piece of speech. Applies at once. */
    fun selectPause(value: PauseTolerance) {
        pause = value
        detector.updateConfig(VadConfig(sensitivity = sensitivity, pause = value))
    }

    /** Turns automatic sending of detected speech to the recognizer on or off. */
    fun setAutoRecognize(enabled: Boolean) {
        autoRecognize = enabled
    }

    /** Chooses which recognizer service receives the sound. */
    fun selectRecognitionService(service: GoogleRecognizerBridge.Service) {
        recognitionService = service
    }

    /** Sends one detected piece of speech to the recognizer (again, if it was sent before). */
    fun recognize(id: Int) {
        val item: Utterance = utteranceList.firstOrNull { it.id == id } ?: return
        enqueueRecognition(item)
    }

    /** Records the next 5 seconds and keeps them for playback. */
    fun recordClip() {
        if (!isRunning || phase != LabPhase.IDLE) return
        clipJob = scope.launch {
            phase = LabPhase.RECORDING
            engine.buffer.clear()
            delay(CLIP_MS)
            val clip: ShortArray = engine.buffer.readLast(CLIP_SAMPLES)
            lastClip = clip
            clipSeconds = clip.size / AudioConfig.SAMPLE_RATE_HZ
            phase = LabPhase.IDLE
        }
    }

    /** Plays the recorded 5-second clip. */
    fun playClip() {
        val clip: ShortArray = lastClip ?: return
        if (phase != LabPhase.IDLE) return
        startPlayback(clip, null)
    }

    /** Plays one detected piece of speech. */
    fun playUtterance(id: Int) {
        if (phase != LabPhase.IDLE) return
        val item: Utterance = utteranceList.firstOrNull { it.id == id } ?: return
        startPlayback(item.samples, id)
    }

    /** The user refused the microphone permission. */
    fun reportPermissionDenied() {
        errorMessage = appContext.getString(R.string.mic_lab_permission)
    }

    /** Releases everything, including any request to the recognizer. Call when the screen is gone. */
    fun release() {
        stop()
        bridge.cancel()
        for (waiting in recognitionQueue) waiting.recognition = RecognitionStatus.NotSent
        recognitionQueue.clear()
        inFlight?.recognition = RecognitionStatus.NotSent
        inFlight = null
    }

    // ---------------------------------------------------------------- recognition queue

    private fun enqueueRecognition(item: Utterance) {
        if (item.recognition is RecognitionStatus.Sending) return
        item.recognition = RecognitionStatus.Sending
        recognitionQueue.addLast(item)
        pumpRecognition()
    }

    // One request at a time: the next starts when the previous has an answer.
    private fun pumpRecognition() {
        if (inFlight != null) return
        val next: Utterance = recognitionQueue.removeFirstOrNull() ?: return
        inFlight = next

        bridge.recognize(next.samples, recognitionService, languageProvider()) { outcome ->
            next.recognition = statusOf(outcome)
            inFlight = null
            pumpRecognition()
        }
    }

    private fun statusOf(outcome: GoogleRecognizerBridge.Outcome): RecognitionStatus {
        val text: String? = outcome.text?.takeIf { it.isNotBlank() }
        if (text != null) return RecognitionStatus.Done(text, outcome.latencyMs)
        val message: String = outcome.error?.message ?: appContext.getString(R.string.rec_empty)
        return RecognitionStatus.Failed(message, outcome.latencyMs)
    }

    private fun startPlayback(samples: ShortArray, utteranceId: Int?) {
        when (val result: NovaResult<Long> = player.play(samples)) {
            is NovaResult.Success -> {
                phase = LabPhase.PLAYING
                playingUtteranceId = utteranceId
                val durationMs: Long = result.value
                clipJob = scope.launch {
                    delay(durationMs + PLAYBACK_PADDING_MS)
                    player.stop()
                    phase = LabPhase.IDLE
                    playingUtteranceId = null
                }
            }
            is NovaResult.Failure -> errorMessage = result.error.message
        }
    }

    private companion object {
        const val CLIP_SECONDS: Int = 5
        const val CLIP_MS: Long = CLIP_SECONDS * 1000L
        const val CLIP_SAMPLES: Int = CLIP_SECONDS * AudioConfig.SAMPLE_RATE_HZ
        const val PLAYBACK_PADDING_MS: Long = 250L
        const val SILENCE_PEAK: Float = 0.01f
        const val SILENT_WARNING_MS: Long = 3_000L
        const val MAX_KEPT_UTTERANCES: Int = 5
    }
}
EOF

# ---------- 3. MicLabCard.kt (E1 and E2 kept; Google recognition section added) ----------
cat > "$BASE/ui/components/MicLabCard.kt" <<'EOF'
package com.nova.ai.ui.components

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.nova.ai.R
import com.nova.ai.audio.AudioEffectsStatus
import com.nova.ai.audio.CaptureProfile
import com.nova.ai.audio.EffectState
import com.nova.ai.audio.GoogleRecognizerBridge
import com.nova.ai.audio.LabPhase
import com.nova.ai.audio.MicLabController
import com.nova.ai.audio.PauseTolerance
import com.nova.ai.audio.RecognitionStatus
import com.nova.ai.audio.SegmentEnd
import com.nova.ai.audio.Utterance
import com.nova.ai.audio.VadSensitivity
import com.nova.ai.settings.AppLanguage
import com.nova.ai.time.TimeText
import com.nova.ai.ui.theme.LocalAppSettings
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope

/**
 * Test card for the new listening engine: switch the microphone on, watch the
 * level move, compare the two microphone types, record and replay 5 seconds,
 * see how the engine cuts your speech into pieces, and send each piece to
 * Google's recognizer to get the text.
 * The microphone closes when the app goes to the background or the screen is left.
 */
@Composable
fun MicLabCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val scope: CoroutineScope = rememberCoroutineScope()
    val settings = LocalAppSettings.current
    val currentLanguage: AppLanguage by rememberUpdatedState(settings.language)
    val controller: MicLabController = remember {
        MicLabController(context, scope) { currentLanguage }
    }

    val lifecycleOwner: LifecycleOwner? = context as? LifecycleOwner
    DisposableEffect(lifecycleOwner, controller) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) controller.stop()
        }
        lifecycleOwner?.lifecycle?.addObserver(observer)
        onDispose {
            lifecycleOwner?.lifecycle?.removeObserver(observer)
            controller.release()
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted: Boolean ->
        if (granted) controller.start() else controller.reportPermissionDenied()
    }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.mic_lab_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.mic_lab_note),
                style = MaterialTheme.typography.bodySmall
            )

            Button(
                onClick = {
                    if (controller.isRunning) {
                        controller.stop()
                    } else {
                        val micGranted: Boolean = ContextCompat.checkSelfPermission(
                            context, Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                        if (micGranted) {
                            controller.start()
                        } else {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    stringResource(
                        if (controller.isRunning) R.string.mic_lab_stop else R.string.mic_lab_start
                    )
                )
            }

            if (controller.isRunning) {
                Text(
                    text = stringResource(R.string.mic_lab_level),
                    style = MaterialTheme.typography.bodySmall
                )
                LinearProgressIndicator(
                    progress = { controller.meterLevel },
                    modifier = Modifier.fillMaxWidth()
                )
                controller.effects?.let { status ->
                    Text(
                        text = effectsLine(status),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                if (controller.silentWarning) {
                    Text(
                        text = stringResource(R.string.mic_lab_silent),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }

            NovaChoiceGroup(
                title = stringResource(R.string.mic_lab_profile_title),
                options = CaptureProfile.values().toList(),
                selected = controller.profile,
                labelOf = { profileLabel(it) },
                onSelected = { controller.selectProfile(it) }
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { controller.recordClip() },
                    enabled = controller.isRunning && controller.phase == LabPhase.IDLE,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        stringResource(
                            if (controller.phase == LabPhase.RECORDING) {
                                R.string.mic_lab_recording
                            } else {
                                R.string.mic_lab_record
                            }
                        )
                    )
                }
                OutlinedButton(
                    onClick = { controller.playClip() },
                    enabled = controller.clipSeconds > 0 && controller.phase == LabPhase.IDLE,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        stringResource(
                            if (controller.phase == LabPhase.PLAYING && controller.playingUtteranceId == null) {
                                R.string.mic_lab_playing
                            } else {
                                R.string.mic_lab_play
                            }
                        )
                    )
                }
            }

            if (controller.clipSeconds > 0) {
                Text(
                    text = stringResource(R.string.mic_lab_clip_ready, controller.clipSeconds),
                    style = MaterialTheme.typography.bodySmall
                )
            }

            DetectionSection(controller)
            RecognitionSection(controller)
            UtteranceListSection(controller)

            controller.errorMessage?.let { message ->
                Text(
                    text = stringResource(R.string.mic_lab_error, message),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }
        }
    }
}

/** The speech detection part: live state and settings. */
@Composable
private fun ColumnScope.DetectionSection(controller: MicLabController) {
    Text(
        text = stringResource(R.string.vad_title),
        style = MaterialTheme.typography.titleMedium
    )
    Text(
        text = stringResource(R.string.vad_note),
        style = MaterialTheme.typography.bodySmall
    )

    if (controller.isRunning) {
        Text(
            text = stringResource(
                if (controller.speaking) R.string.vad_status_speaking else R.string.vad_status_quiet
            ),
            style = MaterialTheme.typography.titleMedium
        )
        Text(
            text = stringResource(R.string.vad_noise, controller.noiseFloorDb.roundToInt()),
            style = MaterialTheme.typography.bodySmall
        )
    }

    NovaChoiceGroup(
        title = stringResource(R.string.vad_sensitivity_title),
        options = VadSensitivity.values().toList(),
        selected = controller.sensitivity,
        labelOf = { sensitivityLabel(it) },
        onSelected = { controller.selectSensitivity(it) }
    )

    NovaChoiceGroup(
        title = stringResource(R.string.vad_pause_title),
        options = PauseTolerance.values().toList(),
        selected = controller.pause,
        labelOf = { pauseLabel(it) },
        onSelected = { controller.selectPause(it) }
    )

    Text(
        text = stringResource(R.string.vad_count, controller.detectedCount, controller.discardedCount),
        style = MaterialTheme.typography.bodyMedium
    )
}

/** The Google recognition part: support status, automatic sending and the chosen service. */
@Composable
private fun ColumnScope.RecognitionSection(controller: MicLabController) {
    Text(
        text = stringResource(R.string.rec_title),
        style = MaterialTheme.typography.titleMedium
    )
    Text(
        text = stringResource(R.string.rec_note),
        style = MaterialTheme.typography.bodySmall
    )
    Text(
        text = stringResource(R.string.rec_privacy),
        style = MaterialTheme.typography.bodySmall
    )
    Text(
        text = stringResource(
            if (controller.feedSupported) R.string.rec_support_ok else R.string.rec_support_no
        ),
        style = MaterialTheme.typography.bodySmall
    )
    Text(
        text = stringResource(
            if (controller.onDeviceAvailable) R.string.rec_ondevice_yes else R.string.rec_ondevice_no
        ),
        style = MaterialTheme.typography.bodySmall
    )

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = stringResource(R.string.rec_auto_label),
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f)
        )
        Switch(
            checked = controller.autoRecognize,
            onCheckedChange = { controller.setAutoRecognize(it) },
            enabled = controller.feedSupported
        )
    }

    NovaChoiceGroup(
        title = stringResource(R.string.rec_engine_title),
        options = GoogleRecognizerBridge.Service.values().toList(),
        selected = controller.recognitionService,
        labelOf = { serviceLabel(it) },
        onSelected = { controller.selectRecognitionService(it) }
    )
}

/** The list of detected pieces of speech, each with replay and recognition result. */
@Composable
private fun ColumnScope.UtteranceListSection(controller: MicLabController) {
    if (controller.utterances.isEmpty()) {
        Text(
            text = stringResource(R.string.vad_empty),
            style = MaterialTheme.typography.bodySmall
        )
        return
    }
    Text(
        text = stringResource(R.string.vad_list_title),
        style = MaterialTheme.typography.titleMedium
    )
    controller.utterances.forEach { item ->
        key(item.id) { UtteranceRow(controller, item) }
    }
}

@Composable
private fun UtteranceRow(controller: MicLabController, item: Utterance) {
    val seconds: String = formatSeconds(item.durationMs)
    val cutNote: String =
        if (item.endReason == SegmentEnd.MAX_LENGTH) stringResource(R.string.vad_reason_max) else ""
    val isPlayingThis: Boolean =
        controller.phase == LabPhase.PLAYING && controller.playingUtteranceId == item.id

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = stringResource(R.string.vad_item, item.id, seconds) + cutNote,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f)
            )
            OutlinedButton(
                onClick = { controller.playUtterance(item.id) },
                enabled = controller.phase == LabPhase.IDLE
            ) {
                Text(
                    stringResource(
                        if (isPlayingThis) R.string.vad_item_playing else R.string.vad_item_play
                    )
                )
            }
        }

        when (val status = item.recognition) {
            is RecognitionStatus.NotSent -> {
                OutlinedButton(
                    onClick = { controller.recognize(item.id) },
                    enabled = controller.feedSupported
                ) {
                    Text(stringResource(R.string.rec_send))
                }
            }
            is RecognitionStatus.Sending -> {
                Text(
                    text = stringResource(R.string.rec_sending),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            is RecognitionStatus.Done -> {
                Text(
                    text = stringResource(R.string.rec_result, status.text, formatSeconds(status.latencyMs)),
                    style = MaterialTheme.typography.bodyMedium
                )
                OutlinedButton(onClick = { controller.recognize(item.id) }) {
                    Text(stringResource(R.string.rec_resend))
                }
            }
            is RecognitionStatus.Failed -> {
                Text(
                    text = stringResource(R.string.rec_failed, status.message, formatSeconds(status.latencyMs)),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
                OutlinedButton(onClick = { controller.recognize(item.id) }) {
                    Text(stringResource(R.string.rec_resend))
                }
            }
        }
    }
}

/** For example 3200 gives "৩.২" (Bangla digits, one decimal). */
private fun formatSeconds(milliseconds: Long): String =
    TimeText.digits(String.format(Locale.US, "%.1f", milliseconds / 1000f))

@Composable
private fun profileLabel(profile: CaptureProfile): String = stringResource(
    when (profile) {
        CaptureProfile.CLEAN -> R.string.mic_lab_profile_clean
        CaptureProfile.ECHO_SAFE -> R.string.mic_lab_profile_echo
    }
)

@Composable
private fun sensitivityLabel(value: VadSensitivity): String = stringResource(
    when (value) {
        VadSensitivity.HIGH -> R.string.vad_sens_high
        VadSensitivity.NORMAL -> R.string.vad_sens_normal
        VadSensitivity.LOW -> R.string.vad_sens_low
    }
)

@Composable
private fun pauseLabel(value: PauseTolerance): String = stringResource(
    when (value) {
        PauseTolerance.SHORT -> R.string.vad_pause_short
        PauseTolerance.NORMAL -> R.string.vad_pause_normal
        PauseTolerance.LONG -> R.string.vad_pause_long
    }
)

@Composable
private fun serviceLabel(service: GoogleRecognizerBridge.Service): String = stringResource(
    when (service) {
        GoogleRecognizerBridge.Service.ONLINE -> R.string.rec_engine_online
        GoogleRecognizerBridge.Service.ON_DEVICE -> R.string.rec_engine_on_device
    }
)

@Composable
private fun effectsLine(status: AudioEffectsStatus): String = stringResource(
    R.string.mic_lab_effects,
    effectLabel(status.echoCancel),
    effectLabel(status.noiseSuppress),
    effectLabel(status.autoGain)
)

@Composable
private fun effectLabel(state: EffectState): String = stringResource(
    when (state) {
        EffectState.ON -> R.string.mic_lab_effect_on
        EffectState.AVAILABLE_OFF -> R.string.mic_lab_effect_off
        EffectState.UNAVAILABLE -> R.string.mic_lab_effect_none
    }
)
EOF

# ---------- Commit and push ----------
git add -A
git commit -m "E4: send our own detected speech to Google's recognizer and show the text"
git push

echo "E4 files created and pushed."
