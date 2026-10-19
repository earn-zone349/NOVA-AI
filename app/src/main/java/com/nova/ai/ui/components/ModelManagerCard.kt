package com.nova.ai.ui.components

import android.content.Context
import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.models.FileModelManager
import com.nova.ai.models.ModelCatalog
import com.nova.ai.models.ModelDownloadHub
import com.nova.ai.models.ModelDownloadState
import com.nova.ai.models.WhisperModelSpec

/**
 * Model manager: download, stop and delete the offline Whisper models.
 * Downloads continue even if the user leaves this tab.
 */
@Composable
fun ModelManagerCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val manager: FileModelManager = remember { FileModelManager(context) }

    // Reading this makes the card refresh after a download ends or a model is deleted.
    val refreshTick: Int = ModelDownloadHub.revision

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.models_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.models_note),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.models_wifi_note),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(
                    R.string.models_free_space,
                    Formatter.formatShortFileSize(context, manager.freeSpaceBytes())
                ),
                style = MaterialTheme.typography.bodySmall
            )

            ModelCatalog.whisperModels.forEach { spec ->
                key(spec.id) { ModelRow(context, manager, spec, refreshTick) }
            }
        }
    }
}

@Composable
private fun ModelRow(
    context: Context,
    manager: FileModelManager,
    spec: WhisperModelSpec,
    refreshTick: Int
) {
    // refreshTick only forces this row to be rebuilt; it is not shown.
    check(refreshTick >= 0)

    val installed: Boolean = manager.isInstalled(spec)
    val state: ModelDownloadState = ModelDownloadHub.stateOf(spec.id)

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = stringResource(spec.titleRes),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )

        when {
            installed -> {
                Text(
                    text = stringResource(
                        R.string.model_installed,
                        Formatter.formatShortFileSize(context, manager.installedSizeBytes(spec))
                    ),
                    style = MaterialTheme.typography.bodySmall
                )
                OutlinedButton(onClick = { ModelDownloadHub.delete(context, spec) }) {
                    Text(stringResource(R.string.model_delete))
                }
            }

            state is ModelDownloadState.Downloading -> {
                LinearProgressIndicator(
                    progress = { state.percent / 100f },
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    text = stringResource(
                        R.string.model_downloading,
                        state.percent,
                        state.downloadedMegabytes
                    ),
                    style = MaterialTheme.typography.bodySmall
                )
                OutlinedButton(onClick = { ModelDownloadHub.cancel(spec.id) }) {
                    Text(stringResource(R.string.model_cancel))
                }
            }

            else -> {
                Text(
                    text = stringResource(R.string.model_size, spec.approxMegabytes),
                    style = MaterialTheme.typography.bodySmall
                )
                if (state is ModelDownloadState.Failed) {
                    Text(
                        text = stringResource(R.string.model_failed, state.message),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
                Button(onClick = { ModelDownloadHub.start(context, spec) }) {
                    Text(
                        stringResource(
                            if (state is ModelDownloadState.Failed) R.string.model_resume else R.string.model_download
                        )
                    )
                }
            }
        }
    }
}
