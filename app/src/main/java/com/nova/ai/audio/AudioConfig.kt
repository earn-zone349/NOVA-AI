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
