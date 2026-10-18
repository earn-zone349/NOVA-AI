#!/usr/bin/env bash
# NOVA AI - Engine phase E2: speech start/end detection (adaptive VAD and utterance cutting).
# Additive: new audio classes; MicLabController and MicLabCard are rewritten with every E1 feature kept.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"

for required in \
  "$BASE/audio/AudioCaptureEngine.kt" \
  "$BASE/audio/MicLabController.kt" \
  "$BASE/audio/ClipPlayer.kt" \
  "$BASE/ui/components/MicLabCard.kt" \
  "$BASE/ui/components/NovaChoiceGroup.kt" \
  "$BASE/time/TimeText.kt"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after E1 is installed." >&2
    exit 1
  fi
done

# ---------- A. New strings file ----------
cat > app/src/main/res/values/strings_e2.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="vad_title">কথা ধরা (ইঞ্জিন E2)</string>
    <string name="vad_note">ইঞ্জিন নিজে বোঝে কখন তুমি কথা শুরু ও শেষ করলে। মাইক চালু করে কথা বলো, থামো, আবার বলো।</string>
    <string name="vad_status_speaking">🟢 কথা চলছে</string>
    <string name="vad_status_quiet">⚪ চুপ</string>
    <string name="vad_noise">পরিবেশের গোলমাল: %1$d ডিবি</string>

    <string name="vad_sensitivity_title">সংবেদনশীলতা</string>
    <string name="vad_sens_high">বেশি (শান্ত ঘর, নরম কথা)</string>
    <string name="vad_sens_normal">স্বাভাবিক</string>
    <string name="vad_sens_low">কম (গোলমালের জায়গা)</string>

    <string name="vad_pause_title">কথার মাঝের বিরতি</string>
    <string name="vad_pause_short">ছোট (০.৫ সেকেন্ড, দ্রুত সাড়া)</string>
    <string name="vad_pause_normal">স্বাভাবিক (০.৭ সেকেন্ড)</string>
    <string name="vad_pause_long">লম্বা (১ সেকেন্ড, ধীরে বলার জন্য)</string>

    <string name="vad_count">ধরা কথা: %1$d টি, বাদ দেওয়া ছোট গোলমাল: %2$d টি</string>
    <string name="vad_list_title">সর্বশেষ ধরা কথা</string>
    <string name="vad_empty">এখনো কোনো কথা ধরা হয়নি।</string>
    <string name="vad_item">কথা %1$d: %2$s সেকেন্ড</string>
    <string name="vad_reason_max"> (লম্বা হওয়ায় কাটা)</string>
    <string name="vad_item_play">শোনো</string>
    <string name="vad_item_playing">বাজছে...</string>
</resources>
EOF

# ---------- 1. VadConfig.kt ----------
cat > "$BASE/audio/VadConfig.kt" <<'EOF'
package com.nova.ai.audio

/** How easily speech is detected. Margins are how many dB above the room noise counts as speech. */
enum class VadSensitivity(val startMarginDb: Float, val continueMarginDb: Float) {
    /** Catches soft speech in a quiet room, but may react to small noises. */
    HIGH(8f, 5f),

    /** Balanced. */
    NORMAL(12f, 8f),

    /** Ignores more noise, but soft speech may be missed. */
    LOW(16f, 11f)
}

/** How long a pause must last before the speech is considered finished. */
enum class PauseTolerance(val endSilenceMs: Int) {
    SHORT(500),
    NORMAL(700),
    LONG(1000)
}

/** All settings of the speech detector. */
data class VadConfig(
    val sensitivity: VadSensitivity = VadSensitivity.NORMAL,
    val pause: PauseTolerance = PauseTolerance.NORMAL,

    /** Loud sound must last this long before speech is considered started. */
    val minStartMs: Int = 100,

    /** Shorter sounds are thrown away as noise. */
    val minSpeechMs: Int = 250,

    /** Sound from just before the start is kept, so the first word is not cut. */
    val preRollMs: Int = 300,

    /** How much quiet is kept at the end of a piece of speech. */
    val tailKeepMs: Int = 250,

    /** A very long speech is cut into pieces of this length. */
    val maxUtteranceMs: Int = 25_000
)
EOF

# ---------- 2. FrameEnergy.kt ----------
cat > "$BASE/audio/FrameEnergy.kt" <<'EOF'
package com.nova.ai.audio

import kotlin.math.log10
import kotlin.math.sqrt

