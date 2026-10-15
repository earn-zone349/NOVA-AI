package com.nova.ai.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout

/** Permissions: explains why each permission is needed. Live status comes in P17. */
@Composable
fun PermissionsScreen(modifier: Modifier = Modifier) {
    val pending: String = stringResource(R.string.perm_status_pending)

    NovaScreenLayout(
        title = stringResource(R.string.permissions_title),
        subtitle = stringResource(R.string.permissions_subtitle),
        modifier = modifier
    ) {
        NovaInfoCard(
            title = stringResource(R.string.perm_accessibility_title),
            body = stringResource(R.string.perm_accessibility_body) + "\n" + pending
        )
        NovaInfoCard(
            title = stringResource(R.string.perm_microphone_title),
            body = stringResource(R.string.perm_microphone_body) + "\n" + pending
        )
        NovaInfoCard(
            title = stringResource(R.string.perm_notification_title),
            body = stringResource(R.string.perm_notification_body) + "\n" + pending
        )
    }
}
