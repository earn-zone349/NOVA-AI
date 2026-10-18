#!/usr/bin/env bash
# NOVA AI - Engine phase E1: continuous microphone capture foundation and a test card.
# Additive: new audio package; AiBrainScreen gets two new lines (import + card).
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
BRAIN_FILE="$BASE/ui/screens/AiBrainScreen.kt"

for required in \
  "$BRAIN_FILE" \
  "$BASE/ui/components/NovaChoiceGroup.kt" \
  "$BASE/logging/NovaLogger.kt" \
  "$BASE/voice/VoiceEngine.kt"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after P1 to P16 are installed." >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
mkdir -p "$BASE/audio"

# ---------- A. New strings file ----------
cat > app/src/main/res/values/strings_e1.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="mic_lab_title">মাইক পরীক্ষা (ইঞ্জিন E1)</string>
    <string name="mic_lab_note">নতুন একটানা শোনার ইঞ্জিনের ভিত্তি। মাইক চালু করে কথা বলো, বারটি নড়বে। এখনো লেখা বানানো হয় না।</string>
    <string name="mic_lab_start">মাইক চালু করো</string>
    <string name="mic_lab_stop">মাইক বন্ধ করো</string>
    <string name="mic_lab_level">শব্দের মাত্রা</string>
    <string name="mic_lab_profile_title">মাইকের ধরন</string>
    <string name="mic_lab_profile_clean">পরিষ্কার (শোনার জন্য সেরা)</string>
    <string name="mic_lab_profile_echo">ইকো-নিরাপদ (নোভা বলার সময় মাঝে বলার জন্য)</string>
    <string name="mic_lab_effects">ফোনের সুবিধা: ইকো কমানো: %1$s, গোলমাল কমানো: %2$s, ভলিউম সমতা: %3$s</string>
    <string name="mic_lab_effect_on">চালু</string>
    <string name="mic_lab_effect_off">আছে, বন্ধ</string>
    <string name="mic_lab_effect_none">নেই</string>
    <string name="mic_lab_record">৫ সেকেন্ড রেকর্ড করো</string>
    <string name="mic_lab_recording">রেকর্ড হচ্ছে... বলো</string>
    <string name="mic_lab_play">রেকর্ড শোনো</string>
    <string name="mic_lab_playing">বাজছে...</string>
    <string name="mic_lab_clip_ready">রেকর্ড তৈরি: %1$d সেকেন্ড</string>
    <string name="mic_lab_silent">মাইক থেকে কোনো শব্দ আসছে না। অন্য কোনো অ্যাপ মাইক ধরে থাকতে পারে, বা মাইক ঢাকা আছে।</string>
    <string name="mic_lab_permission">মাইকের অনুমতি ছাড়া পরীক্ষা চলবে না।</string>
    <string name="mic_lab_error">মাইক সমস্যা: %1$s</string>
</resources>
EOF

# ---------- 1. AudioConfig.kt ----------
cat > "$BASE/audio/AudioConfig.kt" <<'EOF'
package com.nova.ai.audio

/** Fixed audio format used by the whole listening engine (16 kHz, mono, 16-bit). */
object AudioConfig {
    const val SAMPLE_RATE_HZ: Int = 16_000
    const val BYTES_PER_SAMPLE: Int = 2

    /** One frame is 20 milliseconds of sound (320 samples). */
    const val FRAME_MS: Int = 20
    const val FRAME_SAMPLES: Int = SAMPLE_RATE_HZ * FRAME_MS / 1000

    /** How many seconds of the latest sound are kept in memory. */
    const val RING_SECONDS: Int = 30
    const val RING_CAPACITY_SAMPLES: Int = SAMPLE_RATE_HZ * RING_SECONDS
}
EOF

# ---------- 2. AudioModels.kt ----------
cat > "$BASE/audio/AudioModels.kt" <<'EOF'
package com.nova.ai.audio

