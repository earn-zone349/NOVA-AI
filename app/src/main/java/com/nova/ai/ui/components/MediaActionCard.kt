package com.nova.ai.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.media.MediaCommandController
import com.nova.ai.system.OutcomeKind
import com.nova.ai.system.SystemActionOutcome

/**
 * Shows the result of a music, search, navigation or camera command on the
 * Home screen. Shows nothing while there is nothing to report.
 */
@Composable
fun MediaActionCard(
    controller: MediaCommandController,
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
                text = stringResource(R.string.media_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(text = "$marker ${outcome.message}")
            TextButton(onClick = { controller.dismiss() }) {
                Text(stringResource(R.string.action_dismiss))
            }
        }
    }
}
