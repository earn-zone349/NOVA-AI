package com.nova.ai.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.core.Language
import com.nova.ai.nlp.CommandNormalizer
import com.nova.ai.nlp.NormalizedCommand

/**
 * Shows how the app cleaned up the current command: the standard form,
 * the apps it recognized, and the detected language.
 * Shows nothing when [text] is blank.
 */
@Composable
fun CommandInsightCard(text: String, modifier: Modifier = Modifier) {
    if (text.isBlank()) return

    val insight: NormalizedCommand = remember(text) { CommandNormalizer.normalize(text) }

    val languageName: String = stringResource(
        when (insight.language) {
            Language.BANGLA -> R.string.insight_lang_bangla
            Language.ENGLISH -> R.string.insight_lang_english
            Language.MIXED -> R.string.insight_lang_mixed
            Language.UNKNOWN -> R.string.insight_lang_unknown
        }
    )
    val normalizedLine: String = stringResource(R.string.insight_normalized, insight.normalizedText)
    val languageLine: String = stringResource(R.string.insight_language, languageName)
    val appsLine: String? = if (insight.detectedApps.isEmpty()) {
        null
    } else {
        stringResource(R.string.insight_apps, insight.detectedApps.joinToString(", "))
    }

    val body: String = listOfNotNull(normalizedLine, appsLine, languageLine).joinToString("\n")

    NovaInfoCard(
        title = stringResource(R.string.insight_title),
        body = body,
        modifier = modifier
    )
}
