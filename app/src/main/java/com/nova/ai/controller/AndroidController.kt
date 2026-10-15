package com.nova.ai.controller

import com.nova.ai.core.NovaResult
import com.nova.ai.core.SettingsSection

/** Performs permitted system-level actions (apps, settings, dialer). */
interface AndroidController {
    /** True if an app matching [appName] is installed. */
    fun isAppInstalled(appName: String): Boolean

    /** Opens the installed app best matching [appName]. */
    fun openApp(appName: String): NovaResult<Unit>

    /** Opens the given system settings screen. */
    fun openSystemSettings(section: SettingsSection): NovaResult<Unit>

    /** Opens the dialer with [phoneNumber] filled in (does not place the call). */
    fun openDialer(phoneNumber: String): NovaResult<Unit>
}
