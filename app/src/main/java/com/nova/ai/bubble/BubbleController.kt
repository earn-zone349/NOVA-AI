package com.nova.ai.bubble

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.nova.ai.R
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * Starts and stops the floating bubble and tells whether it can run. The screens, the quick
 * settings tile and the notification all use this one place. Use from the main thread.
 */
object BubbleController {

    private const val TAG: String = "BubbleController"

    /** True while the bubble service is running. Set by the service; the screens only read it. */
    var isRunning: Boolean by mutableStateOf(false)
        internal set

    /** True if the user allowed NOVA to draw over other apps. */
    fun canDrawOverlays(context: Context): Boolean = Settings.canDrawOverlays(context)

    /** True if the user allowed the microphone. */
    fun hasMicrophone(context: Context): Boolean = ContextCompat.checkSelfPermission(
        context, Manifest.permission.RECORD_AUDIO
    ) == PackageManager.PERMISSION_GRANTED

    /** The settings screen where the user allows drawing over other apps. */
    fun overlaySettingsIntent(context: Context): Intent =
        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))

    /** Starts the bubble. A failure result says what is missing. */
    fun start(context: Context): NovaResult<Unit> {
        val appContext: Context = context.applicationContext
        if (!canDrawOverlays(appContext)) {
            return NovaResult.failure(ErrorCode.PERMISSION_DENIED, appContext.getString(R.string.bub_need_overlay))
        }
        if (!hasMicrophone(appContext)) {
            return NovaResult.failure(ErrorCode.PERMISSION_DENIED, appContext.getString(R.string.bub_need_mic))
        }
        return try {
            val intent = Intent(appContext, NovaBubbleService::class.java).setAction(NovaBubbleService.ACTION_START)
            ContextCompat.startForegroundService(appContext, intent)
            NovaResult.Success(Unit)
        } catch (e: Exception) {
            // Android refuses to start a foreground service in some situations (for example from the background).
            NovaLogger.e(TAG, "Could not start the bubble service", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, appContext.getString(R.string.bub_start_failed), e)
        }
    }

    /** Stops the bubble. */
    fun stop(context: Context) {
        try {
            val appContext: Context = context.applicationContext
            appContext.stopService(Intent(appContext, NovaBubbleService::class.java))
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not stop the bubble service", e)
        }
    }
}
