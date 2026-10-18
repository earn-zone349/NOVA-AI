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
