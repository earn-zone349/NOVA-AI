package com.nova.ai.bubble

import com.nova.ai.apps.AppActionUi
import com.nova.ai.apps.InstalledApp
import com.nova.ai.apps.RegisteredApp
import com.nova.ai.contacts.Contact
import com.nova.ai.contacts.ContactActionUi
import com.nova.ai.system.OutcomeKind
import com.nova.ai.system.SystemActionOutcome
import com.nova.ai.time.TimeActionUi
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests which messages of the bubble mean "an error was reported, so trying again is safe". */
class BubbleOutputRetryableTest {

    private class Texts : BubbleTexts {
        override fun opened(appLabel: String) = "opened"
        override fun confirmApp(appLabel: String) = "confirm"
        override fun chooseApp(spoken: String) = "choose"
        override fun suggestApp(spoken: String) = "suggest"
        override fun appNotFound(spoken: String) = "noapp"
        override fun chooseContact(spoken: String) = "chooseContact"
        override fun chooseNumber(contactName: String) = "chooseNumber"
        override fun confirmCall(who: String, number: String) = "call"
        override fun contactNotFound(spoken: String) = "nocontact"
        override fun askPeriod(clockText: String) = "period"
        override fun needsContactsPermission() = "needs"
        override fun yesOpen() = "yes"
        override fun callNow() = "callnow"
        override fun notUnderstood() = "?"
        override fun notDone() = "notdone"
    }

    private class Actions : BubbleActions {
        override fun confirmApp() {}
        override fun chooseApp(app: RegisteredApp) {}
        override fun addAndOpen(app: InstalledApp) {}
        override fun pickContact(contact: Contact) {}
        override fun pickNumber(number: String) {}
        override fun placeCall(number: String) {}
        override fun choosePeriod(isEvening: Boolean) {}
    }

    private val mapper = BubbleOutputMapper(Texts(), Actions())

    private fun retryable(
        app: AppActionUi = AppActionUi.Idle,
        contact: ContactActionUi = ContactActionUi.Idle,
        time: TimeActionUi = TimeActionUi.Idle,
        system: SystemActionOutcome? = null
    ): Boolean = (mapper.map(app, contact, time, system, null) as BubbleOutput.Message).retryable

    @Test
    fun reportedErrorsMayBeTriedAgain() {
        assertTrue(retryable(app = AppActionUi.Failed("x")))
        assertTrue(retryable(contact = ContactActionUi.Failed("x")))
        assertTrue(retryable(time = TimeActionUi.Failed("x")))
        assertTrue(retryable(system = SystemActionOutcome(OutcomeKind.FAILED, "x")))
    }

    @Test
    fun notFoundHintsAndInfoMayNot() {
        assertFalse(retryable(app = AppActionUi.NotFound("x")))
        assertFalse(retryable(contact = ContactActionUi.NotFound("x")))
        assertFalse(retryable(contact = ContactActionUi.Info("x")))
        assertFalse(retryable(time = TimeActionUi.NeedsDetail("x")))
        assertFalse(retryable(system = SystemActionOutcome(OutcomeKind.HINT, "x")))
    }
}
