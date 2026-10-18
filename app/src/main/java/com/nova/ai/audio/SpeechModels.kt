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