/** Measures the strength of a frame in dBFS (0 is the loudest possible, −90 is silence). */
object FrameEnergy {

    const val SILENCE_DB: Float = -90f
    private const val FULL_SCALE: Double = 32768.0

    /** Strength of the first [length] samples of [frame]. */
    fun rmsDb(frame: ShortArray, length: Int): Float {
        val count: Int = length.coerceIn(0, frame.size)
        if (count == 0) return SILENCE_DB

        var sumSquares = 0.0
        for (index in 0 until count) {
            val value: Int = frame[index].toInt()
            sumSquares += (value * value).toDouble()
        }
        val rms: Double = sqrt(sumSquares / count)
        if (rms < 1.0) return SILENCE_DB
        return maxOf(SILENCE_DB, (20.0 * log10(rms / FULL_SCALE)).toFloat())
    }
}
EOF

# ---------- 3. SpeechModels.kt ----------
cat > "$BASE/audio/SpeechModels.kt" <<'EOF'
package com.nova.ai.audio

/** Why a piece of speech ended. */
enum class SegmentEnd {
    /** The speaker paused long enough. */
    SILENCE,

    /** The speech got too long and was cut here (the speaker may still be talking). */
    MAX_LENGTH,

    /** The microphone was closed in the middle of speech. */
    STOPPED
}

/** One piece of speech: the sound (16 kHz, mono) and how long it is. */
class SpeechSegment(
    val samples: ShortArray,
    val durationMs: Long,
    val endReason: SegmentEnd
)

/** What the detector found. */
sealed class SpeechEvent {
    /** Speech began. */
    object Started : SpeechEvent()

    /** A piece of speech is complete. */
    class Ended(val segment: SpeechSegment) : SpeechEvent()

    /** A short sound was thrown away as noise. */
    class Discarded(val durationMs: Long) : SpeechEvent()
}
EOF

# ---------- 4. SampleAccumulator.kt ----------
cat > "$BASE/audio/SampleAccumulator.kt" <<'EOF'
package com.nova.ai.audio

/** A growing list of sound samples. Not thread-safe: use from one thread. */
internal class SampleAccumulator(initialCapacity: Int) {

    private var data: ShortArray = ShortArray(maxOf(1, initialCapacity))

    /** How many samples are stored. */
    var size: Int = 0
        private set

    /** Adds the first [length] samples of [source]. */
    fun append(source: ShortArray, length: Int) {
        val count: Int = length.coerceIn(0, source.size)
        ensureCapacity(size + count)
        System.arraycopy(source, 0, data, size, count)
        size += count
    }

    /** Removes the last [count] samples. */
    fun trimEnd(count: Int) {
        size = (size - count.coerceAtLeast(0)).coerceAtLeast(0)
    }

    /** A copy of the stored samples. */
    fun toArray(): ShortArray = data.copyOf(size)

    /** Forgets all samples (the memory is kept for reuse). */
    fun clear() {
        size = 0
    }

    private fun ensureCapacity(needed: Int) {
        if (needed <= data.size) return
        var capacity: Int = data.size * 2
        while (capacity < needed) capacity *= 2
        data = data.copyOf(capacity)
    }
}
EOF

# ---------- 5. SpeechSegmenter.kt ----------
cat > "$BASE/audio/SpeechSegmenter.kt" <<'EOF'
package com.nova.ai.audio

private fun msToSamples(milliseconds: Int): Int = milliseconds * AudioConfig.SAMPLE_RATE_HZ / 1000

private fun samplesToMs(samples: Int): Long = samples * 1000L / AudioConfig.SAMPLE_RATE_HZ

/**
 * Cuts a stream of sound frames into pieces of speech. Pure logic, no Android needed.
 *
 * How it works:
 * 1. The first 0.6 seconds measure the room noise. Afterwards the noise level keeps
 *    adjusting during quiet moments.
 * 2. Sound clearly above the noise, for long enough, means speech started. The sound
 *    just before it is kept, so the first word is not cut.
 * 3. A pause of the chosen length means speech ended. Very short sounds are thrown
 *    away as noise, and very long speech is cut into pieces.
 *
 * Use [process] from one thread only. [config] may be changed from another thread.
 */
class SpeechSegmenter(initialConfig: VadConfig = VadConfig()) {

    private enum class Mode { WAITING, SPEAKING }

    /** Current settings. Changes apply from the next frame. */
    @Volatile
    var config: VadConfig = initialConfig

