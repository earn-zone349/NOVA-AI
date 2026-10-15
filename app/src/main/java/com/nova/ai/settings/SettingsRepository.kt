package com.nova.ai.settings

import android.content.Context
import android.content.SharedPreferences
import android.util.Log

/** Theme choice. */
enum class ThemeMode { SYSTEM, LIGHT, DARK }

/** Preferred interaction language. Used by voice features from Phase 6. */
enum class AppLanguage { BANGLA, ENGLISH, MIXED }

/**
 * Stores app settings on the device only (SharedPreferences).
 * Every read falls back to a safe default, and every write is guarded,
 * so storage problems never crash the app.
 */
class SettingsRepository(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getThemeMode(): ThemeMode = readEnum(KEY_THEME, ThemeMode.SYSTEM)

    fun setThemeMode(mode: ThemeMode) = writeString(KEY_THEME, mode.name)

    fun getLanguage(): AppLanguage = readEnum(KEY_LANGUAGE, AppLanguage.BANGLA)

    fun setLanguage(language: AppLanguage) = writeString(KEY_LANGUAGE, language.name)

    fun isOnboardingDone(): Boolean = try {
        prefs.getBoolean(KEY_ONBOARDING_DONE, false)
    } catch (e: Exception) {
        Log.e(TAG, "Failed to read onboarding flag", e)
        false
    }

    fun setOnboardingDone(done: Boolean) {
        try {
            prefs.edit().putBoolean(KEY_ONBOARDING_DONE, done).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save onboarding flag", e)
        }
    }

    private inline fun <reified T : Enum<T>> readEnum(key: String, default: T): T {
        return try {
            val stored: String? = prefs.getString(key, null)
            if (stored == null) default else enumValueOf<T>(stored)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read $key, using default", e)
            default
        }
    }

    private fun writeString(key: String, value: String) {
        try {
            prefs.edit().putString(key, value).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save $key", e)
        }
    }

    private companion object {
        const val TAG: String = "SettingsRepository"
        const val PREFS_NAME: String = "nova_settings"
        const val KEY_THEME: String = "theme_mode"
        const val KEY_LANGUAGE: String = "app_language"
        const val KEY_ONBOARDING_DONE: String = "onboarding_done"
    }
}
