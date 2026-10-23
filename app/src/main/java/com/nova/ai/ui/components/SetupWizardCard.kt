package com.nova.ai.ui.components

import android.accessibilityservice.AccessibilityService
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.nova.ai.R
import com.nova.ai.accessibility.AccessibilityBridge
import com.nova.ai.core.NovaResult
import com.nova.ai.setup.SetupCatalog
import com.nova.ai.setup.SetupChecker
import com.nova.ai.setup.SetupItem
import com.nova.ai.setup.SetupItemId
import com.nova.ai.setup.SetupLauncher

/**
 * The setup wizard: every permission NOVA needs, its status, and one button that
 * asks for the next missing one. Pop-up permissions are asked all together;
 * special permissions open the right settings screen. The card refreshes when
 * the user comes back from settings.
 */
@Composable
fun SetupWizardCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val checker: SetupChecker = remember { SetupChecker(context) }
    var refreshTick: Int by remember { mutableStateOf(0) }
    var message: String? by remember { mutableStateOf<String?>(null) }

    val lifecycleOwner: LifecycleOwner? = context as? LifecycleOwner
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refreshTick += 1
        }
        lifecycleOwner?.lifecycle?.addObserver(observer)
        onDispose { lifecycleOwner?.lifecycle?.removeObserver(observer) }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { _: Map<String, Boolean> -> refreshTick += 1 }

    val statuses: Map<SetupItemId, Boolean> = remember(refreshTick) {
        SetupCatalog.items.associate { item -> item.id to checker.isGranted(item) }
    }
    val doneCount: Int = statuses.values.count { it }
    val total: Int = statuses.size
    val accessibilityEnabled: Boolean = statuses[SetupItemId.ACCESSIBILITY] == true

    fun report(result: NovaResult<Unit>) {
        message = (result as? NovaResult.Failure)?.error?.message
    }

    fun grant(item: SetupItem) {
        message = null
        val permission: String? = item.runtimePermission
        when {
            permission != null -> permissionLauncher.launch(arrayOf(permission))
            item.id == SetupItemId.ACCESSIBILITY -> report(SetupLauncher.openAccessibilitySettings(context))
            item.id == SetupItemId.SYSTEM_SETTINGS -> report(SetupLauncher.openWriteSettings(context))
        }
    }

    fun grantNext() {
        message = null
        val missingRuntime: List<String> = checker.missingRuntimePermissions()
        if (missingRuntime.isNotEmpty()) {
            permissionLauncher.launch(missingRuntime.toTypedArray())
            return
        }
        val next: SetupItem = SetupCatalog.items.firstOrNull { statuses[it.id] != true } ?: return
        grant(next)
    }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = stringResource(R.string.setup_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.setup_note),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.setup_progress, doneCount, total),
                style = MaterialTheme.typography.titleMedium
            )
            LinearProgressIndicator(
                progress = { if (total == 0) 0f else doneCount / total.toFloat() },
                modifier = Modifier.fillMaxWidth()
            )

            if (doneCount < total) {
                Button(onClick = { grantNext() }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.setup_next))
                }
            } else {
                Text(text = stringResource(R.string.setup_all_done))
            }

            SetupCatalog.items.forEach { item ->
                key(item.id) {
                    SetupItemRow(
                        item = item,
                        granted = statuses[item.id] == true,
                        onGrant = { grant(item) }
                    )
                }
            }

            if (accessibilityEnabled) {
                AccessibilitySection(context) { error -> message = error }
            } else {
                Text(
                    text = stringResource(R.string.setup_a11y_help),
                    style = MaterialTheme.typography.bodySmall
                )
            }

            OutlinedButton(
                onClick = { report(SetupLauncher.openAppDetails(context)) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.setup_app_details))
            }

            message?.let { text ->
                Text(
                    text = stringResource(R.string.setup_error, text),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }
        }
    }
}

@Composable
private fun SetupItemRow(item: SetupItem, granted: Boolean, onGrant: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top
    ) {
        Text(text = if (granted) "✅" else "⚪")
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = stringResource(item.titleRes),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(item.whyRes),
                style = MaterialTheme.typography.bodySmall
            )
        }
        if (!granted) {
            OutlinedButton(onClick = onGrant) {
                Text(stringResource(R.string.setup_grant))
            }
        }
    }
}

/** Shown once Accessibility is on: is the service connected, what app was seen, and a Home test. */
@Composable
private fun AccessibilitySection(context: Context, onError: (String?) -> Unit) {
    val connected: Boolean = AccessibilityBridge.isConnected
    val lastPackage: String? = AccessibilityBridge.lastOtherPackage
    val lastLabel: String? = remember(lastPackage) { lastPackage?.let { appLabelOf(context, it) } }

    Text(
        text = stringResource(
            if (connected) R.string.setup_a11y_connected else R.string.setup_a11y_not_connected
        ),
        style = MaterialTheme.typography.bodySmall
    )
    Text(
        text = if (lastLabel != null) {
            stringResource(R.string.setup_last_app, lastLabel)
        } else {
            stringResource(R.string.setup_last_app_none)
        },
        style = MaterialTheme.typography.bodySmall
    )
    OutlinedButton(
        onClick = {
            val result: NovaResult<Unit> =
                AccessibilityBridge.performGlobal(AccessibilityService.GLOBAL_ACTION_HOME)
            onError((result as? NovaResult.Failure)?.error?.message)
        },
        enabled = connected,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(stringResource(R.string.setup_test_home))
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
