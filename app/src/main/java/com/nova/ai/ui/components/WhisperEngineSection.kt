package com.nova.ai.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.audio.RecognitionRouting
import com.nova.ai.models.FileModelManager
import com.nova.ai.models.ModelCatalog
import com.nova.ai.models.ModelDownloadHub
import com.nova.ai.models.WhisperModelSpec

/**
 * The offline Whisper part of the recognition settings: the on/off switch and
 * the choice of model. Shown inside the test card.
 */
@Composable
fun ColumnScope.WhisperEngineSection() {
    val context = LocalContext.current
    val manager: FileModelManager = remember { FileModelManager(context) }

    // Reading this makes the labels refresh after a download ends or a model is deleted.
    val refreshTick: Int = ModelDownloadHub.revision
    val selected: WhisperModelSpec =
        ModelCatalog.find(RecognitionRouting.whisperModelId) ?: ModelCatalog.whisperModels.first()

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = stringResource(R.string.whisper_use_label),
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f)
        )
        Switch(
            checked = RecognitionRouting.useWhisper,
            onCheckedChange = { RecognitionRouting.useWhisper = it }
        )
    }
    Text(
        text = stringResource(R.string.whisper_note),
        style = MaterialTheme.typography.bodySmall
    )

    NovaChoiceGroup(
        title = stringResource(R.string.whisper_model_title),
        options = ModelCatalog.whisperModels,
        selected = selected,
        labelOf = { spec -> whisperModelLabel(spec, manager.isInstalled(spec), refreshTick) },
        onSelected = { RecognitionRouting.whisperModelId = it.id }
    )

    if (RecognitionRouting.useWhisper && !manager.isInstalled(selected)) {
        Text(
            text = stringResource(R.string.whisper_missing),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error
        )
    }
}

@Composable
private fun whisperModelLabel(spec: WhisperModelSpec, installed: Boolean, refreshTick: Int): String {
    // refreshTick only forces this label to be rebuilt; it is not shown.
    check(refreshTick >= 0)
    return stringResource(spec.titleRes) + if (installed) " ✓" else ""
}
