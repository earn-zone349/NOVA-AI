package com.nova.ai.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nova.ai.R
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.ThemeMode
import com.nova.ai.ui.components.NovaChoiceGroup
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.languageLabel
import com.nova.ai.ui.components.themeModeLabel

private const val TOTAL_STEPS: Int = 3

/**
 * First-run guide: welcome, feature overview, then language and theme choice.
 * Calls [onFinished] with the chosen settings when the user taps Start.
 */
@Composable
fun OnboardingScreen(
    onFinished: (AppLanguage, ThemeMode) -> Unit,
    modifier: Modifier = Modifier
) {
    var step: Int by rememberSaveable { mutableStateOf(0) }
    var language: AppLanguage by rememberSaveable { mutableStateOf(AppLanguage.BANGLA) }
    var theme: ThemeMode by rememberSaveable { mutableStateOf(ThemeMode.SYSTEM) }
    val lastStep: Int = TOTAL_STEPS - 1

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp)
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = stringResource(R.string.onboarding_step_format, step + 1, TOTAL_STEPS),
                style = MaterialTheme.typography.bodySmall
            )
            when (step) {
                0 -> WelcomeStep()
                1 -> FeaturesStep()
                else -> PreferencesStep(
                    language = language,
                    theme = theme,
                    onLanguageChange = { language = it },
                    onThemeChange = { theme = it }
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (step > 0) {
                OutlinedButton(
                    onClick = { step -= 1 },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.onboarding_back))
                }
            }
            Button(
                onClick = {
                    if (step < lastStep) step += 1 else onFinished(language, theme)
                },
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    stringResource(
                        if (step < lastStep) R.string.onboarding_next else R.string.onboarding_start
                    )
                )
            }
        }
    }
}

@Composable
private fun WelcomeStep() {
    Text(text = stringResource(R.string.onboarding_welcome_emoji), fontSize = 64.sp)
    Text(
        text = stringResource(R.string.onboarding_welcome_title),
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold
    )
    Text(
        text = stringResource(R.string.onboarding_welcome_body),
        style = MaterialTheme.typography.bodyMedium
    )
}

@Composable
private fun FeaturesStep() {
    Text(
        text = stringResource(R.string.onboarding_features_title),
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold
    )
    NovaInfoCard(
        title = stringResource(R.string.onboarding_feature_voice_title),
        body = stringResource(R.string.onboarding_feature_voice_body)
    )
    NovaInfoCard(
        title = stringResource(R.string.onboarding_feature_apps_title),
        body = stringResource(R.string.onboarding_feature_apps_body)
    )
    NovaInfoCard(
        title = stringResource(R.string.onboarding_feature_privacy_title),
        body = stringResource(R.string.onboarding_feature_privacy_body)
    )
}

@Composable
private fun PreferencesStep(
    language: AppLanguage,
    theme: ThemeMode,
    onLanguageChange: (AppLanguage) -> Unit,
    onThemeChange: (ThemeMode) -> Unit
) {
    Text(
        text = stringResource(R.string.onboarding_prefs_title),
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold
    )
    NovaChoiceGroup(
        title = stringResource(R.string.settings_language_title),
        options = AppLanguage.values().toList(),
        selected = language,
        labelOf = { languageLabel(it) },
        onSelected = onLanguageChange
    )
    NovaChoiceGroup(
        title = stringResource(R.string.settings_theme_title),
        options = ThemeMode.values().toList(),
        selected = theme,
        labelOf = { themeModeLabel(it) },
        onSelected = onThemeChange
    )
    Text(
        text = stringResource(R.string.onboarding_prefs_note),
        style = MaterialTheme.typography.bodySmall
    )
}
