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
