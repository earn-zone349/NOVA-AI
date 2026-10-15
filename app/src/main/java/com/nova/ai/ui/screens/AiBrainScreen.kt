package com.nova.ai.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.ThemeMode
import com.nova.ai.ui.components.NovaChoiceGroup
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout
import com.nova.ai.ui.components.languageLabel
import com.nova.ai.ui.components.themeModeLabel
import com.nova.ai.ui.theme.LocalAppSettings

/** AI Brain: model status, memory use, offline status, language, and appearance. */
@Composable
fun AiBrainScreen(modifier: Modifier = Modifier) {
    val settings = LocalAppSettings.current

    NovaScreenLayout(
        title = stringResource(R.string.brain_title),
        subtitle = stringResource(R.string.brain_subtitle),
        modifier = modifier
    ) {
        NovaInfoCard(
            title = stringResource(R.string.brain_model_title),
            body = stringResource(R.string.brain_model_none)
        )
        NovaInfoCard(
            title = stringResource(R.string.brain_ram_title),
            body = stringResource(R.string.brain_ram_none)
        )
        NovaInfoCard(
            title = stringResource(R.string.brain_offline_title),
            body = stringResource(R.string.brain_offline_body)
        )
        NovaInfoCard(
            title = stringResource(R.string.brain_language_title),
            body = stringResource(R.string.brain_language_body)
        )

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                NovaChoiceGroup(
                    title = stringResource(R.string.settings_language_title),
                    options = AppLanguage.values().toList(),
                    selected = settings.language,
                    labelOf = { languageLabel(it) },
                    onSelected = settings.onLanguageChange
                )
                NovaChoiceGroup(
                    title = stringResource(R.string.settings_theme_title),
                    options = ThemeMode.values().toList(),
                    selected = settings.themeMode,
                    labelOf = { themeModeLabel(it) },
                    onSelected = settings.onThemeModeChange
                )
            }
        }
    }
}
