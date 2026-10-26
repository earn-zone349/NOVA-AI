package com.nova.ai.ui.components

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.accessibility.AccessibilityBridge
import com.nova.ai.accessibility.ActionGate
import com.nova.ai.accessibility.ActionLab
import com.nova.ai.accessibility.ActionLabMessage
import com.nova.ai.accessibility.LabAction

/**
 * Test card for NOVA's hands: click a button by its name, type into a field, scroll,
 * press Back, Home or recent apps, and make finger gestures (swipe, long press, double tap,
 * pinch, two-finger swipe). With the 5-second option the action runs after a countdown,
 * so it can be tested on another app. With the check option, a click, typing, scroll, Back or
 * Home is verified on the screen afterwards. Also tests the emergency stop.
 */
@Composable
fun ActionLabCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val connected: Boolean = AccessibilityBridge.isConnected
    val waitingSeconds: Int = ActionLab.waitingSeconds
    val message: ActionLabMessage? = ActionLab.message
    val stopped: Boolean = ActionGate.isStopped

    var query: String by rememberSaveable { mutableStateOf("") }
    var typed: String by rememberSaveable { mutableStateOf("") }
    var delayed: Boolean by rememberSaveable { mutableStateOf(false) }
    var verify: Boolean by rememberSaveable { mutableStateOf(false) }

    fun run(action: LabAction) {
        ActionLab.run(context, action, query, typed, delayed, verify)
    }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.act_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.act_note),
                style = MaterialTheme.typography.bodySmall
            )
            if (!connected) {
                Text(
                    text = stringResource(R.string.act_need_service),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }

            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text(stringResource(R.string.act_query_label)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedTextField(
                value = typed,
                onValueChange = { typed = it },
                label = { Text(stringResource(R.string.act_text_label)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.act_delay_label),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f)
                )
                Switch(checked = delayed, onCheckedChange = { delayed = it })
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.ver_label),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f)
                )
                Switch(checked = verify, onCheckedChange = { verify = it })
            }

            if (waitingSeconds > 0) {
                Text(text = stringResource(R.string.act_waiting, waitingSeconds))
                OutlinedButton(
                    onClick = { ActionLab.cancel() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.act_cancel))
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = { run(LabAction.CLICK) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_click))
                }
                Button(
                    onClick = { run(LabAction.TYPE) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_type))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { run(LabAction.SCROLL_UP) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_scroll_up))
                }
                OutlinedButton(
                    onClick = { run(LabAction.SCROLL_DOWN) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_scroll_down))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { run(LabAction.BACK) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_back))
                }
                OutlinedButton(
                    onClick = { run(LabAction.HOME) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_home))
                }
                OutlinedButton(
                    onClick = { run(LabAction.RECENTS) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_recents))
                }
            }

            Text(
                text = stringResource(R.string.gst_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.gst_note),
                style = MaterialTheme.typography.bodySmall
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_swipe_up, connected) { run(LabAction.SWIPE_UP) }
                GestureButton(R.string.gst_swipe_down, connected) { run(LabAction.SWIPE_DOWN) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_swipe_left, connected) { run(LabAction.SWIPE_LEFT) }
                GestureButton(R.string.gst_swipe_right, connected) { run(LabAction.SWIPE_RIGHT) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_long_press, connected) { run(LabAction.LONG_PRESS) }
                GestureButton(R.string.gst_double_tap, connected) { run(LabAction.DOUBLE_TAP) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_pinch_out, connected) { run(LabAction.PINCH_OUT) }
                GestureButton(R.string.gst_pinch_in, connected) { run(LabAction.PINCH_IN) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_two_up, connected) { run(LabAction.TWO_FINGER_UP) }
                GestureButton(R.string.gst_two_down, connected) { run(LabAction.TWO_FINGER_DOWN) }
            }

            message?.let { shown ->
                Text(
                    text = (if (shown.success) "✅ " else "⚠️ ") + shown.text,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (shown.success) {
                        MaterialTheme.colorScheme.onSurface
                    } else {
                        MaterialTheme.colorScheme.error
                    }
                )
            }

            Text(
                text = stringResource(R.string.act_stop_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(if (stopped) R.string.act_stop_on else R.string.act_stop_off),
                style = MaterialTheme.typography.bodySmall
            )
            OutlinedButton(
                onClick = { if (stopped) ActionGate.resume() else ActionGate.stop() },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    stringResource(if (stopped) R.string.act_stop_disable else R.string.act_stop_enable)
                )
            }
        }
    }
}

// One equally wide gesture button inside a row of the test card.
@Composable
private fun RowScope.GestureButton(label: Int, enabled: Boolean, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.weight(1f)
    ) {
        Text(stringResource(label))
    }
}
