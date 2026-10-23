package com.nova.ai.accessibility

import android.content.ComponentName
import android.content.Context
import android.provider.Settings

/** Tells whether the user switched NOVA's accessibility service on in the phone's settings. */
object AccessibilityStatus {

    private const val SERVICE_LIST_SEPARATOR: Char = ':'

    /** True if the service is listed as enabled in the phone's settings. */
    fun isEnabledInSettings(context: Context): Boolean {
        val resolver = context.applicationContext.contentResolver
        val masterSwitch: Int = Settings.Secure.getInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 0)
        if (masterSwitch != 1) return false

        val enabledList: String = Settings.Secure.getString(
            resolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val expected = ComponentName(context.applicationContext, NovaAccessibilityService::class.java)
        return enabledList
            .split(SERVICE_LIST_SEPARATOR)
            .any { entry -> ComponentName.unflattenFromString(entry) == expected }
    }
}