import android.media.MediaRecorder

/** How the microphone is opened. */
enum class CaptureProfile(val audioSource: Int) {
    /** Plain voice with no extra processing: best for speech recognition. */
    CLEAN(MediaRecorder.AudioSource.VOICE_RECOGNITION),

    /** Echo and noise reduction switched on: for talking while NOVA is speaking. */
    ECHO_SAFE(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
}

/** State of one sound-improving feature of the phone. */
enum class EffectState {
    /** This phone does not have the feature. */
    UNAVAILABLE,

    /** The phone has it, but it is not switched on. */
    AVAILABLE_OFF,

    /** Switched on. */
    ON
}

/** Which sound-improving features of the phone are available and on. */
data class AudioEffectsStatus(
    val echoCancel: EffectState,
    val noiseSuppress: EffectState,
    val autoGain: EffectState
) {
    companion object {
        val UNKNOWN: AudioEffectsStatus = AudioEffectsStatus(
            EffectState.UNAVAILABLE,
            EffectState.UNAVAILABLE,
            EffectState.UNAVAILABLE
        )
    }
}
EOF

# ---------- 3. PcmRingBuffer.kt ----------
cat > "$BASE/audio/PcmRingBuffer.kt" <<'EOF'
package com.nova.ai.audio

/**
 * Keeps the most recent [capacity] samples of sound. Old sound is overwritten
 * by new sound. Safe to use from several threads.
 */
class PcmRingBuffer(private val capacity: Int) {

    private val data: ShortArray
    private var writeIndex: Int = 0
    private var filled: Int = 0
    private var total: Long = 0L

    init {
        require(capacity > 0) { "capacity must be positive" }
        data = ShortArray(capacity)
    }

    /** Adds the first [length] samples of [frame]. */
    @Synchronized
    fun write(frame: ShortArray, length: Int) {
        val count: Int = length.coerceIn(0, frame.size)
        // If more than the whole buffer arrives at once, only the newest part is kept.
        var source: Int = if (count > capacity) count - capacity else 0
        var remaining: Int = count - source

        while (remaining > 0) {
            val chunk: Int = minOf(remaining, capacity - writeIndex)
            System.arraycopy(frame, source, data, writeIndex, chunk)
            writeIndex = (writeIndex + chunk) % capacity
            source += chunk
            remaining -= chunk
        }
        filled = minOf(capacity, filled + count)
        total += count
    }

    /** Returns a copy of the newest [sampleCount] samples (fewer if not enough is stored). */
    @Synchronized
    fun readLast(sampleCount: Int): ShortArray {
        val count: Int = sampleCount.coerceIn(0, filled)
        val result = ShortArray(count)
        var readIndex: Int = (writeIndex - count + capacity) % capacity
        var destination = 0
        var remaining: Int = count

        while (remaining > 0) {
            val chunk: Int = minOf(remaining, capacity - readIndex)
            System.arraycopy(data, readIndex, result, destination, chunk)
            readIndex = (readIndex + chunk) % capacity
            destination += chunk
            remaining -= chunk
        }
        return result
    }

    /** How many samples are stored right now. */
    @Synchronized
    fun availableSamples(): Int = filled

    /** How many samples were written since the buffer was created. */
    @Synchronized
    fun totalWritten(): Long = total

    /** Forgets all stored sound. */
    @Synchronized
    fun clear() {
        writeIndex = 0
        filled = 0
    }
}
EOF

# ---------- 4. AudioLevel.kt ----------
cat > "$BASE/audio/AudioLevel.kt" <<'EOF'
package com.nova.ai.audio

import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sqrt

/** Measures how loud a piece of sound is, on a 0 to 1 scale (0 = silence, 1 = loudest). */
object AudioLevel {

    /** Loudness of one frame: average strength and strongest moment. */
    data class Reading(val level: Float, val peak: Float)

