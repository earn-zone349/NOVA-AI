package com.nova.ai.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout

/** AI Brain: active local model, memory use, offline status, language settings. */
@Composable
fun AiBrainScreen(modifier: Modifier = Modifier) {
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
    }
}
