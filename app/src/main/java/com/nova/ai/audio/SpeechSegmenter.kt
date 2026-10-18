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
