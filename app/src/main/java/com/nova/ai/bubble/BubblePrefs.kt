package com.nova.ai.bubble

import android.content.Context
import android.content.SharedPreferences
import com.nova.ai.logging.NovaLogger

/** Remembers where the user left the bubble: which screen edge and how far down. */
internal class BubblePrefs(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** True if the bubble sticks to the right edge. */
    fun isRightSide(): Boolean = try {
        prefs.getBoolean(KEY_RIGHT, true)
    } catch (e: Exception) {
        NovaLogger.w(TAG, "Could not read the bubble side", e)
        true
    }

    /** How far down the free area the bubble is, from 0.0 to 1.0. */
    fun yFraction(): Float = try {
        prefs.getFloat(KEY_Y, DEFAULT_Y)
    } catch (e: Exception) {
        NovaLogger.w(TAG, "Could not read the bubble position", e)
        DEFAULT_Y
    }

    /** Saves the place of the bubble. */
    fun save(rightSide: Boolean, yFraction: Float) {
        try {
            prefs.edit().putBoolean(KEY_RIGHT, rightSide).putFloat(KEY_Y, yFraction).apply()
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not save the bubble position", e)
        }
    }

    private companion object {
        const val TAG: String = "BubblePrefs"
        const val PREFS_NAME: String = "nova_bubble"
        const val KEY_RIGHT: String = "right_side"
        const val KEY_Y: String = "y_fraction"
        const val DEFAULT_Y: Float = 0.4f
    }
}
