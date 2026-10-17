package com.nova.ai.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.system.OutcomeKind
import com.nova.ai.system.SystemActionOutcome
import com.nova.ai.system.SystemCommandController

/**
 * Shows the result of a system command (torch, volume, brightness, Wi-Fi,
 * Bluetooth) on the Home screen. Shows nothing while there is nothing to report.
 */
@Composable
fun SystemActionCard(
    controller: SystemCommandController,
    modifier: Modifier = Modifier
) {
    val outcome: SystemActionOutcome = controller.state ?: return

    val marker: String = when (outcome.kind) {
        OutcomeKind.DONE -> "✅"
        OutcomeKind.GUIDED -> "👉"
        OutcomeKind.NEEDS_PERMISSION -> "🔐"
        OutcomeKind.HINT -> "💡"
        OutcomeKind.FAILED -> "⚠️"
    }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.sys_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(text = "$marker ${outcome.message}")

            if (outcome.kind == OutcomeKind.NEEDS_PERMISSION) {
                Button(
                    onClick = { controller.openBrightnessPermission() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.sys_brightness_permission_button))
                }
            }

            TextButton(onClick = { controller.dismiss() }) {
                Text(stringResource(R.string.action_dismiss))
            }
        }
    }
}
