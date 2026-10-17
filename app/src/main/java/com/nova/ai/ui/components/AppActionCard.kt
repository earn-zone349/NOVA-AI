package com.nova.ai.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.apps.AppActionUi
import com.nova.ai.apps.AppCommandController

/**
 * Shows the result of an "open app" command on the Home screen: opened,
 * a question to confirm or choose, an offer to add an app, or a problem.
 * Shows nothing while there is nothing to report.
 */
@Composable
fun AppActionCard(
    controller: AppCommandController,
    modifier: Modifier = Modifier
) {
    val current: AppActionUi = controller.state
    if (current is AppActionUi.Idle) return

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.action_title),
                style = MaterialTheme.typography.titleMedium
            )

            when (current) {
                is AppActionUi.Idle -> Unit

                is AppActionUi.Opened -> {
                    Text(stringResource(R.string.action_opened, current.appLabel))
                }

                is AppActionUi.Confirm -> {
                    Text(stringResource(R.string.action_confirm, current.spoken, current.app.label))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = { controller.confirm() },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(stringResource(R.string.action_confirm_yes))
                        }
                        OutlinedButton(
                            onClick = { controller.dismiss() },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(stringResource(R.string.action_confirm_no))
                        }
                    }
                }

                is AppActionUi.Choose -> {
                    Text(stringResource(R.string.action_choose, current.spoken))
                    current.apps.forEach { app ->
                        Button(
                            onClick = { controller.choose(app) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(app.label)
                        }
                    }
                }

                is AppActionUi.Suggest -> {
                    Text(stringResource(R.string.action_suggest, current.spoken))
                    current.apps.forEach { app ->
                        Button(
                            onClick = { controller.addAndOpen(app) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(stringResource(R.string.action_suggest_button, app.label))
                        }
                    }
                }

                is AppActionUi.NotFound -> {
                    Text(stringResource(R.string.action_not_found, current.spoken))
                }

                is AppActionUi.Failed -> {
                    Text(stringResource(R.string.action_failed, current.message))
                }
            }

            if (current !is AppActionUi.Confirm) {
                TextButton(onClick = { controller.dismiss() }) {
                    Text(stringResource(R.string.action_dismiss))
                }
            }
        }
    }
}
