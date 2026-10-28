package com.nova.ai.ui.screens

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.security.EmergencyStop
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.TaskQueueCard
import com.nova.ai.ui.components.NovaScreenLayout

/** Automation: routines, task history and the stop control. */
@Composable
fun AutomationScreen(modifier: Modifier = Modifier) {
    NovaScreenLayout(
        title = stringResource(R.string.automation_title),
        subtitle = stringResource(R.string.automation_subtitle),
        modifier = modifier
    ) {
        NovaInfoCard(
            title = stringResource(R.string.automation_routines_title),
            body = stringResource(R.string.automation_routines_none)
        )
        NovaInfoCard(
            title = stringResource(R.string.automation_history_title),
            body = stringResource(R.string.automation_history_none)
        )
        TaskQueueCard()

        // Disabled until the emergency stop is implemented (P22).
        Button(
            onClick = { if (EmergencyStop.isActive) EmergencyStop.release("automation screen") else EmergencyStop.trigger("automation screen") },
            enabled = true,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(stringResource(R.string.automation_stop_button))
        }
        Text(
            text = stringResource(R.string.automation_stop_note),
            style = MaterialTheme.typography.bodySmall
        )
    }
}
