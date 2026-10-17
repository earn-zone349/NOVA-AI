package com.nova.ai.system

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * Opens the phone's Wi-Fi, Bluetooth and mobile data screens. Android does not
 * let ordinary apps switch these on or off, so the user taps the final switch.
 */
class SystemSettingsOpener(context: Context) {

    private val appContext: Context = context.applicationContext

    /** Opens the quick Wi-Fi panel (Android 10 and newer) or the Wi-Fi settings page. */
    fun openWifi(): NovaResult<Unit> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val panel: NovaResult<Unit> = start(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
            if (panel is NovaResult.Success) return panel
        }
        return start(Settings.ACTION_WIFI_SETTINGS)
    }

    /** Opens the Bluetooth settings page. */
    fun openBluetooth(): NovaResult<Unit> = start(Settings.ACTION_BLUETOOTH_SETTINGS)

    /** Opens the internet panel (Android 10 and newer) or the mobile network settings page. */
    fun openMobileData(): NovaResult<Unit> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val panel: NovaResult<Unit> = start(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
            if (panel is NovaResult.Success) return panel
        }
        return start(Settings.ACTION_DATA_ROAMING_SETTINGS)
    }

    private fun start(action: String): NovaResult<Unit> {
        return try {
            appContext.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            NovaResult.Success(Unit)
        } catch (e: ActivityNotFoundException) {
            NovaLogger.e(TAG, "Settings screen not found", e)
            NovaResult.failure(ErrorCode.NOT_AVAILABLE, "সেটিংস স্ক্রিন খোলা যাচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to open settings screen", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "সেটিংস খুলতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "SystemSettingsOpener"
    }
}