    private const val FULL_SCALE: Double = 32768.0
    private const val FLOOR_DB: Double = -60.0

    /** Measures the first [length] samples of [frame]. */
    fun measure(frame: ShortArray, length: Int): Reading {
        val count: Int = length.coerceIn(0, frame.size)
        if (count == 0) return Reading(0f, 0f)

        var sumSquares = 0.0
        var strongest = 0
        for (index in 0 until count) {
            val value: Int = frame[index].toInt()
            sumSquares += (value * value).toDouble()
            val magnitude: Int = abs(value)
            if (magnitude > strongest) strongest = magnitude
        }
        val rms: Double = sqrt(sumSquares / count)
        return Reading(toUnit(rms), toUnit(strongest.toDouble()))
    }

    /** Converts strength to decibels, then to 0 to 1 (−60 dB or quieter is 0). */
    private fun toUnit(amplitude: Double): Float {
        if (amplitude <= 0.0) return 0f
        val decibels: Double = 20.0 * log10(amplitude / FULL_SCALE)
        return ((decibels - FLOOR_DB) / -FLOOR_DB).toFloat().coerceIn(0f, 1f)
    }
}
EOF

# ---------- 5. AudioCaptureEngine.kt ----------
cat > "$BASE/audio/AudioCaptureEngine.kt" <<'EOF'
package com.nova.ai.audio

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AudioEffect
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import androidx.core.content.ContextCompat
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaError
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * Keeps the microphone open and reads sound continuously on its own thread.
 * Every frame goes into [buffer] (the last 30 seconds) and to an optional
 * frame consumer (used by speech detection in the next phase).
 * Level and error events reach the [Listener] on the main thread.
 * Sound is never saved to storage or logged.
 */
class AudioCaptureEngine(context: Context) {

    /** Receives events on the main thread. */
    interface Listener {
        fun onLevel(level: Float, peak: Float)
        fun onError(error: NovaError)
    }

    private class AttachedEffects(val effects: List<AudioEffect>, val status: AudioEffectsStatus)

    private val appContext: Context = context.applicationContext
    private val mainHandler: Handler = Handler(Looper.getMainLooper())

    /** The newest sound, always the last [AudioConfig.RING_SECONDS] seconds. */
    val buffer: PcmRingBuffer = PcmRingBuffer(AudioConfig.RING_CAPACITY_SAMPLES)

    @Volatile
    private var running: Boolean = false

    @Volatile
    private var frameConsumer: ((ShortArray, Int) -> Unit)? = null

    private var record: AudioRecord? = null
    private var captureThread: Thread? = null
    private var activeEffects: List<AudioEffect> = emptyList()

    /** Which sound-improving features are available and on, since the last start. */
    @Volatile
    var effectsStatus: AudioEffectsStatus = AudioEffectsStatus.UNKNOWN
        private set

    /** True while the microphone is open. */
    fun isRunning(): Boolean = running

    /**
     * Sets a function that receives every frame on the capture thread (null removes it).
     * It must be fast and must not keep the frame array after returning.
     */
    fun setFrameConsumer(consumer: ((ShortArray, Int) -> Unit)?) {
        frameConsumer = consumer
    }

