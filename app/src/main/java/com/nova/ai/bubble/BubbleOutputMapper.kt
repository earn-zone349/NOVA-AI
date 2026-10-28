package com.nova.ai.bubble

import com.nova.ai.apps.AppActionUi
import com.nova.ai.contacts.ContactActionUi
import com.nova.ai.system.OutcomeKind
import com.nova.ai.system.SystemActionOutcome
import com.nova.ai.time.TimeActionUi
import com.nova.ai.time.TimePlanner
import com.nova.ai.time.TimeText

/**
 * Turns what the five command controllers hold (the state their Home cards show) into one
 * [BubbleOutput] for the bubble. It only reads: no question is ever answered here, so a call
 * is never placed without the user tapping the call button.
 */
internal class BubbleOutputMapper(
    private val texts: BubbleTexts,
    private val actions: BubbleActions
) {

    /** The first controller that has something to show wins (call, app, time, system, media). */
    fun map(
        app: AppActionUi,
        contact: ContactActionUi,
        time: TimeActionUi,
        system: SystemActionOutcome?,
        media: SystemActionOutcome?
    ): BubbleOutput {
        val candidates: List<BubbleOutput> = listOf(
            fromContact(contact),
            fromApp(app),
            fromTime(time),
            fromOutcome(system),
            fromOutcome(media)
        )
        return candidates.firstOrNull { it !is BubbleOutput.None } ?: BubbleOutput.None
    }

    private fun fromContact(state: ContactActionUi): BubbleOutput = when (state) {
        is ContactActionUi.Idle -> BubbleOutput.None
        is ContactActionUi.NeedsContactsPermission ->
            BubbleOutput.NeedsApp(texts.needsContactsPermission())
        is ContactActionUi.ChooseContact -> BubbleOutput.Decision(
            source = state,
            question = texts.chooseContact(state.spoken),
            options = state.contacts.take(MAX_OPTIONS).map { contact ->
                BubbleOption(contact.name) { actions.pickContact(contact) }
            }
        )
        is ContactActionUi.ChooseNumber -> BubbleOutput.Decision(
            source = state,
            question = texts.chooseNumber(state.contact.name),
            options = state.contact.numbers.take(MAX_OPTIONS).map { number ->
                BubbleOption(number) { actions.pickNumber(number) }
            }
        )
        is ContactActionUi.ConfirmCall -> BubbleOutput.Decision(
            source = state,
            question = texts.confirmCall(state.name ?: state.number, state.number),
            options = listOf(BubbleOption(texts.callNow(), emphasis = true) { actions.placeCall(state.number) })
        )
        is ContactActionUi.Done -> BubbleOutput.Message(state.message, MessageKind.DONE)
        is ContactActionUi.Info -> BubbleOutput.Message(state.message, MessageKind.INFO)
        is ContactActionUi.NotFound ->
            BubbleOutput.Message(texts.contactNotFound(state.spoken), MessageKind.INFO)
        is ContactActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR)
    }

    private fun fromApp(state: AppActionUi): BubbleOutput = when (state) {
        is AppActionUi.Idle -> BubbleOutput.None
        is AppActionUi.Opened -> BubbleOutput.Message(texts.opened(state.appLabel), MessageKind.DONE)
        is AppActionUi.Confirm -> BubbleOutput.Decision(
            source = state,
            question = texts.confirmApp(state.app.label),
            options = listOf(BubbleOption(texts.yesOpen(), emphasis = true) { actions.confirmApp() })
        )
        is AppActionUi.Choose -> BubbleOutput.Decision(
            source = state,
            question = texts.chooseApp(state.spoken),
            options = state.apps.take(MAX_OPTIONS).map { app ->
                BubbleOption(app.label) { actions.chooseApp(app) }
            }
        )
        is AppActionUi.Suggest -> BubbleOutput.Decision(
            source = state,
            question = texts.suggestApp(state.spoken),
            options = state.apps.take(MAX_OPTIONS).map { app ->
                BubbleOption(app.label) { actions.addAndOpen(app) }
            }
        )
        is AppActionUi.NotFound -> BubbleOutput.Message(texts.appNotFound(state.spoken), MessageKind.INFO)
        is AppActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR)
    }

    private fun fromTime(state: TimeActionUi): BubbleOutput = when (state) {
        is TimeActionUi.Idle -> BubbleOutput.None
        is TimeActionUi.Done -> BubbleOutput.Message(state.message, MessageKind.DONE)
        is TimeActionUi.AskPeriod -> {
            val minuteText: String = state.minute.toString().padStart(2, '0')
            BubbleOutput.Decision(
                source = state,
                question = texts.askPeriod(TimeText.digits("${state.hour}:$minuteText")),
                options = listOf(false, true).map { evening ->
                    val label: String = TimeText.clock(TimePlanner.to24(state.hour, evening), state.minute)
                    BubbleOption(label, emphasis = true) { actions.choosePeriod(isEvening = evening) }
                }
            )
        }
        is TimeActionUi.NeedsDetail -> BubbleOutput.Message(state.message, MessageKind.INFO)
        is TimeActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR)
    }

    private fun fromOutcome(outcome: SystemActionOutcome?): BubbleOutput {
        if (outcome == null) return BubbleOutput.None
        return when (outcome.kind) {
            OutcomeKind.DONE -> BubbleOutput.Message(outcome.message, MessageKind.DONE)
            OutcomeKind.GUIDED -> BubbleOutput.Message(outcome.message, MessageKind.INFO, completed = true)
            OutcomeKind.HINT -> BubbleOutput.Message(outcome.message, MessageKind.INFO)
            OutcomeKind.NEEDS_PERMISSION -> BubbleOutput.NeedsApp(outcome.message)
            OutcomeKind.FAILED -> BubbleOutput.Message(outcome.message, MessageKind.ERROR)
        }
    }

    private companion object {
        // A small panel shows at most this many choices.
        const val MAX_OPTIONS: Int = 5
    }
}
