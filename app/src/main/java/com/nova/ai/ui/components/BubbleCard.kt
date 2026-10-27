package com.nova.ai.ui.components

import android.content.Context
import android.widget.Toast
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.nova.ai.R
import com.nova.ai.bubble.BubbleController
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import com.nova.ai.security.EmergencyStop

/**
 * Controls for the floating bubble: allow drawing over other apps, show or hide the bubble,
 * and the emergency stop. The permission status is checked again whenever the screen returns
 * from the Android settings.
 */
@Composable
fun BubbleCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val running: Boolean = BubbleController.isRunning
    val stopped: Boolean = EmergencyStop.isActive

    var overlayAllowed: Boolean by remember { mutableStateOf(BubbleController.canDrawOverlays(context)) }
    var micAllowed: Boolean by remember { mutableStateOf(BubbleController.hasMicrophone(context)) }

    val lifecycleOwner: LifecycleOwner? = context as? LifecycleOwner
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                overlayAllowed = BubbleController.canDrawOverlays(context)
                micAllowed = BubbleController.hasMicrophone(context)
            }
        }
        lifecycleOwner?.lifecycle?.addObserver(observer)
        onDispose { lifecycleOwner?.lifecycle?.removeObserver(observer) }
    }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.bub_card_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.bub_card_note),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(
                    if (running) R.string.bub_card_running else R.string.bub_card_not_running
                ),
                style = MaterialTheme.typography.bodyMedium
            )
            if (stopped) {
                Text(
                    text = EmergencyStop.MESSAGE,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }

            if (!overlayAllowed) {
                Text(
                    text = stringResource(R.string.bub_card_overlay_missing),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
                Button(
                    onClick = { openOverlaySettings(context) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.bub_card_allow_overlay))
                }
            }
            if (!micAllowed) {
                Text(
                    text = stringResource(R.string.bub_card_mic_missing),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }

            if (running) {
                OutlinedButton(
                    onClick = { BubbleController.stop(context) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.bub_card_hide))
                }
            } else {
                Button(
                    onClick = { startBubble(context) },
                    enabled = overlayAllowed && micAllowed,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.bub_card_show))
                }
            }

            if (stopped) {
                Button(
                    onClick = { EmergencyStop.release(SOURCE) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.bub_menu_resume))
                }
            } else {
                OutlinedButton(
                    onClick = { EmergencyStop.trigger(SOURCE) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.bub_card_stop))
                }
            }
        }
    }
}

private const val TAG: String = "BubbleCard"
private const val SOURCE: String = "bubble card"

private fun startBubble(context: Context) {
    when (val result: NovaResult<Unit> = BubbleController.start(context)) {
        is NovaResult.Success -> Unit
        is NovaResult.Failure -> {
            NovaLogger.w(TAG, "Bubble did not start: ${result.error.message}")
            Toast.makeText(context, result.error.message, Toast.LENGTH_LONG).show()
        }
    }
}

private fun openOverlaySettings(context: Context) {
    try {
        context.startActivity(BubbleController.overlaySettingsIntent(context))
    } catch (e: Exception) {
        NovaLogger.w(TAG, "Could not open the overlay settings", e)
        Toast.makeText(context, context.getString(R.string.bub_card_settings_failed), Toast.LENGTH_LONG).show()
    }
}