    /** The room noise level now, in dBFS. */
    @Volatile
    var noiseFloorDb: Float = INITIAL_NOISE_FLOOR_DB
        private set

    /** True while a piece of speech is being collected. */
    @Volatile
    var isSpeaking: Boolean = false
        private set

    private var mode: Mode = Mode.WAITING
    private var calibrationLeft: Int = msToSamples(CALIBRATION_MS)
    private val preRoll = ArrayDeque<ShortArray>()
    private var preRollSamples: Int = 0
    private var voicedRun: Int = 0
    private val segment = SampleAccumulator(INITIAL_SEGMENT_SAMPLES)
    private var voicedInSegment: Int = 0
    private var silenceRun: Int = 0

    /** Handles one frame. Returns an event if something happened, otherwise null. */
    fun process(frame: ShortArray, length: Int): SpeechEvent? {
        val count: Int = length.coerceIn(0, frame.size)
        if (count == 0) return null

        val currentConfig: VadConfig = config
        val db: Float = FrameEnergy.rmsDb(frame, count)
        return when (mode) {
            Mode.WAITING -> processWaiting(frame, count, db, currentConfig)
            Mode.SPEAKING -> processSpeaking(frame, count, db, currentConfig)
        }
    }

    /** Ends the speech in progress (if any). Call when the microphone is closed. */
    fun flush(): SpeechEvent? {
        if (mode != Mode.SPEAKING) return null
        return finishSegment(SegmentEnd.STOPPED, config)
    }

    /** Forgets everything and measures the room noise again. */
    fun reset() {
        mode = Mode.WAITING
        calibrationLeft = msToSamples(CALIBRATION_MS)
        preRoll.clear()
        preRollSamples = 0
        voicedRun = 0
        segment.clear()
        voicedInSegment = 0
        silenceRun = 0
        isSpeaking = false
        noiseFloorDb = INITIAL_NOISE_FLOOR_DB
    }

    // ---------------------------------------------------------------- waiting for speech

    private fun processWaiting(
        frame: ShortArray,
        count: Int,
        db: Float,
        cfg: VadConfig
    ): SpeechEvent? {
        pushPreRoll(frame, count, cfg)

        // At the start, learn the room noise quickly and do not react to anything.
        if (calibrationLeft > 0) {
            calibrationLeft -= count
            adjustNoiseFloor(db, CALIBRATION_RATE, CALIBRATION_RATE)
            return null
        }

        if (db > startThresholdDb(cfg)) {
            voicedRun += count
        } else {
            voicedRun = 0
            adjustNoiseFloor(db, FLOOR_FALL_RATE, FLOOR_RISE_RATE)
        }

        if (voicedRun >= msToSamples(cfg.minStartMs)) {
            beginSpeech()
            return SpeechEvent.Started
        }
        return null
    }

    private fun beginSpeech() {
        segment.clear()
        for (kept in preRoll) segment.append(kept, kept.size)
        preRoll.clear()
        preRollSamples = 0

        voicedInSegment = voicedRun
        voicedRun = 0
        silenceRun = 0
        mode = Mode.SPEAKING
        isSpeaking = true
    }

    private fun pushPreRoll(frame: ShortArray, count: Int, cfg: VadConfig) {
        preRoll.addLast(frame.copyOf(count))
        preRollSamples += count

        // Keep the newest sound: the pre-roll plus the loud stretch that triggers the start.
        val limit: Int = msToSamples(cfg.preRollMs + cfg.minStartMs)
        while (preRollSamples - preRoll.first().size >= limit) {
            preRollSamples -= preRoll.removeFirst().size
        }
    }

    // ---------------------------------------------------------------- collecting speech

    private fun processSpeaking(
        frame: ShortArray,
        count: Int,
        db: Float,
        cfg: VadConfig
    ): SpeechEvent? {
        segment.append(frame, count)

        if (db > continueThresholdDb(cfg)) {
            voicedInSegment += count
            silenceRun = 0
        } else {
            silenceRun += count
        }

        if (silenceRun >= msToSamples(cfg.pause.endSilenceMs)) {
            return finishSegment(SegmentEnd.SILENCE, cfg)
        }
        if (segment.size >= msToSamples(cfg.maxUtteranceMs)) {
            return finishSegment(SegmentEnd.MAX_LENGTH, cfg)
        }
        return null
    }

