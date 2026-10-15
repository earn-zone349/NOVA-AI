package com.nova.ai.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import com.nova.ai.settings.ThemeMode

/** App theme. [themeMode] decides light, dark, or follow the phone. */
@Composable
fun NovaTheme(
    themeMode: ThemeMode = ThemeMode.SYSTEM,
    content: @Composable () -> Unit
) {
    val systemDark: Boolean = isSystemInDarkTheme()
    val useDark: Boolean = when (themeMode) {
        ThemeMode.SYSTEM -> systemDark
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }
    val colors: ColorScheme = if (useDark) NovaDarkColors else NovaLightColors

    MaterialTheme(
        colorScheme = colors,
        typography = NovaTypography,
        content = content
    )
}
