package com.nova.ai.time

import com.nova.ai.nlp.IntentEntity
import com.nova.ai.nlp.IntentMode

/** What is missing from a time command. */
enum class MissingDetail { TIMER_DURATION, ALARM_TIME, REMINDER_TIME }

/** What to do for a time command. */
sealed class TimePlan {
    /** Start a countdown timer. */
    data class Timer(val seconds: Int, val label: String?, val isReminder: Boolean) : TimePlan()

    /** Set an alarm at a clear time of day (hour in 0 to 23). */
    data class Alarm(
        val hour24: Int,
        val minute: Int,
        val label: String?,
        val isReminder: Boolean
    ) : TimePlan()

    /** The hour is 1 to 12 and nobody said morning or evening: ask the user. */
    data class AskPeriod(
        val hour: Int,
        val minute: Int,
        val label: String?,
        val isReminder: Boolean
    ) : TimePlan()

    /** The command did not say enough. */
    data class NeedsDetail(val missing: MissingDetail) : TimePlan()
}

/** Decides what to do for a SET_ALARM command. Pure logic, no Android needed. */
object TimePlanner {

    private const val MAX_HOUR: Int = 23
    private const val MAX_MINUTE: Int = 59
    private const val MAX_HOUR_12: Int = 12

    /** Builds a plan from the details found in the command. */
    fun plan(entities: Map<String, String>): TimePlan {
        val mode: String? = entities[IntentEntity.MODE]
        val isReminder: Boolean = mode == IntentMode.REMINDER
        val label: String? = entities[IntentEntity.BODY]?.trim()?.takeIf { it.isNotEmpty() }

        val seconds: Int? = entities[IntentEntity.DURATION_SECONDS]?.toIntOrNull()
        if (seconds != null && seconds > 0) return TimePlan.Timer(seconds, label, isReminder)

        if (mode == IntentMode.TIMER) return TimePlan.NeedsDetail(MissingDetail.TIMER_DURATION)

        val missing: MissingDetail =
            if (isReminder) MissingDetail.REMINDER_TIME else MissingDetail.ALARM_TIME

        val hour: Int = entities[IntentEntity.HOUR]?.toIntOrNull()
            ?: return TimePlan.NeedsDetail(missing)
        val minute: Int = entities[IntentEntity.MINUTE]?.toIntOrNull() ?: 0
        if (hour !in 0..MAX_HOUR || minute !in 0..MAX_MINUTE) return TimePlan.NeedsDetail(missing)

        val hour24: Int? = entities[IntentEntity.HOUR24]?.toIntOrNull()
        if (hour24 != null && hour24 in 0..MAX_HOUR) {
            return TimePlan.Alarm(hour24, minute, label, isReminder)
        }
        return if (hour in 1..MAX_HOUR_12) {
            TimePlan.AskPeriod(hour, minute, label, isReminder)
        } else {
            TimePlan.Alarm(hour, minute, label, isReminder)
        }
    }

    /** Converts a 12-hour clock hour (1 to 12) and morning or evening to a 0 to 23 hour. */
    fun to24(hour12: Int, isEvening: Boolean): Int = when {
        isEvening && hour12 == MAX_HOUR_12 -> MAX_HOUR_12
        isEvening -> hour12 + MAX_HOUR_12
        hour12 == MAX_HOUR_12 -> 0
        else -> hour12
    }
}