    private fun finishSegment(reason: SegmentEnd, cfg: VadConfig): SpeechEvent {
        // Keep only a short stretch of the quiet at the end.
        val tailKeep: Int = msToSamples(cfg.tailKeepMs)
        if (silenceRun > tailKeep) segment.trimEnd(silenceRun - tailKeep)

        val enoughSpeech: Boolean = voicedInSegment >= msToSamples(cfg.minSpeechMs)
        val event: SpeechEvent = if (enoughSpeech) {
            SpeechEvent.Ended(SpeechSegment(segment.toArray(), samplesToMs(segment.size), reason))
        } else {
            SpeechEvent.Discarded(samplesToMs(voicedInSegment))
        }

        segment.clear()
        voicedInSegment = 0
        silenceRun = 0

        // A cut because of length means the speaker is probably still talking: keep going.
        if (reason != SegmentEnd.MAX_LENGTH) {
            mode = Mode.WAITING
            voicedRun = 0
            isSpeaking = false
        }
        return event
    }

    // ---------------------------------------------------------------- thresholds

    private fun startThresholdDb(cfg: VadConfig): Float =
        (noiseFloorDb + cfg.sensitivity.startMarginDb).coerceIn(MIN_START_DB, MAX_START_DB)

    private fun continueThresholdDb(cfg: VadConfig): Float =
        (noiseFloorDb + cfg.sensitivity.continueMarginDb).coerceIn(MIN_CONTINUE_DB, MAX_CONTINUE_DB)

    /** Moves the noise level toward [db]: [fallRate] when quieter, [riseRate] when louder. */
    private fun adjustNoiseFloor(db: Float, fallRate: Float, riseRate: Float) {
        val rate: Float = if (db < noiseFloorDb) fallRate else riseRate
        noiseFloorDb = (noiseFloorDb + (db - noiseFloorDb) * rate)
            .coerceIn(MIN_NOISE_FLOOR_DB, MAX_NOISE_FLOOR_DB)
    }

    private companion object {
        const val INITIAL_NOISE_FLOOR_DB: Float = -55f
        const val MIN_NOISE_FLOOR_DB: Float = -85f
        const val MAX_NOISE_FLOOR_DB: Float = -30f

        const val MIN_START_DB: Float = -48f
        const val MAX_START_DB: Float = -22f
        const val MIN_CONTINUE_DB: Float = -52f
        const val MAX_CONTINUE_DB: Float = -26f

        const val CALIBRATION_MS: Int = 600
        const val CALIBRATION_RATE: Float = 0.15f
        const val FLOOR_FALL_RATE: Float = 0.2f
        const val FLOOR_RISE_RATE: Float = 0.02f

        const val INITIAL_SEGMENT_SAMPLES: Int = AudioConfig.SAMPLE_RATE_HZ * 2
    }
}
EOF

# ---------- 6. SpeechDetector.kt ----------
cat > "$BASE/audio/SpeechDetector.kt" <<'EOF'
package com.nova.ai.audio

import android.os.Handler
import android.os.Looper
import com.nova.ai.logging.NovaLogger

/**
 * Connects the speech segmenter to the live microphone: it listens to every frame
 * of an [AudioCaptureEngine] and tells a [Listener] when speech starts and ends.
 * Events reach the listener on the main thread. Sound is never saved or logged.
 */
class SpeechDetector(
    private val engine: AudioCaptureEngine,
    config: VadConfig = VadConfig()
) {

    /** Receives speech events on the main thread. */
    interface Listener {
        fun onSpeechStarted()
        fun onSpeechEnded(segment: SpeechSegment)
        fun onSpeechDiscarded(durationMs: Long)
    }

    private val segmenter = SpeechSegmenter(config)
    private val mainHandler: Handler = Handler(Looper.getMainLooper())

    @Volatile
    private var listener: Listener? = null

    /** Starts watching the microphone. Call after the engine has started. */
    fun attach(newListener: Listener) {
        segmenter.reset()
        listener = newListener
        engine.setFrameConsumer { frame, count -> onFrame(frame, count) }
    }

    /**
     * Stops watching. Call after the engine has stopped. Speech that was still in
     * progress is delivered as a last piece.
     */
    fun detach() {
        engine.setFrameConsumer(null)
        val lastEvent: SpeechEvent? = segmenter.flush()
        val current: Listener? = listener
        listener = null
        segmenter.reset()
        if (lastEvent != null && current != null) deliver(lastEvent, current)
    }

    /** Applies new settings from the next frame on. */
    fun updateConfig(newConfig: VadConfig) {
        segmenter.config = newConfig
    }

    /** The room noise level now, in dBFS. */
    fun noiseFloorDb(): Float = segmenter.noiseFloorDb

    /** True while speech is being collected. */
    fun isSpeaking(): Boolean = segmenter.isSpeaking

    // Runs on the capture thread for every frame.
    private fun onFrame(frame: ShortArray, count: Int) {
        val current: Listener = listener ?: return
        val event: SpeechEvent = try {
            segmenter.process(frame, count)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Speech detection failed on a frame", e)
            null
        } ?: return
        deliver(event, current)
    }

    private fun deliver(event: SpeechEvent, target: Listener) {
        mainHandler.post {
            try {
                when (event) {
                    is SpeechEvent.Started -> target.onSpeechStarted()
                    is SpeechEvent.Ended -> target.onSpeechEnded(event.segment)
                    is SpeechEvent.Discarded -> target.onSpeechDiscarded(event.durationMs)
                }
            } catch (e: Exception) {
                NovaLogger.e(TAG, "Speech listener failed", e)
            }
        }
    }

    private companion object {
        const val TAG: String = "SpeechDetector"
    }
}
EOF