    /** Opens the microphone. A failure result carries a Bangla message. */
    @Synchronized
    fun start(profile: CaptureProfile, listener: Listener): NovaResult<Unit> {
        if (record != null) return NovaResult.Success(Unit)

        val micGranted: Boolean = ContextCompat.checkSelfPermission(
            appContext, Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        if (!micGranted) {
            return NovaResult.failure(ErrorCode.PERMISSION_DENIED, "মাইক্রোফোনের অনুমতি নেই।")
        }

        val minBufferBytes: Int = AudioRecord.getMinBufferSize(
            AudioConfig.SAMPLE_RATE_HZ,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBufferBytes <= 0) {
            return NovaResult.failure(
                ErrorCode.NOT_AVAILABLE,
                "এই ফোনে এই মানের মাইক ধরা যাচ্ছে না।"
            )
        }
        val bufferBytes: Int = maxOf(
            minBufferBytes,
            AudioConfig.FRAME_SAMPLES * AudioConfig.BYTES_PER_SAMPLE * BUFFER_FRAMES
        )

        val created: AudioRecord = try {
            AudioRecord.Builder()
                .setAudioSource(profile.audioSource)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(AudioConfig.SAMPLE_RATE_HZ)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .build()
                )
                .setBufferSizeInBytes(bufferBytes)
                .build()
        } catch (e: SecurityException) {
            NovaLogger.w(TAG, "Microphone access refused", e)
            return NovaResult.failure(ErrorCode.PERMISSION_DENIED, "মাইক্রোফোনের অনুমতি নেই।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to create the recorder", e)
            return NovaResult.failure(ErrorCode.EXECUTION_FAILED, "মাইক চালু করা যায়নি।", e)
        }

        if (created.state != AudioRecord.STATE_INITIALIZED) {
            created.release()
            return NovaResult.failure(ErrorCode.NOT_AVAILABLE, "মাইক প্রস্তুত হয়নি।")
        }

        val attached: AttachedEffects = attachEffects(
            sessionId = created.audioSessionId,
            enableProcessing = profile == CaptureProfile.ECHO_SAFE
        )

        try {
            created.startRecording()
        } catch (e: IllegalStateException) {
            NovaLogger.e(TAG, "Failed to start recording", e)
            releaseEffects(attached.effects)
            created.release()
            return NovaResult.failure(ErrorCode.EXECUTION_FAILED, "মাইক চালু করা যায়নি।", e)
        }

        if (created.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            releaseEffects(attached.effects)
            created.release()
            return NovaResult.failure(
                ErrorCode.NOT_AVAILABLE,
                "মাইক এখন অন্য কাজে ব্যস্ত। অন্য অ্যাপ বন্ধ করে আবার চেষ্টা করো।"
            )
        }

        buffer.clear()
        record = created
        activeEffects = attached.effects
        effectsStatus = attached.status
        running = true

        val thread = Thread({ captureLoop(created, listener) }, THREAD_NAME)
        captureThread = thread
        thread.start()

        NovaLogger.i(TAG, "Microphone opened (profile=$profile)")
        return NovaResult.Success(Unit)
    }

    /** Closes the microphone. Safe to call at any time, also more than once. */
    @Synchronized
    fun stop() {
        running = false
        val current: AudioRecord = record ?: return
        record = null

        try {
            current.stop()
        } catch (e: IllegalStateException) {
            NovaLogger.w(TAG, "Recorder was already stopped", e)
        }

        val thread: Thread? = captureThread
        captureThread = null
        if (thread != null && thread !== Thread.currentThread()) {
            try {
                thread.join(JOIN_TIMEOUT_MS)
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }

        releaseEffects(activeEffects)
        activeEffects = emptyList()
        try {
            current.release()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to release the recorder", e)
        }
        NovaLogger.i(TAG, "Microphone closed")
    }

    private fun captureLoop(source: AudioRecord, listener: Listener) {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)

        val frame = ShortArray(AudioConfig.FRAME_SAMPLES)
        var heldLevel = 0f
        var heldPeak = 0f
        var lastReportMs = 0L

        while (running) {
            val readCount: Int = source.read(frame, 0, frame.size)
            if (readCount < 0) {
                if (running) reportCaptureFailure(listener, readCount)
                return
            }
            if (readCount == 0) continue

            buffer.write(frame, readCount)
            deliverFrame(frame, readCount)

            // The meter falls slowly, so short sounds stay visible for a moment.
            val reading: AudioLevel.Reading = AudioLevel.measure(frame, readCount)
            heldLevel = maxOf(reading.level, heldLevel * HOLD_DECAY)
            heldPeak = maxOf(reading.peak, heldPeak * HOLD_DECAY)

            val now: Long = SystemClock.elapsedRealtime()
            if (now - lastReportMs >= REPORT_INTERVAL_MS) {
                lastReportMs = now
                val levelToShow: Float = heldLevel
                val peakToShow: Float = heldPeak
                mainHandler.post {
                    if (running) listener.onLevel(levelToShow, peakToShow)
                }
            }
        }
    }

