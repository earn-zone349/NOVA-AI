package com.nova.ai.bubble

import com.nova.ai.apps.AppActionUi
import com.nova.ai.apps.InstalledApp
import com.nova.ai.apps.RegisteredApp
import com.nova.ai.contacts.Contact
import com.nova.ai.contacts.ContactActionUi
import com.nova.ai.contacts.ContactPurpose
import com.nova.ai.system.OutcomeKind
import com.nova.ai.system.SystemActionOutcome
import com.nova.ai.time.TimeActionUi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests what the bubble shows for each controller state. Plain JVM test. */
class BubbleOutputMapperTest {

    private class FakeTexts : BubbleTexts {
        override fun opened(appLabel: String) = "opened $appLabel"
        override fun confirmApp(appLabel: String) = "confirm $appLabel"
        override fun chooseApp(spoken: String) = "chooseApp $spoken"
        override fun suggestApp(spoken: String) = "suggest $spoken"
        override fun appNotFound(spoken: String) = "noapp $spoken"
        override fun chooseContact(spoken: String) = "chooseContact $spoken"
        override fun chooseNumber(contactName: String) = "chooseNumber $contactName"
        override fun confirmCall(who: String, number: String) = "call $who $number"
        override fun contactNotFound(spoken: String) = "nocontact $spoken"
        override fun askPeriod(clockText: String) = "period $clockText"
        override fun needsContactsPermission() = "needs contacts"
        override fun yesOpen() = "yes"
        override fun callNow() = "callnow"
        override fun notUnderstood() = "?"
        override fun notDone() = "notdone"
    }

    private class RecordingActions : BubbleActions {
        val log = mutableListOf<String>()
        override fun confirmApp() { log.add("confirmApp") }
        override fun chooseApp(app: RegisteredApp) { log.add("chooseApp ${app.label}") }
        override fun addAndOpen(app: InstalledApp) { log.add("addAndOpen ${app.label}") }
        override fun pickContact(contact: Contact) { log.add("pickContact ${contact.name}") }
        override fun pickNumber(number: String) { log.add("pickNumber $number") }
        override fun placeCall(number: String) { log.add("placeCall $number") }
        override fun choosePeriod(isEvening: Boolean) { log.add("period $isEvening") }
    }

    private val actions = RecordingActions()
    private val mapper = BubbleOutputMapper(FakeTexts(), actions)

    private fun map(
        app: AppActionUi = AppActionUi.Idle,
        contact: ContactActionUi = ContactActionUi.Idle,
        time: TimeActionUi = TimeActionUi.Idle,
        system: SystemActionOutcome? = null,
        media: SystemActionOutcome? = null
    ) = mapper.map(app, contact, time, system, media)

    @Test
    fun nothingToShowGivesNone() {
        assertEquals(BubbleOutput.None, map())
    }

    @Test
    fun openedAppIsADoneMessage() {
        val out = map(app = AppActionUi.Opened("Camera")) as BubbleOutput.Message
        assertEquals("opened Camera", out.text)
        assertEquals(MessageKind.DONE, out.kind)
    }

    @Test
    fun callNeverHappensWithoutTheUserTappingCallNow() {
        val out = map(contact = ContactActionUi.ConfirmCall("Rahim", "0171")) as BubbleOutput.Decision
        assertTrue(actions.log.isEmpty())
        val option = out.options.single()
        assertEquals("callnow", option.label)
        option.action()
        assertEquals(listOf("placeCall 0171"), actions.log)
    }

    @Test
    fun confirmCallFallsBackToTheNumberWhenThereIsNoName() {
        val out = map(contact = ContactActionUi.ConfirmCall(null, "0171")) as BubbleOutput.Decision
        assertEquals("call 0171 0171", out.question)
    }

    @Test
    fun contactChoicesAreLimitedToFive() {
        val contacts = (1..9).map { Contact(it.toLong(), "C$it", listOf("0$it")) }
        val out = map(
            contact = ContactActionUi.ChooseContact(ContactPurpose.CALL, "c", contacts, null)
        ) as BubbleOutput.Decision
        assertEquals(5, out.options.size)
        out.options[2].action()
        assertEquals(listOf("pickContact C3"), actions.log)
    }

    @Test
    fun numberChoiceCallsPickNumber() {
        val contact = Contact(1, "Rahim", listOf("01", "02"))
        val out = map(contact = ContactActionUi.ChooseNumber(ContactPurpose.CALL, contact, null)) as BubbleOutput.Decision
        out.options[1].action()
        assertEquals(listOf("pickNumber 02"), actions.log)
    }

    @Test
    fun appConfirmAndChooseAndSuggest() {
        val reg = RegisteredApp("p.a", "Alpha")
        val confirm = map(app = AppActionUi.Confirm("alfa", reg)) as BubbleOutput.Decision
        confirm.options.single().action()
        val choose = map(app = AppActionUi.Choose("a", listOf(reg))) as BubbleOutput.Decision
        choose.options.single().action()
        val suggest = map(app = AppActionUi.Suggest("a", listOf(InstalledApp("p.b", "Beta")))) as BubbleOutput.Decision
        suggest.options.single().action()
        assertEquals(listOf("confirmApp", "chooseApp Alpha", "addAndOpen Beta"), actions.log)
    }

    @Test
    fun periodQuestionOffersMorningAndEvening() {
        val out = map(time = TimeActionUi.AskPeriod(7, 30, null, false)) as BubbleOutput.Decision
        assertEquals(2, out.options.size)
        out.options[0].action()
        out.options[1].action()
        assertEquals(listOf("period false", "period true"), actions.log)
    }

    @Test
    fun permissionProblemsSendTheUserToTheApp() {
        val out = map(system = SystemActionOutcome(OutcomeKind.NEEDS_PERMISSION, "allow")) as BubbleOutput.NeedsApp
        assertEquals("allow", out.text)
        assertTrue(map(contact = ContactActionUi.NeedsContactsPermission) is BubbleOutput.NeedsApp)
    }

    @Test
    fun outcomeKindsBecomeMessageKinds() {
        fun kind(k: OutcomeKind) = (map(system = SystemActionOutcome(k, "m")) as BubbleOutput.Message).kind
        assertEquals(MessageKind.DONE, kind(OutcomeKind.DONE))
        assertEquals(MessageKind.INFO, kind(OutcomeKind.GUIDED))
        assertEquals(MessageKind.INFO, kind(OutcomeKind.HINT))
        assertEquals(MessageKind.ERROR, kind(OutcomeKind.FAILED))
    }

    @Test
    fun contactWinsOverAppAndSystemOverMedia() {
        val both = map(
            app = AppActionUi.Opened("X"),
            contact = ContactActionUi.Done("called")
        ) as BubbleOutput.Message
        assertEquals("called", both.text)
        val sys = map(
            system = SystemActionOutcome(OutcomeKind.DONE, "sys"),
            media = SystemActionOutcome(OutcomeKind.DONE, "media")
        ) as BubbleOutput.Message
        assertEquals("sys", sys.text)
    }
}
