package com.nova.ai.bubble

import com.nova.ai.apps.InstalledApp
import com.nova.ai.apps.RegisteredApp
import com.nova.ai.contacts.Contact

/** What kind of line a message is, for its icon and color. */
internal enum class MessageKind { DONE, INFO, ERROR }

/** One choice of a [BubbleOutput.Decision]. [action] runs when the user taps it. */
internal data class BubbleOption(
    val label: String,
    val emphasis: Boolean = false,
    val action: () -> Unit
)

/** What the bubble shows after a command: nothing yet, a message, a question, or "open the app". */
internal sealed class BubbleOutput {

    /** Nothing to show (yet). */
    object None : BubbleOutput()

    /** A finished result, or a note. */
    data class Message(
        val text: String,
        val kind: MessageKind,
        /** True if the job is finished. A guided screen (the user taps the last step) counts as finished. */
        val completed: Boolean = kind == MessageKind.DONE
    ) : BubbleOutput()

    /**
     * A question the user must answer by tapping one of the [options] (or cancel). [source] is the
     * state the question came from, so the same question is not shown twice.
     */
    data class Decision(
        val source: Any,
        val question: String,
        val options: List<BubbleOption>
    ) : BubbleOutput()

    /** The step needs something only the app screen can do (a permission pop-up, for example). */
    data class NeedsApp(val text: String) : BubbleOutput()
}

/** The texts of the bubble. The app reads them from resources; tests use a fake. */
internal interface BubbleTexts {
    fun opened(appLabel: String): String
    fun confirmApp(appLabel: String): String
    fun chooseApp(spoken: String): String
    fun suggestApp(spoken: String): String
    fun appNotFound(spoken: String): String
    fun chooseContact(spoken: String): String
    fun chooseNumber(contactName: String): String
    fun confirmCall(who: String, number: String): String
    fun contactNotFound(spoken: String): String
    fun askPeriod(clockText: String): String
    fun needsContactsPermission(): String
    fun yesOpen(): String
    fun callNow(): String
    fun notUnderstood(): String
    fun notDone(): String
}

/** What the bubble can do when the user answers a question. The router connects it to the controllers. */
internal interface BubbleActions {
    fun confirmApp()
    fun chooseApp(app: RegisteredApp)
    fun addAndOpen(app: InstalledApp)
    fun pickContact(contact: Contact)
    fun pickNumber(number: String)
    fun placeCall(number: String)
    fun choosePeriod(isEvening: Boolean)
}
