package com.nova.ai.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.ThemeMode

/** Single-choice list with radio buttons. Whole row is tappable. */
@Composable
fun <T> NovaChoiceGroup(
    title: String,
    options: List<T>,
    selected: T,
    labelOf: @Composable (T) -> String,
    onSelected: (T) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxWidth().selectableGroup()) {
        Text(text = title, style = MaterialTheme.typography.titleMedium)
        options.forEach { option ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .selectable(
                        selected = option == selected,
                        onClick = { onSelected(option) },
                        role = Role.RadioButton
                    )
                    .padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                RadioButton(selected = option == selected, onClick = null)
                Spacer(modifier = Modifier.width(12.dp))
                Text(text = labelOf(option), style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

/** Display text for a [ThemeMode]. */
@Composable
fun themeModeLabel(mode: ThemeMode): String = stringResource(
    when (mode) {
        ThemeMode.SYSTEM -> R.string.settings_theme_system
        ThemeMode.LIGHT -> R.string.settings_theme_light
        ThemeMode.DARK -> R.string.settings_theme_dark
    }
)

/** Display text for an [AppLanguage]. */
@Composable
fun languageLabel(language: AppLanguage): String = stringResource(
    when (language) {
        AppLanguage.BANGLA -> R.string.settings_language_bangla
        AppLanguage.ENGLISH -> R.string.settings_language_english
        AppLanguage.MIXED -> R.string.settings_language_mixed
    }
)
