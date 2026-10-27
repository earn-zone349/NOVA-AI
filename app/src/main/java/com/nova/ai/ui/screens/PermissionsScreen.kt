package com.nova.ai.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.ui.components.AppLibrarySection
import com.nova.ai.ui.components.NovaScreenLayout
import com.nova.ai.ui.components.SetupWizardCard
import com.nova.ai.ui.components.ScreenReadLabCard
import com.nova.ai.ui.components.ActionLabCard
import com.nova.ai.ui.components.BubbleCard

/**
 * Access: the setup wizard (every permission with its reason and live status)
 * and NOVA's app list.
 */
@Composable
fun PermissionsScreen(modifier: Modifier = Modifier) {
    NovaScreenLayout(
        title = stringResource(R.string.permissions_title),
        subtitle = stringResource(R.string.permissions_subtitle),
        modifier = modifier
    ) {
        SetupWizardCard()
        ScreenReadLabCard()
        ActionLabCard()
        BubbleCard()
        AppLibrarySection()
    }
}