    private fun deliverFrame(frame: ShortArray, count: Int) {
        val consumer: ((ShortArray, Int) -> Unit) = frameConsumer ?: return
        try {
            consumer(frame, count)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Frame consumer failed", e)
        }
    }

    private fun reportCaptureFailure(listener: Listener, code: Int) {
        NovaLogger.e(TAG, "Microphone read failed (code=$code)")
        val error = NovaError(ErrorCode.EXECUTION_FAILED, "মাইক থেকে শব্দ পড়তে সমস্যা হয়েছে।")
        mainHandler.post {
            listener.onError(error)
            stop()
        }
    }

    /**
     * Looks for the phone's sound-improving features. Echo and noise reduction are
     * switched on only when [enableProcessing] is true. Automatic gain is never
     * switched on, because it raises background noise and hurts speech detection.
     */
    private fun attachEffects(sessionId: Int, enableProcessing: Boolean): AttachedEffects {
        val created = ArrayList<AudioEffect>()

        val echo: EffectState = tryAttach(
            available = AcousticEchoCanceler.isAvailable(),
            enable = enableProcessing,
            created = created
        ) { AcousticEchoCanceler.create(sessionId) }

        val noise: EffectState = tryAttach(
            available = NoiseSuppressor.isAvailable(),
            enable = enableProcessing,
            created = created
        ) { NoiseSuppressor.create(sessionId) }

        val gain: EffectState =
            if (AutomaticGainControl.isAvailable()) EffectState.AVAILABLE_OFF else EffectState.UNAVAILABLE

        return AttachedEffects(created, AudioEffectsStatus(echo, noise, gain))
    }

    private fun tryAttach(
        available: Boolean,
        enable: Boolean,
        created: MutableList<AudioEffect>,
        factory: () -> AudioEffect?
    ): EffectState {
        if (!available) return EffectState.UNAVAILABLE
        if (!enable) return EffectState.AVAILABLE_OFF
        return try {
            val effect: AudioEffect? = factory()
            if (effect == null) {
                EffectState.AVAILABLE_OFF
            } else {
                effect.setEnabled(true)
                created.add(effect)
                if (effect.getEnabled()) EffectState.ON else EffectState.AVAILABLE_OFF
            }
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not switch on a sound feature", e)
            EffectState.AVAILABLE_OFF
        }
    }

    private fun releaseEffects(effects: List<AudioEffect>) {
        for (effect in effects) {
            try {
                effect.release()
            } catch (e: Exception) {
                NovaLogger.e(TAG, "Failed to release a sound feature", e)
            }
        }
    }

    private companion object {
        const val TAG: String = "AudioCaptureEngine"
        const val THREAD_NAME: String = "nova-audio-capture"
        const val BUFFER_FRAMES: Int = 8
        const val REPORT_INTERVAL_MS: Long = 50L
        const val JOIN_TIMEOUT_MS: Long = 500L
        const val HOLD_DECAY: Float = 0.85f
    }
}
EOF

# ---------- 6. ClipPlayer.kt ----------
cat > "$BASE/audio/ClipPlayer.kt" <<'EOF'
package com.nova.ai.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/** Plays a short recorded clip (16 kHz, mono) so the user can hear what the microphone caught. */
class ClipPlayer {

    private var track: AudioTrack? = null

    /** Starts playing [samples]. Returns the length of the clip in milliseconds. */
    @Synchronized
    fun play(samples: ShortArray): NovaResult<Long> {
        if (samples.isEmpty()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, "শোনানোর মতো রেকর্ড নেই।")
        }
        stop()