# ---------- 7. MicLabController.kt (all E1 features kept; speech detection added) ----------
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** What the test card is doing with the sound. */
enum class LabPhase { IDLE, RECORDING, PLAYING }

/** One detected piece of speech, kept for replay in the test card. */
class Utterance(
    val id: Int,
    val durationMs: Long,
    val samples: ShortArray,
    val endReason: SegmentEnd
)

/**
 * Screen-side holder for the microphone test card: starts and stops the
 * microphone, shows the level, finds pieces of speech, records a 5-second clip
 * and plays sounds back. Use from the main thread.
 */
class MicLabController(
    context: Context,
    private val scope: CoroutineScope
) {

    private val appContext: Context = context.applicationContext
    private val engine = AudioCaptureEngine(appContext)
    private val detector = SpeechDetector(engine)
    private val player = ClipPlayer()

    private var clipJob: Job? = null
    private var lastClip: ShortArray? = null
    private var lastSignalMs: Long = 0L
    private var nextUtteranceId: Int = 1
    private val utteranceList = mutableStateListOf<Utterance>()

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
            utteranceList.add(
                0,
                Utterance(nextUtteranceId, segment.durationMs, segment.samples, segment.endReason)
            )
            nextUtteranceId += 1
            while (utteranceList.size > MAX_KEPT_UTTERANCES) {
                utteranceList.removeAt(utteranceList.lastIndex)
            }
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

    /** Closes the microphone and stops any recording or playback. */
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

    /** Releases everything. Call when the screen is gone. */
    fun release() {
        stop()
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

# ---------- 8. MicLabCard.kt (all E1 features kept; speech detection section added) ----------
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import com.nova.ai.audio.LabPhase
import com.nova.ai.audio.MicLabController
import com.nova.ai.audio.PauseTolerance
import com.nova.ai.audio.SegmentEnd
import com.nova.ai.audio.Utterance
import com.nova.ai.audio.VadSensitivity
import com.nova.ai.time.TimeText
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope

/**
 * Test card for the new listening engine: switch the microphone on, watch the
 * level move, compare the two microphone types, record and replay 5 seconds,
 * and see how the engine cuts your speech into pieces.
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

/** The speech detection part of the card: live state, settings and the list of detected speech. */
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

    if (controller.utterances.isEmpty()) {
        Text(
            text = stringResource(R.string.vad_empty),
            style = MaterialTheme.typography.bodySmall
        )
    } else {
        Text(
            text = stringResource(R.string.vad_list_title),
            style = MaterialTheme.typography.titleMedium
        )
        controller.utterances.forEach { item ->
            key(item.id) { UtteranceRow(controller, item) }
        }
    }
}

@Composable
private fun UtteranceRow(controller: MicLabController, item: Utterance) {
    val seconds: String = TimeText.digits(String.format(Locale.US, "%.1f", item.durationMs / 1000f))
    val cutNote: String =
        if (item.endReason == SegmentEnd.MAX_LENGTH) stringResource(R.string.vad_reason_max) else ""
    val isPlayingThis: Boolean =
        controller.phase == LabPhase.PLAYING && controller.playingUtteranceId == item.id

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
}

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
git commit -m "E2: adaptive speech start/end detection and utterance cutting"
git push

echo "E2 files created and pushed."
