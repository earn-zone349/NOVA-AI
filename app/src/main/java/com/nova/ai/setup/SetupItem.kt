package com.nova.ai.setup

import android.Manifest
import androidx.annotation.StringRes
import com.nova.ai.R

/** The permissions NOVA needs the user to grant. Later phases add more. */
enum class SetupItemId {
    MICROPHONE,
    CONTACTS,
    CALL,
    NOTIFICATIONS,
    ACCESSIBILITY,
    SYSTEM_SETTINGS
}

/**
 * One permission in the setup wizard. [runtimePermission] is the Android permission
 * asked with a pop-up; it is null for special permissions the user switches on in Settings.
 */
data class SetupItem(
    val id: SetupItemId,
    @StringRes val titleRes: Int,
    @StringRes val whyRes: Int,
    val runtimePermission: String? = null
)

/** The list shown in the setup wizard, in the order they are asked. */
object SetupCatalog {

    val items: List<SetupItem> = listOf(
        SetupItem(
            SetupItemId.MICROPHONE,
            R.string.setup_mic_title,
            R.string.setup_mic_why,
            Manifest.permission.RECORD_AUDIO
        ),
        SetupItem(
            SetupItemId.CONTACTS,
            R.string.setup_contacts_title,
            R.string.setup_contacts_why,
            Manifest.permission.READ_CONTACTS
        ),
        SetupItem(
            SetupItemId.CALL,
            R.string.setup_call_title,
            R.string.setup_call_why,
            Manifest.permission.CALL_PHONE
        ),
        SetupItem(
            SetupItemId.NOTIFICATIONS,
            R.string.setup_notif_title,
            R.string.setup_notif_why,
            Manifest.permission.POST_NOTIFICATIONS
        ),
        SetupItem(
            SetupItemId.ACCESSIBILITY,
            R.string.setup_a11y_title,
            R.string.setup_a11y_why
        ),
        SetupItem(
            SetupItemId.SYSTEM_SETTINGS,
            R.string.setup_settings_title,
            R.string.setup_settings_why
        )
    )
}
