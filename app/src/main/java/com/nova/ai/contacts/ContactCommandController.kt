package com.nova.ai.contacts

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.annotation.StringRes
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.nova.ai.R
import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.nlp.IntentEntity
import com.nova.ai.voice.LanguageDetector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** What the Home screen shows about the last call or message command. */
sealed class ContactActionUi {
    object Idle : ContactActionUi()
    object NeedsContactsPermission : ContactActionUi()
    data class ChooseContact(
        val purpose: ContactPurpose,
        val spoken: String,
        val contacts: List<Contact>,
        val body: String?
    ) : ContactActionUi()
    data class ChooseNumber(
        val purpose: ContactPurpose,
        val contact: Contact,
        val body: String?
    ) : ContactActionUi()
    data class ConfirmCall(val name: String?, val number: String) : ContactActionUi()
    data class Done(val message: String) : ContactActionUi()
    data class Info(val message: String) : ContactActionUi()
    data class NotFound(val spoken: String) : ContactActionUi()
    data class Failed(val message: String) : ContactActionUi()
}

/**
 * Turns "call" and "send message" commands into real actions.
 * A call always needs the user's confirmation first. A message opens the SMS app
 * with the text ready; the user taps send. Use from the main thread.
 */
class ContactCommandController(
    context: Context,
    private val scope: CoroutineScope
) {

    private val appContext: Context = context.applicationContext
    private val repository = ContactRepository(appContext)
    private val actions = PhoneActions(appContext)
    private val brain = RuleBasedBrain()

    private var pendingIntent: NovaIntent? = null
    private var pendingCallNumber: String? = null

    var state: ContactActionUi by mutableStateOf<ContactActionUi>(ContactActionUi.Idle)
        private set

    /** Looks at [text]; if it asks for a call or a message, starts that flow. */
    fun handleCommand(text: String) {
        pendingIntent = null
        val intent: NovaIntent? = analyze(text)
        val relevant: Boolean = intent != null &&
            (intent.type == IntentType.MAKE_CALL || intent.type == IntentType.SEND_MESSAGE)
        if (intent == null || !relevant) {
            state = ContactActionUi.Idle
            return
        }
        process(intent)
    }

    /** The user answered the contacts permission question. */
    fun onContactsPermissionResult(granted: Boolean) {
        val intent: NovaIntent? = pendingIntent
        pendingIntent = null
        if (granted && intent != null) {
            process(intent)
        } else {
            state = ContactActionUi.Info(text(R.string.contact_permission_denied))
        }
    }

    /** The user picked one of several matching contacts. */
    fun pickContact(contact: Contact) {
        val current: ContactActionUi.ChooseContact = state as? ContactActionUi.ChooseContact ?: return
        chooseNumber(current.purpose, contact, current.body)
    }

    /** The user picked one of several numbers of a contact. */
    fun pickNumber(number: String) {
        val current: ContactActionUi.ChooseNumber = state as? ContactActionUi.ChooseNumber ?: return
        proceedWithNumber(current.purpose, current.contact.name, number, current.body)
    }

    /** True if the user allowed NOVA to place calls directly. */
    fun hasCallPermission(): Boolean = ContextCompat.checkSelfPermission(
        appContext, Manifest.permission.CALL_PHONE
    ) == PackageManager.PERMISSION_GRANTED

    /** Remembers the number while the call permission question is shown. */
    fun rememberPendingCall(number: String) {
        pendingCallNumber = number
    }

    /** The user answered the call permission question. */
    fun onCallPermissionResult(granted: Boolean) {
        val number: String = pendingCallNumber ?: return
        pendingCallNumber = null
        if (granted) {
            placeCall(number)
        } else {
            state = when (val result: NovaResult<Unit> = actions.dial(number)) {
                is NovaResult.Success -> ContactActionUi.Info(text(R.string.contact_call_denied))
                is NovaResult.Failure -> ContactActionUi.Failed(result.error.message)
            }
        }
    }

    /** Places the confirmed call (opens the dialer instead if the permission is missing). */
    fun placeCall(number: String) {
        if (!hasCallPermission()) {
            dial(number)
            return
        }
        state = when (val result: NovaResult<Unit> = actions.call(number)) {
            is NovaResult.Success -> ContactActionUi.Done(text(R.string.contact_call_started))
            is NovaResult.Failure -> ContactActionUi.Failed(result.error.message)
        }
    }

    /** Opens the dialer with the number filled in. */
    fun dial(number: String) {
        state = when (val result: NovaResult<Unit> = actions.dial(number)) {
            is NovaResult.Success -> ContactActionUi.Done(text(R.string.contact_dialer_opened))
            is NovaResult.Failure -> ContactActionUi.Failed(result.error.message)
        }
    }

    /** Hides the card. */
    fun dismiss() {
        pendingIntent = null
        pendingCallNumber = null
        state = ContactActionUi.Idle
    }

    private fun process(intent: NovaIntent) {
        val purpose: ContactPurpose =
            if (intent.type == IntentType.MAKE_CALL) ContactPurpose.CALL else ContactPurpose.SMS

        // Calls and messages through other apps (WhatsApp and so on) come in a later phase.
        val app: String? = intent.entities[IntentEntity.APP]
        if (app != null && !(purpose == ContactPurpose.SMS && app == SMS_APP_NAME)) {
            state = ContactActionUi.Info(text(R.string.contact_app_later))
            return
        }

        val body: String? = intent.entities[IntentEntity.BODY]
        val number: String? = intent.entities[IntentEntity.NUMBER]
        val contactName: String? = intent.entities[IntentEntity.CONTACT]

        when {
            number != null -> proceedWithNumber(purpose, null, number, body)
            contactName != null -> lookUpContact(intent, purpose, contactName, body)
            else -> state = ContactActionUi.Info(
                text(if (purpose == ContactPurpose.CALL) R.string.contact_who_call else R.string.contact_who_sms)
            )
        }
    }

    private fun lookUpContact(
        intent: NovaIntent,
        purpose: ContactPurpose,
        spoken: String,
        body: String?
    ) {
        if (!repository.hasPermission()) {
            pendingIntent = intent
            state = ContactActionUi.NeedsContactsPermission
            return
        }
        scope.launch {
            val contacts: List<Contact> = when (val result = repository.loadAll()) {
                is NovaResult.Success -> result.value
                is NovaResult.Failure -> {
                    state = ContactActionUi.Failed(result.error.message)
                    return@launch
                }
            }
            when (val outcome: ContactOutcome = ContactMatcher.match(spoken, contacts)) {
                is ContactOutcome.Single -> chooseNumber(purpose, outcome.contact, body)
                is ContactOutcome.Ambiguous ->
                    state = ContactActionUi.ChooseContact(purpose, spoken, outcome.contacts, body)
                is ContactOutcome.None -> state = ContactActionUi.NotFound(spoken)
            }
        }
    }

    private fun chooseNumber(purpose: ContactPurpose, contact: Contact, body: String?) {
        if (contact.numbers.size == 1) {
            proceedWithNumber(purpose, contact.name, contact.numbers.first(), body)
        } else {
            state = ContactActionUi.ChooseNumber(purpose, contact, body)
        }
    }

    private fun proceedWithNumber(
        purpose: ContactPurpose,
        name: String?,
        number: String,
        body: String?
    ) {
        when (purpose) {
            ContactPurpose.CALL -> state = ContactActionUi.ConfirmCall(name, number)
            ContactPurpose.SMS -> openSms(name, number, body)
        }
    }

    private fun openSms(name: String?, number: String, body: String?) {
        state = when (val result: NovaResult<Unit> = actions.composeSms(number, body)) {
            is NovaResult.Success -> ContactActionUi.Done(text(R.string.contact_sms_opened, name ?: number))
            is NovaResult.Failure -> ContactActionUi.Failed(result.error.message)
        }
    }

    private fun analyze(text: String): NovaIntent? {
        if (text.isBlank()) return null
        val command = VoiceCommand(
            rawText = text,
            language = LanguageDetector.detect(text),
            timestampMs = System.currentTimeMillis()
        )
        return (brain.analyze(command, emptyList()) as? NovaResult.Success)?.value
    }

    private fun text(@StringRes id: Int, vararg args: Any): String = appContext.getString(id, *args)

    private companion object {
        const val SMS_APP_NAME: String = "SMS"
    }
}
