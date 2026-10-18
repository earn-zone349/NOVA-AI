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
