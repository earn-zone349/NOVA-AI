package com.nova.ai.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout

/** Privacy and Security: local data, sensitive-action rules, security log. */
@Composable
fun PrivacySecurityScreen(modifier: Modifier = Modifier) {
    NovaScreenLayout(
        title = stringResource(R.string.privacy_title),
        subtitle = stringResource(R.string.privacy_subtitle),
        modifier = modifier
    ) {
        NovaInfoCard(
            title = stringResource(R.string.privacy_local_title),
            body = stringResource(R.string.privacy_local_body)
        )
        NovaInfoCard(
            title = stringResource(R.string.privacy_sensitive_title),
            body = stringResource(R.string.privacy_sensitive_body)
        )
        NovaInfoCard(
            title = stringResource(R.string.privacy_log_title),
            body = stringResource(R.string.privacy_log_body)
        )
    }
}
