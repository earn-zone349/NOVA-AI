#!/usr/bin/env bash
# NOVA AI - Phase 15 setup script: alarms, timers and reminders (with calendar option).
# Additive: new time package; a few additive lines in HomeScreen and the manifest.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
MANIFEST="app/src/main/AndroidManifest.xml"
HOME_FILE="$BASE/ui/screens/HomeScreen.kt"

for required in \
  "$BASE/contacts/ContactCommandController.kt" \
  "$BASE/nlp/IntentParser.kt" \
  "$HOME_FILE" \
  "$MANIFEST" \
  "app/src/main/res/values/strings_p11.xml"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after P1 to P14 are installed." >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
mkdir -p "$BASE/time"

# ---------- A. Manifest: permission to set alarms and timers (normal permission) ----------
if ! grep -q "com.android.alarm.permission.SET_ALARM" "$MANIFEST"; then
  cat > "$TMP_DIR/manifest_add.txt" <<'EOF'
    <uses-permission android:name="com.android.alarm.permission.SET_ALARM" />
EOF
  sed -i "/android.permission.RECORD_AUDIO/r $TMP_DIR/manifest_add.txt" "$MANIFEST"
fi
grep -q "com.android.alarm.permission.SET_ALARM" "$MANIFEST" || { echo "ERROR: manifest edit failed" >&2; exit 1; }

# ---------- B. Update a text that said "coming later" ----------
sed -i 's|<string name="intent_note">.*</string>|<string name="intent_note">বোঝা হয়েছে।</string>|' app/src/main/res/values/strings_p11.xml

# ---------- C. New strings file ----------
cat > app/src/main/res/values/strings_p15.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="time_title">অ্যালার্ম ও টাইমার</string>
    <string name="time_default_reminder_label">রিমাইন্ডার</string>

    <string name="time_alarm_set">অ্যালার্ম সেট করেছি: %1$s।</string>
    <string name="time_alarm_set_label">অ্যালার্ম সেট করেছি: %1$s। নাম: %2$s</string>
    <string name="time_reminder_set">রিমাইন্ডার সেট করেছি: %1$s। বার্তা: %2$s</string>
    <string name="time_timer_set">টাইমার চালু করেছি: %1$s।</string>
    <string name="time_timer_set_label">টাইমার চালু করেছি: %1$s। নাম: %2$s</string>
    <string name="time_reminder_timer_set">%1$s পরে মনে করানোর টাইমার চালু করেছি। বার্তা: %2$s</string>

    <string name="time_ask_period">সময় %1$s। এটা সকালের, নাকি বিকাল বা রাতের?</string>
    <string name="time_need_timer">কত সময়ের টাইমার? যেমন: ৫ মিনিটের টাইমার দাও।</string>
    <string name="time_need_alarm">কয়টায় অ্যালার্ম দেব? যেমন: সকাল ৭টায় অ্যালার্ম দাও।</string>
    <string name="time_need_reminder">কখন মনে করাব? যেমন: বিকাল ৫টায় ওষুধ খাওয়ার রিমাইন্ডার দাও।</string>

    <string name="time_open_clock">ক্লক অ্যাপে দেখো</string>
    <string name="time_add_calendar">ক্যালেন্ডারেও যোগ করো</string>
    <string name="time_failed">সমস্যা: %1$s</string>
</resources>
EOF

# ---------- 1. TimeText.kt ----------
cat > "$BASE/time/TimeText.kt" <<'EOF'
package com.nova.ai.time

/** Writes times and durations in Bangla, with Bangla digits. Pure logic. */
object TimeText {

    private val BANGLA_DIGITS: CharArray =
        charArrayOf('০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯')

    private const val SECONDS_PER_MINUTE: Int = 60
    private const val SECONDS_PER_HOUR: Int = 3600

    /** Turns digits 0 to 9 in [text] into Bangla digits. */
    fun digits(text: String): String =
        text.map { character ->
            if (character in '0'..'9') BANGLA_DIGITS[character - '0'] else character
        }.joinToString("")

    /** For example 7 and 0 give "সকাল ৭:০০"; 17 and 30 give "বিকাল ৫:৩০". */
    fun clock(hour24: Int, minute: Int): String {
        val hour12: Int = if (hour24 % 12 == 0) 12 else hour24 % 12
        val minuteText: String = minute.toString().padStart(2, '0')
        return "${periodWord(hour24)} ${digits("$hour12:$minuteText")}"
    }

