package com.nova.ai.ui.components

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.accessibility.AccessibilityBridge
import com.nova.ai.accessibility.ScreenReadLab
import com.nova.ai.accessibility.ScreenReadResult

private const val SHOWN_TEXTS: Int = 20
private const val SHOWN_ACTIONS: Int = 12
private const val SHOWN_FIELDS: Int = 8

/**
 * Test card for the screen reader: read NOVA's own screen at once, or read the
 * screen of another app after a 5-second countdown, then see what was found.
 */
@Composable
fun ScreenReadLabCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val connected: Boolean = AccessibilityBridge.isConnected
    val waitingSeconds: Int = ScreenReadLab.waitingSeconds
    val result: ScreenReadResult? = ScreenReadLab.result
    val error: String? = ScreenReadLab.errorMessage

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.scr_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.scr_note),
                style = MaterialTheme.typography.bodySmall
            )

            if (!connected) {
                Text(
                    text = stringResource(R.string.scr_need_service),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }

            Button(
                onClick = { ScreenReadLab.readNow() },
                enabled = connected,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.scr_read_now))
            }

            if (waitingSeconds > 0) {
                Text(text = stringResource(R.string.scr_waiting, waitingSeconds))
                OutlinedButton(
                    onClick = { ScreenReadLab.cancel() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.scr_cancel))
                }
            } else {
                OutlinedButton(
                    onClick = { ScreenReadLab.readAfterCountdown() },
                    enabled = connected,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.scr_read_later))
                }
            }

            error?.let { message ->
                Text(
                    text = stringResource(R.string.scr_error, message),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }

            result?.let { shown -> ScreenReadResultBlock(context, shown) }
        }
    }
}

@Composable
private fun ScreenReadResultBlock(context: Context, shown: ScreenReadResult) {
    val capture = shown.capture
    val summary = shown.summary
    val appName: String = remember(capture.packageName) {
        capture.packageName?.let { appLabelOf(context, it) } ?: ""
    }
    val emptyFieldLabel: String = stringResource(R.string.scr_field_empty)

    Text(
        text = stringResource(R.string.scr_header, appName),
        style = MaterialTheme.typography.titleMedium
    )
    Text(
        text = stringResource(R.string.scr_stats, capture.nodes.size, capture.durationMs.toInt()),
        style = MaterialTheme.typography.bodySmall
    )
    if (capture.truncated) {
        Text(
            text = stringResource(R.string.scr_truncated),
            style = MaterialTheme.typography.bodySmall
        )
    }
    if (capture.hiddenSensitiveCount > 0) {
        Text(
            text = stringResource(R.string.scr_hidden, capture.hiddenSensitiveCount),
            style = MaterialTheme.typography.bodySmall
        )
    }

    ListBlock(
        title = stringResource(R.string.scr_texts_title, summary.texts.size),
        items = summary.texts,
        limit = SHOWN_TEXTS,
        blankLabel = emptyFieldLabel
    )
    ListBlock(
        title = stringResource(R.string.scr_actions_title, summary.actions.size),
        items = summary.actions,
        limit = SHOWN_ACTIONS,
        blankLabel = emptyFieldLabel
    )
    ListBlock(
        title = stringResource(R.string.scr_fields_title, summary.fields.size),
        items = summary.fields,
        limit = SHOWN_FIELDS,
        blankLabel = emptyFieldLabel
    )
}

@Composable
private fun ListBlock(title: String, items: List<String>, limit: Int, blankLabel: String) {
    Text(text = title, style = MaterialTheme.typography.titleMedium)
    if (items.isEmpty()) {
        Text(
            text = stringResource(R.string.scr_none),
            style = MaterialTheme.typography.bodySmall
        )
        return
    }
    items.take(limit).forEach { item ->
        Text(
            text = "• " + item.ifBlank { blankLabel },
            style = MaterialTheme.typography.bodySmall
        )
    }
    if (items.size > limit) {
        Text(
            text = "… +${items.size - limit}",
            style = MaterialTheme.typography.bodySmall
        )
    }
}

/** The name of an installed app, or its package name if the name cannot be read. */
@Suppress("DEPRECATION")
private fun appLabelOf(context: Context, packageName: String): String = try {
    val manager = context.packageManager
    manager.getApplicationLabel(manager.getApplicationInfo(packageName, 0)).toString()
} catch (e: Exception) {
    packageName
}
