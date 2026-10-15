package com.nova.ai

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.SettingsRepository
import com.nova.ai.settings.ThemeMode
import com.nova.ai.ui.navigation.NovaMainScaffold
import com.nova.ai.ui.screens.OnboardingScreen
import com.nova.ai.ui.theme.AppSettingsState
import com.nova.ai.ui.theme.LocalAppSettings
import com.nova.ai.ui.theme.NovaTheme

/**
 * Single-activity host. Applies the theme, shows onboarding on first launch,
 * then the navigation graph (Home, Brain, Tasks, Access, Memory, Privacy).
 */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val repository = SettingsRepository(applicationContext)
            setContent { NovaRoot(repository) }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set content", e)
        }
    }

    companion object {
        private const val TAG: String = "MainActivity"
    }
}

/** Root composable: settings state, theme, onboarding gate and main scaffold. */
@Composable
private fun NovaRoot(repository: SettingsRepository) {
    var themeMode: ThemeMode by remember { mutableStateOf(repository.getThemeMode()) }
    var language: AppLanguage by remember { mutableStateOf(repository.getLanguage()) }
    var onboardingDone: Boolean by remember { mutableStateOf(repository.isOnboardingDone()) }

    val settingsState = AppSettingsState(
        themeMode = themeMode,
        language = language,
        onThemeModeChange = { newMode ->
            themeMode = newMode
            repository.setThemeMode(newMode)
        },
        onLanguageChange = { newLanguage ->
            language = newLanguage
            repository.setLanguage(newLanguage)
        }
    )

    NovaTheme(themeMode = themeMode) {
        CompositionLocalProvider(LocalAppSettings provides settingsState) {
            Surface(modifier = Modifier.fillMaxSize()) {
                if (onboardingDone) {
                    NovaMainScaffold()
                } else {
                    OnboardingScreen(
                        onFinished = { chosenLanguage, chosenTheme ->
                            language = chosenLanguage
                            themeMode = chosenTheme
                            repository.setLanguage(chosenLanguage)
                            repository.setThemeMode(chosenTheme)
                            repository.setOnboardingDone(true)
                            onboardingDone = true
                        }
                    )
                }
            }
        }
    }
}
