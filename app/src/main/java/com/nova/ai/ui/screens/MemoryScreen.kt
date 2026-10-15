package com.nova.ai.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout

/** Memory: on/off switch and saved items. Real storage is connected in P33. */
@Composable
fun MemoryScreen(modifier: Modifier = Modifier) {
    var memoryEnabled: Boolean by rememberSaveable { mutableStateOf(true) }

    NovaScreenLayout(
        title = stringResource(R.string.memory_title),
        subtitle = stringResource(R.string.memory_subtitle),
        modifier = modifier
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = stringResource(R.string.memory_enabled_label),
                style = MaterialTheme.typography.titleMedium
            )
            Switch(checked = memoryEnabled, onCheckedChange = { memoryEnabled = it })
        }
        NovaInfoCard(
            title = stringResource(R.string.memory_title),
            body = stringResource(R.string.memory_empty)
        )
        Text(
            text = stringResource(R.string.memory_actions_note),
            style = MaterialTheme.typography.bodySmall
        )
    }
}