    /** For example 300 gives "৫ মিনিট"; 5400 gives "১ ঘণ্টা ৩০ মিনিট". */
    fun duration(totalSeconds: Int): String {
        val hours: Int = totalSeconds / SECONDS_PER_HOUR
        val minutes: Int = (totalSeconds % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE
        val seconds: Int = totalSeconds % SECONDS_PER_MINUTE

        val parts = ArrayList<String>()
        if (hours > 0) parts.add("${digits(hours.toString())} ঘণ্টা")
        if (minutes > 0) parts.add("${digits(minutes.toString())} মিনিট")
        if (seconds > 0) parts.add("${digits(seconds.toString())} সেকেন্ড")
        return parts.joinToString(" ")
    }

    private fun periodWord(hour24: Int): String = when (hour24) {
        in 4..5 -> "ভোর"
        in 6..11 -> "সকাল"
        in 12..14 -> "দুপুর"
        in 15..17 -> "বিকাল"
        in 18..19 -> "সন্ধ্যা"
        else -> "রাত"
    }
}
EOF

# ---------- 2. TimePlanner.kt ----------
cat > "$BASE/time/TimePlanner.kt" <<'EOF'
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
EOF

# ---------- 3. ClockActions.kt ----------
cat > "$BASE/time/ClockActions.kt" <<'EOF'
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
EOF

# ---------- 4. TimeCommandController.kt ----------
cat > "$BASE/time/TimeCommandController.kt" <<'EOF'
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
EOF

# ---------- 5. TimeActionCard.kt ----------
cat > "$BASE/ui/components/TimeActionCard.kt" <<'EOF'
package com.nova.ai.ui.components

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
import com.nova.ai.time.TimeActionUi
import com.nova.ai.time.TimeCommandController
import com.nova.ai.time.TimePlanner
import com.nova.ai.time.TimeText

/**
 * Shows the result of an alarm, timer or reminder command on the Home screen,
 * or asks "morning or evening?" when the time is unclear.
 * Shows nothing while there is nothing to report.
 */
@Composable
fun TimeActionCard(
    controller: TimeCommandController,
    modifier: Modifier = Modifier
) {
    val current: TimeActionUi = controller.state
    if (current is TimeActionUi.Idle) return

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.time_title),
                style = MaterialTheme.typography.titleMedium
            )

            when (current) {
                is TimeActionUi.Idle -> Unit

                is TimeActionUi.Done -> {
                    Text("✅ ${current.message}")
                    OutlinedButton(
                        onClick = { controller.openClockApp() },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.time_open_clock))
                    }
                    if (current.calendar != null) {
                        OutlinedButton(
                            onClick = { controller.addToCalendar() },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(stringResource(R.string.time_add_calendar))
                        }
                    }
                }

                is TimeActionUi.AskPeriod -> {
                    val minuteText: String = current.minute.toString().padStart(2, '0')
                    Text(
                        stringResource(
                            R.string.time_ask_period,
                            TimeText.digits("${current.hour}:$minuteText")
                        )
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = { controller.choosePeriod(isEvening = false) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(TimeText.clock(TimePlanner.to24(current.hour, false), current.minute))
                        }
                        Button(
                            onClick = { controller.choosePeriod(isEvening = true) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(TimeText.clock(TimePlanner.to24(current.hour, true), current.minute))
                        }
                    }
                }

                is TimeActionUi.NeedsDetail -> Text("💡 ${current.message}")

                is TimeActionUi.Failed ->
                    Text(stringResource(R.string.time_failed, current.message))
            }

            TextButton(onClick = { controller.dismiss() }) {
                Text(stringResource(R.string.action_dismiss))
            }
        }
    }
}
EOF

# ---------- D. HomeScreen.kt: a few additive lines (idempotent) ----------
if ! grep -q "TimeCommandController" "$HOME_FILE"; then
  grep -q '^import com.nova.ai.contacts.ContactCommandController$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (import) not found" >&2; exit 1; }
  grep -q 'val contactController: ContactCommandController = remember' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (controller) not found" >&2; exit 1; }
  grep -q 'contactController.handleCommand(command.rawText)' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (voice command) not found" >&2; exit 1; }
  grep -q 'contactController.handleCommand(commandText)' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (send button) not found" >&2; exit 1; }
  grep -q '^        ContactActionCard(controller = contactController)$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (card) not found" >&2; exit 1; }

  cat > "$TMP_DIR/home_imports.txt" <<'EOF'
import com.nova.ai.time.TimeCommandController
import com.nova.ai.ui.components.TimeActionCard
EOF
  cat > "$TMP_DIR/home_controller.txt" <<'EOF'

    // Sets alarms, timers and reminders in the phone's clock app.
    val timeController: TimeCommandController = remember { TimeCommandController(context) }
EOF
  cat > "$TMP_DIR/home_voice.txt" <<'EOF'
                    timeController.handleCommand(command.rawText)
EOF
  cat > "$TMP_DIR/home_send.txt" <<'EOF'
                    timeController.handleCommand(commandText)
EOF
  cat > "$TMP_DIR/home_card.txt" <<'EOF'

        TimeActionCard(controller = timeController)
EOF

  sed -i "/^import com.nova.ai.contacts.ContactCommandController$/r $TMP_DIR/home_imports.txt" "$HOME_FILE"
  sed -i "/val contactController: ContactCommandController = remember/r $TMP_DIR/home_controller.txt" "$HOME_FILE"
  sed -i "/contactController.handleCommand(command.rawText)/r $TMP_DIR/home_voice.txt" "$HOME_FILE"
  sed -i "/contactController.handleCommand(commandText)/r $TMP_DIR/home_send.txt" "$HOME_FILE"
  sed -i "/^        ContactActionCard(controller = contactController)$/r $TMP_DIR/home_card.txt" "$HOME_FILE"
fi
grep -q "val timeController: TimeCommandController" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (controller)" >&2; exit 1; }
grep -q "timeController.handleCommand(command.rawText)" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (voice)" >&2; exit 1; }
grep -q "timeController.handleCommand(commandText)" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (send)" >&2; exit 1; }
grep -q "TimeActionCard(controller = timeController)" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (card)" >&2; exit 1; }

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "P15: alarms, timers and reminders through the clock app"
git push

echo "P15 files created and pushed."
