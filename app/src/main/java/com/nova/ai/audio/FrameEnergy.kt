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