        return try {
            val sizeBytes: Int = samples.size * AudioConfig.BYTES_PER_SAMPLE
            val created: AudioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(AudioConfig.SAMPLE_RATE_HZ)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(sizeBytes)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()

            val written: Int = created.write(samples, 0, samples.size)
            if (written != samples.size) {
                created.release()
                return NovaResult.failure(ErrorCode.EXECUTION_FAILED, "রেকর্ড বাজাতে সমস্যা হয়েছে।")
            }
            created.play()
            track = created
            NovaResult.Success(samples.size * MILLIS_PER_SECOND / AudioConfig.SAMPLE_RATE_HZ)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to play the clip", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "রেকর্ড বাজাতে সমস্যা হয়েছে।", e)
        }
    }

    /** Stops playing and frees the player. Safe to call at any time. */
    @Synchronized
    fun stop() {
        val current: AudioTrack = track ?: return
        track = null
        try {
            current.stop()
        } catch (e: IllegalStateException) {
            NovaLogger.w(TAG, "Player was already stopped", e)
        }
        try {
            current.release()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to release the player", e)
        }
    }

    private companion object {
        const val TAG: String = "ClipPlayer"
        const val MILLIS_PER_SECOND: Long = 1000L
    }
}
EOF

# ---------- 7. MicLabController.kt ----------
cat > "$BASE/audio/MicLabController.kt" <<'EOF'
package com.nova.ai.audio

import android.content.Context
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.R
import com.nova.ai.core.NovaResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** What the test card is doing with the sound. */
enum class LabPhase { IDLE, RECORDING, PLAYING }

/**
 * Screen-side holder for the microphone test card: starts and stops the
 * microphone, shows the level, records a 5-second clip and plays it back.
 * Use from the main thread.
 */
