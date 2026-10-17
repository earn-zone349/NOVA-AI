package com.nova.ai.ui.components

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.contacts.ContactActionUi
import com.nova.ai.contacts.ContactCommandController

/**
 * Shows the steps of a call or message command on the Home screen: permission
 * question, choosing a contact or number, and the call confirmation.
 * Shows nothing while there is nothing to report.
 */
@Composable
fun ContactActionCard(
    controller: ContactCommandController,
    modifier: Modifier = Modifier
) {
    // Permission launchers must exist whatever the card shows.
    val contactsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted: Boolean -> controller.onContactsPermissionResult(granted) }

    val callLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted: Boolean -> controller.onCallPermissionResult(granted) }

    val current: ContactActionUi = controller.state
    if (current is ContactActionUi.Idle) return

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.contact_title),
                style = MaterialTheme.typography.titleMedium
            )

            when (current) {
                is ContactActionUi.Idle -> Unit

                is ContactActionUi.NeedsContactsPermission -> {
                    Text(stringResource(R.string.contact_permission_needed))
                    Button(
                        onClick = { contactsLauncher.launch(Manifest.permission.READ_CONTACTS) },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.contact_permission_button))
                    }
                }

                is ContactActionUi.ChooseContact -> {
                    Text(stringResource(R.string.contact_choose, current.spoken))
                    current.contacts.forEach { contact ->
                        val firstNumber: String = contact.numbers.firstOrNull().orEmpty()
                        Button(
                            onClick = { controller.pickContact(contact) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("${contact.name} $firstNumber".trim())
                        }
                    }
                }

                is ContactActionUi.ChooseNumber -> {
                    Text(stringResource(R.string.contact_choose_number, current.contact.name))
                    current.contact.numbers.forEach { number ->
                        Button(
                            onClick = { controller.pickNumber(number) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(number)
                        }
                    }
                }

                is ContactActionUi.ConfirmCall -> {
                    val name: String? = current.name
                    Text(
                        if (name != null) {
                            stringResource(R.string.contact_confirm_call, name, current.number)
                        } else {
                            stringResource(R.string.contact_confirm_call_number, current.number)
                        }
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = {
                                if (controller.hasCallPermission()) {
                                    controller.placeCall(current.number)
                                } else {
                                    controller.rememberPendingCall(current.number)
                                    callLauncher.launch(Manifest.permission.CALL_PHONE)
                                }
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(stringResource(R.string.contact_call_button))
                        }
                        OutlinedButton(
                            onClick = { controller.dial(current.number) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(stringResource(R.string.contact_dial_button))
                        }
                    }
                }

                is ContactActionUi.Done -> Text("✅ ${current.message}")

                is ContactActionUi.Info -> Text("💡 ${current.message}")

                is ContactActionUi.NotFound ->
                    Text(stringResource(R.string.contact_not_found, current.spoken))

                is ContactActionUi.Failed ->
                    Text(stringResource(R.string.contact_failed, current.message))
            }

            TextButton(onClick = { controller.dismiss() }) {
                Text(stringResource(R.string.contact_cancel))
            }
        }
    }
}
