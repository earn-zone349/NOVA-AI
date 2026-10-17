package com.nova.ai.system

import android.content.Context
import android.media.AudioManager
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import kotlin.math.roundToInt

/**
 * Changes the media volume (songs, videos and NOVA's own voice).
 * Every change shows the system volume bar and returns the new volume in percent.
 */
class VolumeController(context: Context) {

    private val audioManager: AudioManager? =
        context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    private var volumeBeforeMute: Int = 0

    /** Sets the volume to [percent] (0 to 100). */
    fun setPercent(percent: Int): NovaResult<Int> = change { max, _ ->
        (max * percent.coerceIn(MIN_PERCENT, MAX_PERCENT) / PERCENT_BASE).roundToInt()
    }

    /** Raises or lowers the volume by one step. */
    fun step(up: Boolean): NovaResult<Int> = change { max, current ->
        val size: Int = maxOf(1, (max * STEP_FRACTION).roundToInt())
        if (up) current + size else current - size
    }

    /** Mutes, remembering the old volume so it can be restored. */
    fun mute(): NovaResult<Int> = change { _, current ->
        if (current > 0) volumeBeforeMute = current
        0
    }

    /** Restores the volume from before muting (or half volume). */
    fun unmute(): NovaResult<Int> = change { max, current ->
        when {
            current > 0 -> current
            volumeBeforeMute > 0 -> volumeBeforeMute
            else -> maxOf(1, max / 2)
        }
    }

    private fun change(compute: (max: Int, current: Int) -> Int): NovaResult<Int> {
        val manager: AudioManager = audioManager
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, "ফোনের অডিও সিস্টেম পাওয়া যায়নি।")
        return try {
            val max: Int = manager.getStreamMaxVolume(STREAM)
            val current: Int = manager.getStreamVolume(STREAM)
            if (max <= 0) {
                return NovaResult.failure(ErrorCode.NOT_AVAILABLE, "ভলিউম বদলানো যাচ্ছে না।")
            }
            val target: Int = compute(max, current).coerceIn(0, max)
            manager.setStreamVolume(STREAM, target, AudioManager.FLAG_SHOW_UI)
            NovaResult.Success((target * PERCENT_BASE / max).roundToInt())
        } catch (e: SecurityException) {
            NovaLogger.w(TAG, "Volume change not allowed", e)
            NovaResult.failure(ErrorCode.PERMISSION_DENIED, "ফোন এখন ভলিউম বদলাতে দিচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Volume change failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "ভলিউম বদলাতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "VolumeController"
        const val STREAM: Int = AudioManager.STREAM_MUSIC
        const val MIN_PERCENT: Int = 0
        const val MAX_PERCENT: Int = 100
        const val PERCENT_BASE: Float = 100f
        const val STEP_FRACTION: Float = 0.15f
    }
}
