package com.nova.ai.time

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.R
import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.voice.LanguageDetector
import java.util.Calendar

/** Which list of the clock app to open for "show me". */
enum class ShowTarget { ALARMS, TIMERS }

/** An event the user can add to the calendar. */
data class CalendarDraft(val title: String, val beginMillis: Long)

/** What the Home screen shows about the last alarm, timer or reminder command. */
sealed class TimeActionUi {
    object Idle : TimeActionUi()
    data class Done(
        val message: String,
        val showTarget: ShowTarget,
        val calendar: CalendarDraft?
    ) : TimeActionUi()
    data class AskPeriod(
        val hour: Int,
        val minute: Int,
        val label: String?,
        val isReminder: Boolean
    ) : TimeActionUi()
    data class NeedsDetail(val message: String) : TimeActionUi()
    data class Failed(val message: String) : TimeActionUi()
}

/**
 * Turns alarm, timer and reminder commands into real clock entries.
 * Use from the main thread.
 */
class TimeCommandController(context: Context) {

    private val appContext: Context = context.applicationContext
    private val actions = ClockActions(appContext)
    private val brain = RuleBasedBrain()

    var state: TimeActionUi by mutableStateOf<TimeActionUi>(TimeActionUi.Idle)
        private set

    /** Looks at [text]; if it asks for an alarm, timer or reminder, sets it. */
    fun handleCommand(text: String) {
        val intent: NovaIntent? = analyze(text)
        if (intent == null || intent.type != IntentType.SET_ALARM) {
            state = TimeActionUi.Idle
            return
        }
        apply(TimePlanner.plan(intent.entities))
    }

    /** The user answered "morning or evening?". */
    fun choosePeriod(isEvening: Boolean) {
        val current: TimeActionUi.AskPeriod = state as? TimeActionUi.AskPeriod ?: return
        val hour24: Int = TimePlanner.to24(current.hour, isEvening)
        apply(TimePlan.Alarm(hour24, current.minute, current.label, current.isReminder))
    }

    /** Opens the clock app's list so the user can check the result. */
    fun openClockApp() {
        val current: TimeActionUi.Done = state as? TimeActionUi.Done ?: return
        val result: NovaResult<Unit> = when (current.showTarget) {
            ShowTarget.ALARMS -> actions.showAlarms()
            ShowTarget.TIMERS -> actions.showTimers()
        }
        if (result is NovaResult.Failure) state = TimeActionUi.Failed(result.error.message)
    }

    /** Opens the calendar with the reminder filled in. */
    fun addToCalendar() {
        val current: TimeActionUi.Done = state as? TimeActionUi.Done ?: return
        val draft: CalendarDraft = current.calendar ?: return
        val result: NovaResult<Unit> =
            actions.insertCalendarEvent(draft.title, draft.beginMillis, EVENT_LENGTH_MS)
        if (result is NovaResult.Failure) state = TimeActionUi.Failed(result.error.message)
    }

    /** Hides the card. */
    fun dismiss() {
        state = TimeActionUi.Idle
    }

    private fun apply(plan: TimePlan) {
        when (plan) {
            is TimePlan.Timer -> startTimer(plan)
            is TimePlan.Alarm -> setAlarm(plan)
            is TimePlan.AskPeriod ->
                state = TimeActionUi.AskPeriod(plan.hour, plan.minute, plan.label, plan.isReminder)
            is TimePlan.NeedsDetail -> state = TimeActionUi.NeedsDetail(
                text(
                    when (plan.missing) {
                        MissingDetail.TIMER_DURATION -> R.string.time_need_timer
                        MissingDetail.ALARM_TIME -> R.string.time_need_alarm
                        MissingDetail.REMINDER_TIME -> R.string.time_need_reminder
                    }
                )
            )
        }
    }

    private fun startTimer(plan: TimePlan.Timer) {
        val label: String? = plan.label
            ?: if (plan.isReminder) text(R.string.time_default_reminder_label) else null
        val durationText: String = TimeText.duration(plan.seconds)

        when (val result: NovaResult<Unit> = actions.setTimer(plan.seconds, label)) {
            is NovaResult.Failure -> state = TimeActionUi.Failed(result.error.message)
            is NovaResult.Success -> {
                val message: String = when {
                    plan.isReminder && label != null ->
                        text(R.string.time_reminder_timer_set, durationText, label)
                    label != null -> text(R.string.time_timer_set_label, durationText, label)
                    else -> text(R.string.time_timer_set, durationText)
                }
                val calendar: CalendarDraft? =
                    if (plan.isReminder && label != null) {
                        CalendarDraft(label, System.currentTimeMillis() + plan.seconds * MILLIS_PER_SECOND)
                    } else {
                        null
                    }
                state = TimeActionUi.Done(message, ShowTarget.TIMERS, calendar)
            }
        }
    }

    private fun setAlarm(plan: TimePlan.Alarm) {
        val label: String? = plan.label
            ?: if (plan.isReminder) text(R.string.time_default_reminder_label) else null
        val clockText: String = TimeText.clock(plan.hour24, plan.minute)

        when (val result: NovaResult<Unit> = actions.setAlarm(plan.hour24, plan.minute, label)) {
            is NovaResult.Failure -> state = TimeActionUi.Failed(result.error.message)
            is NovaResult.Success -> {
                val message: String = when {
                    plan.isReminder && label != null -> text(R.string.time_reminder_set, clockText, label)
                    label != null -> text(R.string.time_alarm_set_label, clockText, label)
                    else -> text(R.string.time_alarm_set, clockText)
                }
                val calendar: CalendarDraft? =
                    if (plan.isReminder && label != null) {
                        CalendarDraft(label, nextOccurrenceMillis(plan.hour24, plan.minute))
                    } else {
                        null
                    }
                state = TimeActionUi.Done(message, ShowTarget.ALARMS, calendar)
            }
        }
    }

    /** The next time the clock shows [hour24]:[minute] (today, or tomorrow if it has passed). */
    private fun nextOccurrenceMillis(hour24: Int, minute: Int): Long {
        val moment: Calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour24)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (moment.timeInMillis <= System.currentTimeMillis()) moment.add(Calendar.DAY_OF_YEAR, 1)
        return moment.timeInMillis
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
        const val MILLIS_PER_SECOND: Long = 1000L
        const val EVENT_LENGTH_MS: Long = 30L * 60L * 1000L
    }
}
