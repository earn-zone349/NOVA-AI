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
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.accessibility.AccessibilityBridge
import com.nova.ai.accessibility.ScreenReadController
import com.nova.ai.accessibility.ScreenReadState

private const val MAX_ITEMS_SHOWN: Int = 40

/**
 * Lets the user have the screen in front read aloud and shows what was found:
 * texts, buttons and input fields.
 */
@Composable
fun ScreenReadCard(
    controller: ScreenReadController,
    modifier: Modifier = Modifier
) {
    val connected: Boolean = AccessibilityBridge.isConnected
    val state: ScreenReadState = controller.state

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
                Text(text = "🔐 " + stringResource(R.string.scr_not_connected))
            }

            Button(
                onClick = { controller.readAfterDelay() },
                enabled = connected && state !is ScreenReadState.Waiting,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.scr_read_delayed))
            }
            OutlinedButton(
                onClick = { controller.readNow() },
                enabled = connected,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.scr_read_now))
            }

            when (state) {
                ScreenReadState.Idle -> Unit
                is ScreenReadState.Waiting ->
                    Text(text = stringResource(R.string.scr_waiting, state.secondsLeft))
                is ScreenReadState.Failed -> Text(text = "⚠️ " + state.message)
                is ScreenReadState.Done -> ReportContent(LocalContext.current, state)
            }

            if (state !is ScreenReadState.Idle) {
                TextButton(onClick = { controller.stop() }) {
                    Text(stringResource(R.string.scr_stop))
                }
            }

            Text(
                text = stringResource(R.string.scr_privacy),
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}

@Composable
private fun ReportContent(context: Context, done: ScreenReadState.Done) {
    val summary = done.summary
    val appName: String = remember(done.appPackage) {
        done.appPackage?.let { appLabelOf(context, it) } ?: ""
    }

    if (appName.isNotBlank()) {
        Text(
            text = stringResource(R.string.scr_app, appName),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold
        )
    }
    Text(
        text = stringResource(
            R.string.scr_counts,
            summary.texts.size,
            summary.actions.size,
            summary.fields.size + summary.unnamedFields
        )
    )
    Text(
        text = stringResource(R.string.scr_stats, done.nodeCount, done.durationMs.toInt()),
        style = MaterialTheme.typography.bodySmall
    )
    if (done.hiddenSensitive > 0) {
        Text(
            text = stringResource(R.string.scr_hidden, done.hiddenSensitive),
            style = MaterialTheme.typography.bodySmall
        )
    }
    done.speakError?.let { message ->
        Text(text = "⚠️ " + stringResource(R.string.scr_speak_error, message))
    }
    if (done.screenTruncated) {
        Text(
            text = stringResource(R.string.scr_screen_truncated),
            style = MaterialTheme.typography.bodySmall
        )
    }
    if (done.speechTruncated) {
        Text(
            text = stringResource(R.string.scr_truncated),
            style = MaterialTheme.typography.bodySmall
        )
    }

    ReportSection(stringResource(R.string.scr_texts_title), summary.texts)
    ReportSection(stringResource(R.string.scr_buttons_title), summary.actions)
    ReportSection(stringResource(R.string.scr_fields_title), summary.fields)
    if (summary.unnamedFields > 0) {
        Text(text = stringResource(R.string.scr_unnamed_fields, summary.unnamedFields))
    }
}

@Composable
private fun ReportSection(title: String, items: List<String>) {
    if (items.isEmpty()) return
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold
    )
    items.take(MAX_ITEMS_SHOWN).forEach { item ->
        Text(text = "• $item", style = MaterialTheme.typography.bodyMedium)
    }
    if (items.size > MAX_ITEMS_SHOWN) {
        Text(
            text = stringResource(R.string.scr_more, items.size - MAX_ITEMS_SHOWN),
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
