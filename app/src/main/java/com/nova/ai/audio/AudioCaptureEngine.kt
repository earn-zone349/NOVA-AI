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