class MicLabController(
    context: Context,
    private val scope: CoroutineScope
) {

    private val appContext: Context = context.applicationContext
    private val engine = AudioCaptureEngine(appContext)
    private val player = ClipPlayer()

    private var clipJob: Job? = null
    private var lastClip: ShortArray? = null
    private var lastSignalMs: Long = 0L

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

    private val listener = object : AudioCaptureEngine.Listener {
        override fun onLevel(level: Float, peak: Float) {
            meterLevel = level
            val now: Long = SystemClock.elapsedRealtime()
            if (peak > SILENCE_PEAK) {
                lastSignalMs = now
                silentWarning = false
            } else if (now - lastSignalMs > SILENT_WARNING_MS) {
                silentWarning = true
            }
        }

        override fun onError(error: com.nova.ai.core.NovaError) {
            errorMessage = error.message
            stop()
        }
    }

    /** Opens the microphone with the chosen [profile]. */
    fun start() {
        errorMessage = null
        when (val result: NovaResult<Unit> = engine.start(profile, listener)) {
            is NovaResult.Success -> {
                isRunning = true
                effects = engine.effectsStatus
                lastSignalMs = SystemClock.elapsedRealtime()
                silentWarning = false
            }
            is NovaResult.Failure -> {
                isRunning = false
                errorMessage = result.error.message
            }
        }
    }

    /** Closes the microphone and stops any recording or playback. */
    fun stop() {
        clipJob?.cancel()
        clipJob = null
        player.stop()
        engine.stop()
        isRunning = false
        meterLevel = 0f
        silentWarning = false
        phase = LabPhase.IDLE
    }

    /** Switches the microphone type; restarts the microphone if it is running. */
    fun selectProfile(newProfile: CaptureProfile) {
        if (newProfile == profile) return
        val wasRunning: Boolean = isRunning
        if (wasRunning) stop()
        profile = newProfile
        if (wasRunning) start()
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

    /** Plays the recorded clip. */
    fun playClip() {
        val clip: ShortArray = lastClip ?: return
        if (phase != LabPhase.IDLE) return
        when (val result: NovaResult<Long> = player.play(clip)) {
            is NovaResult.Success -> {
                phase = LabPhase.PLAYING
                val durationMs: Long = result.value
                clipJob = scope.launch {
                    delay(durationMs + PLAYBACK_PADDING_MS)
                    player.stop()
                    phase = LabPhase.IDLE
                }
            }
            is NovaResult.Failure -> errorMessage = result.error.message
        }
    }

    /** The user refused the microphone permission. */
    fun reportPermissionDenied() {
        errorMessage = appContext.getString(R.string.mic_lab_permission)
    }

    /** Releases everything. Call when the screen is gone. */
    fun release() {
        stop()
    }

    private companion object {
        const val CLIP_SECONDS: Int = 5
        const val CLIP_MS: Long = CLIP_SECONDS * 1000L
        const val CLIP_SAMPLES: Int = CLIP_SECONDS * AudioConfig.SAMPLE_RATE_HZ
        const val PLAYBACK_PADDING_MS: Long = 250L
        const val SILENCE_PEAK: Float = 0.01f
        const val SILENT_WARNING_MS: Long = 3_000L
    }
}
EOF

# ---------- 8. MicLabCard.kt ----------
cat > "$BASE/ui/components/MicLabCard.kt" <<'EOF'
package com.nova.ai.ui.components

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import com.nova.ai.audio.LabPhase
import com.nova.ai.audio.MicLabController
import kotlinx.coroutines.CoroutineScope

/**
 * Test card for the new listening engine: switch the microphone on, watch the
 * level move, compare the two microphone types, and record and replay 5 seconds.
 * The microphone closes when the app goes to the background or the screen is left.
 */
@Composable
fun MicLabCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val scope: CoroutineScope = rememberCoroutineScope()
    val controller: MicLabController = remember { MicLabController(context, scope) }

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
                            if (controller.phase == LabPhase.PLAYING) {
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

@Composable
private fun profileLabel(profile: CaptureProfile): String = stringResource(
    when (profile) {
        CaptureProfile.CLEAN -> R.string.mic_lab_profile_clean
        CaptureProfile.ECHO_SAFE -> R.string.mic_lab_profile_echo
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

# ---------- B. AiBrainScreen.kt: two additive lines (idempotent) ----------
if ! grep -q "MicLabCard" "$BRAIN_FILE"; then
  grep -q '^import com.nova.ai.ui.components.NovaChoiceGroup$' "$BRAIN_FILE" \
    || { echo "ERROR: AiBrainScreen anchor (import) not found" >&2; exit 1; }
  grep -q 'body = stringResource(R.string.brain_language_body)' "$BRAIN_FILE" \
    || { echo "ERROR: AiBrainScreen anchor (card) not found" >&2; exit 1; }

  cat > "$TMP_DIR/brain_import.txt" <<'EOF'
import com.nova.ai.ui.components.MicLabCard
EOF
  cat > "$TMP_DIR/brain_card.txt" <<'EOF'

        MicLabCard()
EOF
  sed -i "/^import com.nova.ai.ui.components.NovaChoiceGroup$/r $TMP_DIR/brain_import.txt" "$BRAIN_FILE"
  sed -i -e "/body = stringResource(R.string.brain_language_body)/{n;r $TMP_DIR/brain_card.txt" -e "}" "$BRAIN_FILE"
fi
grep -q "^import com.nova.ai.ui.components.MicLabCard$" "$BRAIN_FILE" || { echo "ERROR: AiBrainScreen edit failed (import)" >&2; exit 1; }
grep -q "^        MicLabCard()$" "$BRAIN_FILE" || { echo "ERROR: AiBrainScreen edit failed (card)" >&2; exit 1; }

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "E1: continuous microphone capture engine and test card"
git push

echo "E1 files created and pushed."
