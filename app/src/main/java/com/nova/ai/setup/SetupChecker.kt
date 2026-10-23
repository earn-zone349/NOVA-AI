package com.nova.ai.setup

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.nova.ai.accessibility.AccessibilityStatus

/** Checks which permissions of the setup wizard the user has already granted. */
class SetupChecker(context: Context) {

    private val appContext: Context = context.applicationContext

    /** True if [item] is granted. */
    fun isGranted(item: SetupItem): Boolean = when (item.id) {
        SetupItemId.ACCESSIBILITY -> AccessibilityStatus.isEnabledInSettings(appContext)
        SetupItemId.SYSTEM_SETTINGS -> Settings.System.canWrite(appContext)
        // Before Android 13 notifications need no permission.
        SetupItemId.NOTIFICATIONS ->
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                hasRuntimePermission(item.runtimePermission)
        else -> hasRuntimePermission(item.runtimePermission)
    }

    /** The pop-up permissions that are still missing. They can be asked all at once. */
    fun missingRuntimePermissions(): List<String> =
        SetupCatalog.items
            .filter { it.runtimePermission != null && !isGranted(it) }
            .mapNotNull { it.runtimePermission }

    /** How many permissions are still missing. */
    fun missingCount(): Int = SetupCatalog.items.count { !isGranted(it) }

    private fun hasRuntimePermission(permission: String?): Boolean =
        permission != null &&
            ContextCompat.checkSelfPermission(appContext, permission) == PackageManager.PERMISSION_GRANTED
}
