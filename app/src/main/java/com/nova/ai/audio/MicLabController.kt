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
