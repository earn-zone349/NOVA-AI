package com.nova.ai.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.apps.AliasCodec
import com.nova.ai.apps.InstalledApp
import com.nova.ai.apps.RegisteredApp

private val PICKER_LIST_MAX_HEIGHT: Dp = 360.dp

/**
 * Lets the user tick the apps NOVA may control.
 * Apps already in the library are shown ticked and cannot be changed here.
 */
@Composable
fun AppPickerDialog(
    installed: List<InstalledApp>,
    registeredPackages: Set<String>,
    onConfirm: (List<InstalledApp>) -> Unit,
    onDismiss: () -> Unit
) {
    var query: String by rememberSaveable { mutableStateOf("") }
    val selected = remember { mutableStateListOf<String>() }

    val filtered: List<InstalledApp> = remember(installed, query) {
        val needle: String = query.trim()
        if (needle.isEmpty()) {
            installed
        } else {
            installed.filter { it.label.contains(needle, ignoreCase = true) }
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.picker_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    label = { Text(stringResource(R.string.picker_search)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                if (filtered.isEmpty()) {
                    Text(
                        text = stringResource(R.string.picker_empty),
                        style = MaterialTheme.typography.bodySmall
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = PICKER_LIST_MAX_HEIGHT)
                    ) {
                        items(filtered, key = { it.packageName }) { app ->
                            val alreadyAdded: Boolean = app.packageName in registeredPackages
                            val isChecked: Boolean = alreadyAdded || app.packageName in selected
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable(enabled = !alreadyAdded) {
                                        if (app.packageName in selected) {
                                            selected.remove(app.packageName)
                                        } else {
                                            selected.add(app.packageName)
                                        }
                                    }
                                    .padding(vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                AppIcon(packageName = app.packageName, size = 36.dp)
                                Spacer(modifier = Modifier.width(12.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = app.label,
                                        style = MaterialTheme.typography.bodyMedium
                                    )
                                    if (alreadyAdded) {
                                        Text(
                                            text = stringResource(R.string.picker_already),
                                            style = MaterialTheme.typography.bodySmall
                                        )
                                    }
                                }
                                Checkbox(
                                    checked = isChecked,
                                    onCheckedChange = null,
                                    enabled = !alreadyAdded
                                )
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = { onConfirm(installed.filter { it.packageName in selected }) },
                enabled = selected.isNotEmpty()
            ) {
                Text(stringResource(R.string.picker_confirm, selected.size))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.picker_cancel))
            }
        }
    )
}

/** Lets the user type nicknames for one app, separated by commas. */
@Composable
fun AliasEditDialog(
    app: RegisteredApp,
    onSave: (List<String>) -> Unit,
    onDismiss: () -> Unit
) {
    var text: String by remember(app.packageName) {
        mutableStateOf(app.aliases.joinToString(", "))
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.alias_title, app.label)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = stringResource(R.string.alias_help),
                    style = MaterialTheme.typography.bodySmall
                )
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    label = { Text(stringResource(R.string.alias_hint)) },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            Button(onClick = { onSave(AliasCodec.parseInput(text)) }) {
                Text(stringResource(R.string.alias_save))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.picker_cancel))
            }
        }
    )
}
