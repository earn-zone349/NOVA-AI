package com.nova.ai.ui.theme

import androidx.compose.runtime.compositionLocalOf
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.SpeechSpeed
import com.nova.ai.settings.ThemeMode

/** Current settings plus the callbacks screens use to change them. */
data class AppSettingsState(
    val themeMode: ThemeMode,
    val language: AppLanguage,
    val onThemeModeChange: (ThemeMode) -> Unit,
    val onLanguageChange: (AppLanguage) -> Unit,
    val speechSpeed: SpeechSpeed = SpeechSpeed.NORMAL,
    val voiceReplyEnabled: Boolean = true,
    val onSpeechSpeedChange: (SpeechSpeed) -> Unit = { },
    val onVoiceReplyChange: (Boolean) -> Unit = { }
)

/** Gives every screen access to [AppSettingsState] without passing it manually. */
val LocalAppSettings = compositionLocalOf {
    AppSettingsState(
        themeMode = ThemeMode.SYSTEM,
        language = AppLanguage.BANGLA,
        onThemeModeChange = { },
        onLanguageChange = { }
    )
}
