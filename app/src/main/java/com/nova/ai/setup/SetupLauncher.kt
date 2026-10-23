package com.nova.ai.setup

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/** Opens the phone's settings screens where the user grants special permissions. */
object SetupLauncher {

    private const val TAG: String = "SetupLauncher"

    /** Opens the Accessibility settings list. */
    fun openAccessibilitySettings(context: Context): NovaResult<Unit> =
        start(context, Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))

    /** Opens the screen where the user allows NOVA to change system settings (brightness). */
    fun openWriteSettings(context: Context): NovaResult<Unit> =
        start(
            context,
            Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:${context.packageName}"))
        )

    /** Opens NOVA's own app information page (for "Allow restricted settings" and permissions). */
    fun openAppDetails(context: Context): NovaResult<Unit> =
        start(
            context,
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
        )

    private fun start(context: Context, intent: Intent): NovaResult<Unit> {
        return try {
            if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            NovaResult.Success(Unit)
        } catch (e: ActivityNotFoundException) {
            NovaLogger.e(TAG, "Settings screen not found", e)
            NovaResult.failure(ErrorCode.NOT_FOUND, "সেটিংস স্ক্রিন খোলা যাচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to open a settings screen", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "সেটিংস খুলতে সমস্যা হয়েছে।", e)
        }
    }
}
