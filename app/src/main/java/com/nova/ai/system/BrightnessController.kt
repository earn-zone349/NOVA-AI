package com.nova.ai.system

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import kotlin.math.roundToInt

/**
 * Changes the screen brightness. Android asks the user to allow this once
 * ("Modify system settings"); [canWrite] tells whether that was done.
 */
class BrightnessController(context: Context) {

    private val appContext: Context = context.applicationContext

    /** True if the user allowed NOVA to change system settings. */
    fun canWrite(): Boolean = Settings.System.canWrite(appContext)

    /** Sets the brightness to [percent] (kept between 3 and 100). */
    fun setPercent(percent: Int): NovaResult<Int> =
        apply(percent.coerceIn(MIN_PERCENT, MAX_PERCENT))

    /** Raises or lowers the brightness by one step. */
    fun step(up: Boolean): NovaResult<Int> {
        val delta: Int = if (up) STEP_PERCENT else -STEP_PERCENT
        return apply((currentPercent() + delta).coerceIn(MIN_PERCENT, MAX_PERCENT))
    }

    /** Opens the screen where the user can allow NOVA to change brightness. */
    fun openPermissionScreen(): NovaResult<Unit> {
        return try {
            val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                .setData(Uri.parse("package:${appContext.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appContext.startActivity(intent)
            NovaResult.Success(Unit)
        } catch (e: ActivityNotFoundException) {
            NovaLogger.e(TAG, "Permission screen not found", e)
            NovaResult.failure(ErrorCode.NOT_AVAILABLE, "অনুমতির স্ক্রিন খোলা যাচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to open permission screen", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "অনুমতির স্ক্রিন খুলতে সমস্যা হয়েছে।", e)
        }
    }

    private fun currentPercent(): Int {
        val raw: Int = Settings.System.getInt(
            appContext.contentResolver,
            Settings.System.SCREEN_BRIGHTNESS,
            DEFAULT_RAW
        )
        return (raw * PERCENT_BASE / MAX_RAW).roundToInt()
    }

    private fun apply(percent: Int): NovaResult<Int> {
        if (!canWrite()) {
            return NovaResult.failure(ErrorCode.PERMISSION_DENIED, "ব্রাইটনেস বদলানোর অনুমতি নেই।")
        }
        return try {
            val raw: Int = (percent * MAX_RAW / PERCENT_BASE).roundToInt().coerceIn(1, MAX_RAW.toInt())
            val resolver = appContext.contentResolver
            Settings.System.putInt(
                resolver,
                Settings.System.SCREEN_BRIGHTNESS_MODE,
                Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL
            )
            val saved: Boolean = Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS, raw)
            if (saved) {
                NovaResult.Success(percent)
            } else {
                NovaResult.failure(ErrorCode.EXECUTION_FAILED, "ব্রাইটনেস বদলানো যায়নি।")
            }
        } catch (e: SecurityException) {
            NovaLogger.w(TAG, "Brightness change not allowed", e)
            NovaResult.failure(ErrorCode.PERMISSION_DENIED, "ব্রাইটনেস বদলানোর অনুমতি নেই।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Brightness change failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "ব্রাইটনেস বদলাতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "BrightnessController"
        const val MIN_PERCENT: Int = 3
        const val MAX_PERCENT: Int = 100
        const val STEP_PERCENT: Int = 15
        const val PERCENT_BASE: Float = 100f
        const val MAX_RAW: Float = 255f
        const val DEFAULT_RAW: Int = 128
    }
}
