package com.nova.ai.time

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.provider.AlarmClock
import android.provider.CalendarContract
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * Sets alarms and timers in the phone's own clock app, and opens the calendar
 * with an event ready. The clock app does the ringing, so alarms work even
 * when NOVA is closed. Alarm and event texts are never logged.
 */
class ClockActions(context: Context) {

    private val appContext: Context = context.applicationContext

    /** Sets an alarm for the next [hour24]:[minute]. */
    fun setAlarm(hour24: Int, minute: Int, label: String?): NovaResult<Unit> {
        val intent = Intent(AlarmClock.ACTION_SET_ALARM)
            .putExtra(AlarmClock.EXTRA_HOUR, hour24)
            .putExtra(AlarmClock.EXTRA_MINUTES, minute)
            .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
        if (!label.isNullOrBlank()) intent.putExtra(AlarmClock.EXTRA_MESSAGE, label.take(MAX_LABEL_LENGTH))
        return launch(intent)
    }

    /** Starts a countdown timer of [seconds] (1 second to 24 hours). */
    fun setTimer(seconds: Int, label: String?): NovaResult<Unit> {
        if (seconds !in 1..MAX_TIMER_SECONDS) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, "টাইমার সর্বোচ্চ ২৪ ঘণ্টার হতে পারে।")
        }
        val intent = Intent(AlarmClock.ACTION_SET_TIMER)
            .putExtra(AlarmClock.EXTRA_LENGTH, seconds)
            .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
        if (!label.isNullOrBlank()) intent.putExtra(AlarmClock.EXTRA_MESSAGE, label.take(MAX_LABEL_LENGTH))
        return launch(intent)
    }

    /** Opens the clock app's alarm list. */
    fun showAlarms(): NovaResult<Unit> = launch(Intent(AlarmClock.ACTION_SHOW_ALARMS))

    /** Opens the clock app's timer list. */
    fun showTimers(): NovaResult<Unit> = launch(Intent(AlarmClock.ACTION_SHOW_TIMERS))

    /** Opens the calendar with a new event filled in; the user taps save. */
    fun insertCalendarEvent(title: String, beginMillis: Long, durationMillis: Long): NovaResult<Unit> {
        val intent = Intent(Intent.ACTION_INSERT)
            .setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.Events.TITLE, title.take(MAX_LABEL_LENGTH))
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, beginMillis)
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, beginMillis + durationMillis)
        return launch(intent)
    }

    private fun launch(intent: Intent): NovaResult<Unit> {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appContext.startActivity(intent)
            NovaResult.Success(Unit)
        } catch (e: ActivityNotFoundException) {
            NovaLogger.e(TAG, "No clock or calendar app found", e)
            NovaResult.failure(ErrorCode.NOT_FOUND, "ফোনে এই কাজের জন্য ক্লক বা ক্যালেন্ডার অ্যাপ পাওয়া যায়নি।", e)
        } catch (e: SecurityException) {
            NovaLogger.w(TAG, "Action refused by the phone", e)
            NovaResult.failure(ErrorCode.PERMISSION_DENIED, "ফোন অ্যালার্ম সেট করার অনুমতি দিচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Clock action failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "কাজটি করতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "ClockActions"
        const val MAX_LABEL_LENGTH: Int = 60
        const val MAX_TIMER_SECONDS: Int = 86_400
    }
}
