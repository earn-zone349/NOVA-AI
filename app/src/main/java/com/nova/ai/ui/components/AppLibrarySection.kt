package com.nova.ai.ui.components

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.apps.AppLibraryController
import com.nova.ai.apps.RegisteredApp
import kotlinx.coroutines.CoroutineScope

/**
 * "NOVA's apps": the list of apps NOVA may control. The user adds apps from the
 * phone's app list, gives them nicknames, and removes them. Shown in the Access tab.
 */
@Composable
fun AppLibrarySection(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val scope: CoroutineScope = rememberCoroutineScope()
    val controller: AppLibraryController = remember { AppLibraryController(context, scope) }

    var showPicker: Boolean by remember { mutableStateOf(false) }
    var editingApp: RegisteredApp? by remember { mutableStateOf<RegisteredApp?>(null) }

    LaunchedEffect(controller) { controller.refresh() }

    val installedPackages: Set<String> =
        remember(controller.installed) { controller.installed.map { it.packageName }.toSet() }
    val registeredPackages: Set<String> =
        remember(controller.registered) { controller.registered.map { it.packageName }.toSet() }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.apps_title),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = stringResource(R.string.apps_note),
            style = MaterialTheme.typography.bodySmall
        )

        val error: String? = controller.errorMessage
        if (error != null) {
            Text(
                text = stringResource(R.string.apps_error, error),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
        }

        Text(
            text = stringResource(R.string.apps_count, controller.registered.size),
            style = MaterialTheme.typography.bodyMedium
        )
        Button(
            onClick = { showPicker = true },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(stringResource(R.string.apps_add_button))
        }

        if (controller.registered.isEmpty() && !controller.isLoading) {
            NovaInfoCard(
                title = stringResource(R.string.apps_title),
                body = stringResource(R.string.apps_empty)
            )
        }

        controller.registered.forEach { app ->
            key(app.packageName) {
                RegisteredAppCard(
                    app = app,
                    missing = installedPackages.isNotEmpty() && app.packageName !in installedPackages,
                    onEdit = { editingApp = app },
                    onRemove = { controller.removeApp(app.packageName) }
                )
            }
        }
    }

    if (showPicker) {
        AppPickerDialog(
            installed = controller.installed,
            registeredPackages = registeredPackages,
            onConfirm = { chosen ->
                controller.addApps(chosen)
                showPicker = false
            },
            onDismiss = { showPicker = false }
        )
    }

    editingApp?.let { app ->
        AliasEditDialog(
            app = app,
            onSave = { aliases ->
                controller.saveAliases(app.packageName, aliases)
                editingApp = null
            },
            onDismiss = { editingApp = null }
        )
    }
}

@Composable
private fun RegisteredAppCard(
    app: RegisteredApp,
    missing: Boolean,
    onEdit: () -> Unit,
    onRemove: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AppIcon(packageName = app.packageName, size = 40.dp)
                Spacer(modifier = Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(text = app.label, style = MaterialTheme.typography.titleMedium)
                    Text(
                        text = if (app.aliases.isEmpty()) {
                            stringResource(R.string.apps_alias_none)
                        } else {
                            stringResource(R.string.apps_alias_label, app.aliases.joinToString(", "))
                        },
                        style = MaterialTheme.typography.bodySmall
                    )
                    if (missing) {
                        Text(
                            text = stringResource(R.string.apps_not_installed),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onEdit, modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.apps_edit))
                }
                OutlinedButton(onClick = onRemove, modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.apps_remove))
                }
            }
        }
    }
}
