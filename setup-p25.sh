#!/usr/bin/env bash
# NOVA AI - Phase 25 setup script: task control and task history.
# Additive: say "থামো" (or pause / resume / cancel / retry / status) while a task runs; a task that
# was stopped, failed or cancelled can be run again from where it stopped; every finished task is
# kept in a history (existing Room "tasks" table, no database version change) shown on the Automation
# screen. The P23/P24 task files are rewritten with every earlier feature kept. Requires P24.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
TEST="app/src/test/java/com/nova/ai"
RES="app/src/main/res/values"
HOME_FILE="$BASE/ui/screens/HomeScreen.kt"
AUTO_FILE="$BASE/ui/screens/AutomationScreen.kt"
SERVICE_FILE="$BASE/bubble/NovaBubbleService.kt"
DAO_FILE="$BASE/data/dao/TaskDao.kt"

fail() { echo "ERROR: $*" >&2; exit 1; }

TMP_FILES=()
cleanup() { [ ${#TMP_FILES[@]} -eq 0 ] || rm -f "${TMP_FILES[@]}"; }
trap cleanup EXIT

# Number of lines that equal $2 exactly.
count_line() { grep -c -x -F -- "$2" "$1" || true; }

# Replaces the single line that equals $2 with $3. Skips when $4 is already in the file.
replace_line() {
  local file="$1" anchor="$2" text="$3" marker="$4" tmp
  if grep -q -F -- "$marker" "$file"; then return 0; fi
  [ "$(count_line "$file" "$anchor")" = "1" ] || fail "anchor not found exactly once in $file: $anchor"
  tmp="$(mktemp)"; TMP_FILES+=("$tmp")
  A="$anchor" T="$text" awk '$0 == ENVIRON["A"] { print ENVIRON["T"]; next } { print }' "$file" > "$tmp"
  cat "$tmp" > "$file"
}

# Adds $3 after the single line that equals $2. Skips when $4 is already in the file.
insert_after() {
  local file="$1" anchor="$2" text="$3" marker="$4" tmp
  if grep -q -F -- "$marker" "$file"; then return 0; fi
  [ "$(count_line "$file" "$anchor")" = "1" ] || fail "anchor not found exactly once in $file: $anchor"
  tmp="$(mktemp)"; TMP_FILES+=("$tmp")
  A="$anchor" T="$text" awk '{ print } $0 == ENVIRON["A"] { print ENVIRON["T"] }' "$file" > "$tmp"
  cat "$tmp" > "$file"
}

# Adds $3 before the single line that equals $2. Skips when $4 is already in the file.
insert_before() {
  local file="$1" anchor="$2" text="$3" marker="$4" tmp
  if grep -q -F -- "$marker" "$file"; then return 0; fi
  [ "$(count_line "$file" "$anchor")" = "1" ] || fail "anchor not found exactly once in $file: $anchor"
  tmp="$(mktemp)"; TMP_FILES+=("$tmp")
  A="$anchor" T="$text" awk '$0 == ENVIRON["A"] { print ENVIRON["T"] } { print }' "$file" > "$tmp"
  cat "$tmp" > "$file"
}

# Stops early unless the anchor is there once (or the marker shows the edit was made before).
need() {
  local file="$1" anchor="$2" marker="$3"
  grep -q -F -- "$marker" "$file" && return 0
  [ "$(count_line "$file" "$anchor")" = "1" ] || fail "anchor missing in $file: $anchor"
}

for required in "$BASE/tasks/TaskQueue.kt" "$BASE/tasks/TaskHub.kt" "$BASE/tasks/TaskModels.kt" \
  "$BASE/tasks/TaskMessages.kt" "$BASE/ui/components/TaskQueueCard.kt" "$HOME_FILE" "$AUTO_FILE" "$SERVICE_FILE" "$DAO_FILE"; do
  [ -f "$required" ] || fail "$required not found. Run from the repo root after P24 is installed."
done
grep -q "RecoveryAction" "$BASE/tasks/TaskQueue.kt" || fail "P24 is not installed (TaskQueue.kt has no recovery). Run setup-p24.sh first."

# Check every edit point first, so a wrong repo is stopped before anything is written.
need "$DAO_FILE" '    @Query("DELETE FROM tasks")' "fun trimTo"
need "$HOME_FILE" "                    if (TaskHub.submitIfMultiStep(context, command.rawText)) return" "TaskHub.handleControl(context, command.rawText)"
need "$HOME_FILE" "                    if (TaskHub.submitIfMultiStep(context, commandText)) return@Button" "TaskHub.handleControl(context, commandText)"
need "$HOME_FILE" "                            statusOverride = context.getString(R.string.home_status_ended_phrase)" "TaskHub.pauseIfRunning(context)"
need "$SERVICE_FILE" "            if (!TaskHub.submitIfMultiStep(applicationContext, command.rawText)) {" "TaskHub.handleControl(applicationContext"
need "$SERVICE_FILE" "                is ConversationEnd.StopPhrase -> overlay.hidePanel()" "TaskHub.pauseIfRunning(applicationContext)"
need "$SERVICE_FILE" "                overlay.showStatus(notice, MessageKind.ERROR, STATUS_MS)" "snapshot.noticeIsError"
need "$SERVICE_FILE" "        buttons.add(PanelButton(getString(R.string.bub_menu_close)) { stopSelf() })" "bub_task_pause)) { TaskHub.pause() }"
need "$AUTO_FILE" "        TaskQueueCard()" "TaskHistoryCard()"

mkdir -p "$BASE/tasks" "$BASE/ui/components" "$TEST/tasks" "$RES"

# ---------- TaskModels.kt ----------
cat > "$BASE/tasks/TaskModels.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.core.TaskStatus

/** Where one step of a task is right now. */
enum class StepState { PENDING, RUNNING, RETRYING, WAITING_USER, DONE, FAILED, SKIPPED, CANCELLED }

/** How a step is carried out. */
enum class StepKind {
    /** Run the spoken command through the command controllers. */
    COMMAND,

    /** Open a web page (used as an alternative path, for example when an app is not installed). */
    OPEN_URL
}

/**
 * Why a step failed, which decides what the queue does next.
 * [RETRYABLE]: the phone reported an error, so nothing happened and trying again is safe.
 * [UNCERTAIN]: no answer in time; the step may or may not have happened, so it is repeated only if repeating is harmless.
 * [PERMANENT]: trying again cannot help (not found, not understood, a permission is missing).
 */
enum class FailureKind { RETRYABLE, UNCERTAIN, PERMANENT }

/**
 * One step of a task: a single spoken command (for example "ভলিউম বাড়াও"). [intentType] is what
 * the rule-based brain understood, so the queue can wait long enough after steps that open an app.
 */
data class PlannedStep(
    val id: String,
    val title: String,
    val command: String,
    val intentType: IntentType,
    /** The details the brain found (app, query, action ...). The retry and alternative rules read them. */
    val entities: Map<String, String> = emptyMap(),
    val kind: StepKind = StepKind.COMMAND,
    /** The page to open when [kind] is [StepKind.OPEN_URL]. */
    val url: String? = null,
    /** A line for the user when this step is an alternative path. */
    val note: String? = null,
    /** True for a step made by the fallback rules. It is tried once and never repeated. */
    val isAlternative: Boolean = false
)

/** A task that is ready to run: its ordered steps, found before anything was started. */
data class TaskDraft(
    val id: String,
    val title: String,
    val steps: List<PlannedStep>
)

/** What happened when a step ran. */
sealed class StepResult {
    /** The step finished. [message] is shown to the user. */
    data class Done(val message: String) : StepResult()

    /** The step could not be done. [kind] tells whether trying again can help. */
    data class Failed(val message: String, val kind: FailureKind = FailureKind.PERMANENT) : StepResult()

    /** The step needs the user to pick one of the [options] (by its position in the list). */
    data class NeedsUser(val question: String, val options: List<String>) : StepResult()
}

/** The state of one step, for the screens. */
data class StepSnapshot(
    val id: String,
    val title: String,
    val state: StepState,
    val message: String?,
    /** Which try this is (1 for the first) and how many tries are allowed. */
    val attempt: Int = 1,
    val maxAttempts: Int = 1
)

/** A question the running task waits on. */
data class PendingQuestion(val text: String, val options: List<String>)

/** The state of one task, for the screens. */
data class TaskSnapshot(
    val id: String,
    val title: String,
    val status: TaskStatus,
    val steps: List<StepSnapshot>,
    val question: PendingQuestion?,
    val summary: String?
) {
    /** How many steps are done. */
    val doneCount: Int get() = steps.count { it.state == StepState.DONE }

    /** The step that is running (or waiting for the user), if any. */
    val activeIndex: Int get() = steps.indexOfFirst {
        it.state == StepState.RUNNING || it.state == StepState.RETRYING || it.state == StepState.WAITING_USER
    }

    /** True while the task still has work to do. */
    val isOpen: Boolean get() = status == TaskStatus.RUNNING || status == TaskStatus.PAUSED || status == TaskStatus.PENDING
}

/**
 * The whole queue, for the screens: the task in front, the titles of the tasks waiting, and a notice.
 * [noticeSeq] grows with every new notice, so the same words said twice are still shown twice.
 */
data class QueueSnapshot(
    val current: TaskSnapshot?,
    val waiting: List<String>,
    val notice: String? = null,
    val noticeSeq: Int = 0,
    /** True if the notice is a problem; false if it is plain information (for example the progress). */
    val noticeIsError: Boolean = true
) {
    companion object {
        /** An empty queue. */
        val EMPTY: QueueSnapshot = QueueSnapshot(current = null, waiting = emptyList(), notice = null)
    }
}
EOF

# ---------- TaskMessages.kt ----------
cat > "$BASE/tasks/TaskMessages.kt" <<'EOF'
package com.nova.ai.tasks

/** Texts the planner and the queue show to the user (Bangla). Kept in one place. */
object TaskMessages {

    const val MSG_EMPTY: String = "কী করতে হবে বুঝতে পারিনি। কমান্ড খালি।"
    const val MSG_QUEUE_FULL: String = "কাজের লাইন ভর্তি। আগের কাজ শেষ হলে আবার বলুন।"
    const val MSG_STEP_TIMEOUT: String = "ধাপটি সময়মতো শেষ হয়নি।"
    const val MSG_QUESTION_TIMEOUT: String = "উত্তর পাওয়া যায়নি, তাই কাজ বাতিল করেছি।"
    const val MSG_CANCELLED: String = "কাজ বাতিল করা হয়েছে।"
    const val MSG_START_FAILED: String = "ধাপটি চালু করা যায়নি।"
    const val MSG_NOT_FOUND: String = "এই কাজটি এখন চলছে না।"
    const val MSG_NO_QUESTION: String = "এখন কোনো প্রশ্ন নেই।"
    const val MSG_BAD_CHOICE: String = "এই বিকল্পটি নেই।"
    const val MSG_CANNOT_PAUSE: String = "এই কাজ এখন থামানো যাবে না।"
    const val MSG_CANNOT_RESUME: String = "এই কাজ থামানো নেই।"

    const val MSG_PAUSED: String = "কাজ থামানো হয়েছে। চলতি ধাপ শেষ হলে এখানেই থামবে।"
    const val MSG_ALREADY_PAUSED: String = "কাজ আগে থেকেই থামানো আছে।"
    const val MSG_RESUMED: String = "কাজ আবার চলছে।"
    const val MSG_NOTHING_TO_RERUN: String = "আবার চালানোর মতো ব্যর্থ বা বাতিল কাজ নেই।"
    const val MSG_NOTHING_LEFT: String = "এই কাজের সব ধাপ আগেই শেষ হয়েছে।"
    const val MSG_NO_TASK: String = "এখন কোনো কাজ নেই।"
    const val MSG_HISTORY_CLEARED: String = "কাজের ইতিহাস মোছা হয়েছে।"
    const val MSG_HISTORY_NOT_FOUND: String = "এই কাজটি ইতিহাসে পাওয়া যায়নি।"

    /** The rerun of a task has the same title with this word in front. */
    fun rerunTitle(title: String): String = "আবার: $title"

    /** A rerun was put in the queue. */
    fun rerunStarted(count: Int): String = "বাকি ${count}টি ধাপ আবার চালু করছি।"

    /** The answer to "what is the progress?" while a task runs. */
    fun statusRunning(done: Int, total: Int, current: String): String =
        "${done}/${total} ধাপ শেষ। এখন: $current।"

    /** The answer to "what is the progress?" while a task is paused. */
    fun statusPaused(done: Int, total: Int): String = "কাজ থামানো আছে। ${done}/${total} ধাপ শেষ।"

    /** The answer to "what is the progress?" while a task waits for the user. */
    fun statusQuestion(done: Int, total: Int): String = "${done}/${total} ধাপ শেষ। আপনার উত্তরের অপেক্ষায় আছি।"

    const val OPTION_RETRY: String = "আবার চেষ্টা করো"
    const val OPTION_SKIP: String = "এই ধাপ বাদ দিয়ে এগোও"
    const val OPTION_CANCEL: String = "কাজ বাতিল করো"

    /** The next try of a step is about to start. */
    fun retrying(attempt: Int, max: Int, reason: String): String = "$reason (আবার চেষ্টা $attempt/$max)"

    /** The step was done another way. */
    fun alternativeDone(note: String): String = note

    /** Asks what to do after a step failed for good. */
    fun recoveryQuestion(position: Int, total: Int, reason: String): String =
        "${position}/${total} ধাপ হয়নি: $reason। এখন কী করবো?"

    /** The task ended, but some steps were skipped on the user's choice. */
    fun doneWithSkips(done: Int, skipped: Int): String = "${done}টি ধাপ শেষ, ${skipped}টি বাদ দেওয়া হয়েছে।"

    /** The command has more steps than NOVA runs in one task. */
    fun tooManySteps(max: Int): String = "একবারে সর্বোচ্চ ${max}টি ধাপ করা যায়। কাজ ছোট করে বলুন।"

    /** One part of the command was not understood. Nothing was started. */
    fun unknownPart(part: String): String = "“$part” অংশটা বুঝতে পারিনি। কিছুই শুরু করিনি।"

    /** All steps finished. */
    fun allDone(count: Int): String = "সব ${count}টি ধাপ শেষ।"

    /** A step failed, so the task stopped there. */
    fun stoppedAt(position: Int, total: Int, reason: String, attempts: Int = 1, triedAlternative: Boolean = false): String {
        val tries: String = if (attempts > 1) " (${attempts} বার চেষ্টা করেছি)" else ""
        val alt: String = if (triedAlternative) " বিকল্প পথেও হয়নি।" else ""
        return "${position}/${total} ধাপে আটকে গেছি: $reason$tries$alt"
    }
}
EOF

# ---------- TaskHistory.kt ----------
cat > "$BASE/tasks/TaskHistory.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.core.TaskStatus

/** One step of a finished task, as kept in the history. */
data class HistoryStep(
    val title: String,
    val command: String,
    val intentType: IntentType,
    val entities: Map<String, String>,
    val state: StepState,
    val message: String?
)

/** A finished task, as kept in the history on the phone. */
data class HistoryItem(
    val id: String,
    val title: String,
    val status: TaskStatus,
    val summary: String?,
    val finishedAtMs: Long,
    val steps: List<HistoryStep>
) {
    /** True if the user can run the unfinished steps again. */
    val canRerun: Boolean get() = status == TaskStatus.FAILED || status == TaskStatus.CANCELLED

    /**
     * A new task made of the steps that did not finish (failed, skipped or cancelled), in order.
     * Null if every step is done or the steps were not kept.
     */
    fun toRerunDraft(newId: String): TaskDraft? {
        val left: List<HistoryStep> = steps.filter { it.state != StepState.DONE }
        if (left.isEmpty()) return null
        return TaskDraft(
            id = newId,
            title = TaskMessages.rerunTitle(title),
            steps = left.mapIndexed { index, step ->
                PlannedStep(
                    id = "s${index + 1}",
                    title = step.title,
                    command = step.command,
                    intentType = step.intentType,
                    entities = step.entities
                )
            }
        )
    }

    companion object {
        /** Builds the history record of a finished task from its plan and its last snapshot. */
        fun from(draft: TaskDraft, snapshot: TaskSnapshot, finishedAtMs: Long): HistoryItem = HistoryItem(
            id = snapshot.id,
            title = snapshot.title,
            status = snapshot.status,
            summary = snapshot.summary,
            finishedAtMs = finishedAtMs,
            steps = draft.steps.mapIndexed { index, step ->
                val shown: StepSnapshot? = snapshot.steps.getOrNull(index)
                HistoryStep(
                    title = step.title,
                    command = step.command,
                    intentType = step.intentType,
                    entities = step.entities,
                    state = shown?.state ?: StepState.CANCELLED,
                    message = shown?.message
                )
            }
        )
    }
}

/**
 * Writes the steps of a task into one piece of text and reads them back, so the history can keep them
 * in the "detail" column of the existing task table (no database change). Control characters are used
 * as separators and are removed from the texts. Pure logic. Reading is forgiving: a damaged record is skipped.
 */
object HistoryCodec {

    private const val VERSION: String = "1"
    private const val RECORD: Char = '\u001E'
    private const val FIELD: Char = '\u001F'
    private const val PAIR: Char = '\u001C'
    private const val KEY_VALUE: Char = '\u001D'
    private val SEPARATORS: Regex = Regex("[\u001C\u001D\u001E\u001F]")

    /** The "detail" text for [item]. */
    fun encode(item: HistoryItem): String {
        val records: MutableList<String> = mutableListOf(VERSION + FIELD + clean(item.summary.orEmpty()))
        for (step in item.steps) {
            val entities: String = step.entities.entries.joinToString(PAIR.toString()) {
                clean(it.key) + KEY_VALUE + clean(it.value)
            }
            records.add(
                listOf(
                    clean(step.title), clean(step.command), step.intentType.name, step.state.name,
                    clean(step.message.orEmpty()), entities
                ).joinToString(FIELD.toString())
            )
        }
        return records.joinToString(RECORD.toString())
    }

    /** The summary and the steps kept in [detail]. An unknown or empty text gives no summary and no steps. */
    fun decode(detail: String?): Pair<String?, List<HistoryStep>> {
        if (detail.isNullOrEmpty()) return null to emptyList()
        val records: List<String> = detail.split(RECORD)
        val header: List<String> = records.first().split(FIELD)
        if (header.firstOrNull() != VERSION) return null to emptyList()
        val summary: String? = header.getOrNull(1)?.ifEmpty { null }
        val steps: List<HistoryStep> = records.drop(1).mapNotNull { readStep(it) }
        return summary to steps
    }

    private fun readStep(record: String): HistoryStep? {
        val parts: List<String> = record.split(FIELD)
        if (parts.size < 6) return null
        val type: IntentType = enumOrNull<IntentType>(parts[2]) ?: return null
        val state: StepState = enumOrNull<StepState>(parts[3]) ?: return null
        val entities: Map<String, String> = if (parts[5].isEmpty()) {
            emptyMap()
        } else {
            parts[5].split(PAIR).mapNotNull { pair ->
                val kv: List<String> = pair.split(KEY_VALUE)
                if (kv.size == 2) kv[0] to kv[1] else null
            }.toMap()
        }
        return HistoryStep(
            title = parts[0],
            command = parts[1],
            intentType = type,
            entities = entities,
            state = state,
            message = parts[4].ifEmpty { null }
        )
    }

    private fun clean(text: String): String = text.replace(SEPARATORS, " ")

    private inline fun <reified E : Enum<E>> enumOrNull(name: String): E? =
        enumValues<E>().firstOrNull { it.name == name }
}

/** A history record as stored in the existing "tasks" table (the Room entity has the same fields). */
data class HistoryRow(
    val id: String,
    val title: String,
    val status: String,
    val stepCount: Int,
    val createdAtMs: Long,
    val updatedAtMs: Long,
    val detail: String?
) {
    /** The history item for this row, or null if the status is not one this version knows. */
    fun toItem(): HistoryItem? {
        val parsed: TaskStatus = TaskStatus.values().firstOrNull { it.name == status } ?: return null
        val (summary, steps) = HistoryCodec.decode(detail)
        return HistoryItem(id, title, parsed, summary, updatedAtMs, steps)
    }

    companion object {
        /** The row to store for [item]. */
        fun from(item: HistoryItem): HistoryRow = HistoryRow(
            id = item.id,
            title = item.title,
            status = item.status.name,
            stepCount = item.steps.size,
            createdAtMs = item.finishedAtMs,
            updatedAtMs = item.finishedAtMs,
            detail = HistoryCodec.encode(item)
        )
    }
}

/**
 * Turns the queue snapshots into history items. Remember a plan with [remember] when it is queued;
 * give every snapshot to [onSnapshot]: the first time a task is seen finished, its item is returned
 * (once only). Pure logic.
 */
class HistoryRecorder(private val clock: () -> Long) {

    private val plans: LinkedHashMap<String, TaskDraft> = LinkedHashMap()
    private var lastRecordedId: String? = null

    /** Keeps the plan of a queued task so its steps can be saved when it finishes. */
    fun remember(draft: TaskDraft) {
        plans[draft.id] = draft
        while (plans.size > MAX_PLANS) plans.remove(plans.keys.first())
    }

    /** The item to save if [snapshot] shows a task that has just finished, else null. */
    fun onSnapshot(snapshot: QueueSnapshot): HistoryItem? {
        val task: TaskSnapshot = snapshot.current ?: return null
        if (task.isOpen || task.id == lastRecordedId) return null
        val draft: TaskDraft = plans.remove(task.id) ?: return null
        lastRecordedId = task.id
        return HistoryItem.from(draft, task, clock())
    }

    private companion object {
        const val MAX_PLANS: Int = 20
    }
}
EOF

# ---------- TaskVoiceControl.kt ----------
cat > "$BASE/tasks/TaskVoiceControl.kt" <<'EOF'
package com.nova.ai.tasks

import java.util.Locale

/** What the user wants to do with the running task. */
enum class TaskControlCommand { PAUSE, RESUME, CANCEL_CURRENT, CANCEL_ALL, RERUN, STATUS }

/**
 * Understands the short control words said while a task runs ("থামো", "চালিয়ে যাও", "বাতিল",
 * "আবার চালাও", "কতদূর হলো"). Only a whole short phrase counts, so a longer command such as
 * "গান থামাও" or "অ্যালার্ম বাতিল করো" is never taken for a task control. Whether the word applies
 * (a task must be running, paused and so on) is decided by the caller. Pure logic.
 */
object TaskVoiceControl {

    private const val MARKS: String = ",.;:!?।\"“”‘-_"

    // Words at the start that do not change the meaning.
    private val FILLERS: Set<String> = setOf("ভাই", "নোভা", "nova", "hey", "দয়া", "করে", "please", "pls", "একটু", "just")

    private val PHRASES: Map<TaskControlCommand, Set<String>> = mapOf(
        TaskControlCommand.PAUSE to setOf(
            "থামো", "থামুন", "থামাও", "থামিয়ে দাও", "পজ", "পজ করো", "পজ দাও", "অপেক্ষা করো", "দাঁড়াও",
            "কাজ থামাও", "কাজ থামো", "কাজ পজ করো", "টাস্ক থামাও",
            "pause", "pause task", "wait", "hold on", "hold", "stop for now"
        ),
        TaskControlCommand.RESUME to setOf(
            "চালিয়ে যাও", "চালিয়ে যান", "এগিয়ে যাও", "এগোও", "আবার চালু করো", "কাজ চালু করো",
            "কাজ চালিয়ে যাও", "রিজিউম", "কন্টিনিউ",
            "resume", "resume task", "continue", "go on", "carry on", "proceed"
        ),
        TaskControlCommand.CANCEL_CURRENT to setOf(
            "বাতিল", "বাতিল করো", "কাজ বাতিল", "কাজ বাতিল করো", "টাস্ক বাতিল করো", "বাদ দাও", "কাজ বাদ দাও",
            "cancel", "cancel task", "cancel it", "forget it", "abort"
        ),
        TaskControlCommand.CANCEL_ALL to setOf(
            "সব বাতিল", "সব বাতিল করো", "সব কাজ বাতিল", "সব কাজ বাতিল করো", "সব কাজ বন্ধ করো",
            "cancel all", "cancel everything", "cancel all tasks"
        ),
        TaskControlCommand.RERUN to setOf(
            "আবার চালাও", "আবার চেষ্টা করো", "আবার করো", "ব্যর্থ কাজ আবার চালাও", "ব্যর্থ কাজ আবার করো",
            "কাজটা আবার চালাও", "কাজটা আবার করো",
            "retry", "try again", "rerun", "run again", "retry task", "retry the task", "do it again"
        ),
        TaskControlCommand.STATUS to setOf(
            "কাজের অবস্থা", "কাজের অবস্থা কী", "কাজের অবস্থা কি", "কতদূর হলো", "কতদূর", "কতটুকু হলো",
            "কাজ কতদূর", "কাজ কতদূর হলো", "স্ট্যাটাস",
            "task status", "status", "progress", "how far", "how is it going", "whats the progress",
            "what is the progress", "show progress"
        )
    )

    /** The control command in [text], or null if the text is something else. */
    fun parse(text: String): TaskControlCommand? {
        val phrase: String = normalize(text)
        if (phrase.isEmpty()) return null
        return PHRASES.entries.firstOrNull { phrase in it.value }?.key
    }

    private fun normalize(text: String): String {
        var words: List<String> = text.lowercase(Locale.ROOT)
            .filter { it != '\'' && it != '’' }
            .map { if (it in MARKS) ' ' else it }
            .joinToString("")
            .split(Regex("\\s+"))
            .filter { it.isNotEmpty() }
        while (words.size > 1 && words.first() in FILLERS) words = words.drop(1)
        return words.joinToString(" ")
    }
}
EOF

# ---------- TaskControlPlanner.kt ----------
cat > "$BASE/tasks/TaskControlPlanner.kt" <<'EOF'
package com.nova.ai.tasks

/** What the hub must do for a control word. */
enum class ControlAction { PAUSE, RESUME, CANCEL_CURRENT, CANCEL_ALL, RERUN, NONE }

/** The decision: what to do, and what to tell the user (null when the queue already says it). */
data class ControlDecision(val action: ControlAction, val reply: String?)

/**
 * Decides what a control word means for the queue as it is now. Returns null when the word does
 * not apply (nothing runs, nothing is paused...), so the caller handles the text as an ordinary
 * command. Pure logic, no Android classes.
 */
object TaskControlPlanner {

    /** [rerunnableSteps] = number of unfinished steps of the last failed or cancelled task, 0 if there is none. */
    fun decide(command: TaskControlCommand, queue: QueueSnapshot, rerunnableSteps: Int): ControlDecision? {
        val current: TaskSnapshot? = queue.current?.takeIf { it.isOpen }
        return when (command) {
            TaskControlCommand.PAUSE -> when (current?.status) {
                com.nova.ai.core.TaskStatus.RUNNING -> ControlDecision(ControlAction.PAUSE, TaskMessages.MSG_PAUSED)
                com.nova.ai.core.TaskStatus.PAUSED ->
                    ControlDecision(ControlAction.NONE, TaskMessages.MSG_ALREADY_PAUSED)
                else -> null
            }
            TaskControlCommand.RESUME ->
                if (current?.status == com.nova.ai.core.TaskStatus.PAUSED) {
                    ControlDecision(ControlAction.RESUME, TaskMessages.MSG_RESUMED)
                } else {
                    null
                }
            TaskControlCommand.CANCEL_CURRENT ->
                if (current != null) ControlDecision(ControlAction.CANCEL_CURRENT, null) else null
            TaskControlCommand.CANCEL_ALL ->
                if (current != null || queue.waiting.isNotEmpty()) ControlDecision(ControlAction.CANCEL_ALL, null) else null
            TaskControlCommand.RERUN ->
                if (current == null && rerunnableSteps > 0) {
                    ControlDecision(ControlAction.RERUN, TaskMessages.rerunStarted(rerunnableSteps))
                } else {
                    null
                }
            TaskControlCommand.STATUS -> current?.let { ControlDecision(ControlAction.NONE, statusText(it)) }
        }
    }

    private fun statusText(task: TaskSnapshot): String {
        val total: Int = task.steps.size
        return when {
            task.question != null -> TaskMessages.statusQuestion(task.doneCount, total)
            task.status == com.nova.ai.core.TaskStatus.PAUSED -> TaskMessages.statusPaused(task.doneCount, total)
            else -> {
                val index: Int = if (task.activeIndex >= 0) task.activeIndex else task.doneCount.coerceAtMost(total - 1)
                TaskMessages.statusRunning(task.doneCount, total, task.steps.getOrNull(index)?.title ?: task.title)
            }
        }
    }
}
EOF

# ---------- TaskHistoryRepository.kt ----------
cat > "$BASE/tasks/TaskHistoryRepository.kt" <<'EOF'
package com.nova.ai.tasks

import android.content.Context
import com.nova.ai.data.dao.TaskDao
import com.nova.ai.data.db.NovaDatabase
import com.nova.ai.data.entity.TaskEntity
import com.nova.ai.logging.NovaLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Keeps the task history in the phone's database (the existing "tasks" table). Every call runs on a
 * background thread and never throws: a database problem is logged and the call gives an empty or
 * false result, so a task is never stopped because the history could not be saved.
 */
class TaskHistoryRepository(context: Context) {

    private val dao: TaskDao = NovaDatabase.getInstance(context.applicationContext).taskDao()

    /** Saves [item] and keeps only the newest [HISTORY_LIMIT] records. */
    suspend fun save(item: HistoryItem): Boolean = withContext(Dispatchers.IO) {
        try {
            val row: HistoryRow = HistoryRow.from(item)
            dao.upsert(
                TaskEntity(row.id, row.title, row.status, row.stepCount, row.createdAtMs, row.updatedAtMs, row.detail)
            )
            dao.trimTo(HISTORY_LIMIT)
            true
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not save the task history", e)
            false
        }
    }

    /** The newest records, newest first. */
    suspend fun recent(limit: Int = HISTORY_LIMIT): List<HistoryItem> = withContext(Dispatchers.IO) {
        try {
            dao.getRecent(limit).mapNotNull { e ->
                HistoryRow(e.id, e.title, e.status, e.stepCount, e.createdAtMs, e.updatedAtMs, e.detail).toItem()
            }
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not read the task history", e)
            emptyList()
        }
    }

    /** Deletes the whole history. */
    suspend fun clear(): Boolean = withContext(Dispatchers.IO) {
        try {
            dao.clearAll()
            true
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not clear the task history", e)
            false
        }
    }

    companion object {
        private const val TAG: String = "TaskHistory"

        /** How many finished tasks are kept. */
        const val HISTORY_LIMIT: Int = 50
    }
}
EOF

# ---------- TaskHub.kt ----------
cat > "$BASE/tasks/TaskHub.kt" <<'EOF'
package com.nova.ai.tasks

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.security.EmergencyStop
import com.nova.ai.voice.LanguageDetector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.CopyOnWriteArrayList

/**
 * The one place where multi-step tasks are started and watched. The Home screen, the bubble and
 * the Automation screen all use it: a command with several parts ("ক্রোম খোলো তারপর ভলিউম বাড়াও")
 * is planned, queued and run step by step. The emergency stop cancels everything. [state] is
 * observable by Compose screens; other code can use [addListener]. Use from the main thread.
 */
object TaskHub {

    private const val TAG: String = "TaskHub"
    private const val HOOK_KEY: String = "tasks"

    /** The queue as the screens show it. Changes only on the main thread. */
    var state: QueueSnapshot by mutableStateOf(QueueSnapshot.EMPTY)
        private set

    private val listeners: CopyOnWriteArrayList<(QueueSnapshot) -> Unit> = CopyOnWriteArrayList()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val brain = RuleBasedBrain()

    /** The finished tasks, newest first (at most [TaskHistoryRepository.HISTORY_LIMIT]). Main thread. */
    var history: List<HistoryItem> by mutableStateOf(emptyList())
        private set

    private val recorder = HistoryRecorder { System.currentTimeMillis() }
    private var repository: TaskHistoryRepository? = null
    private var scope: CoroutineScope? = null
    private var noticeIsError: Boolean = true

    private var queue: TaskQueue? = null
    private var planner: CommandPlanner? = null
    private var notice: String? = null
    private var noticeSeq: Int = 0

    /** Gets everything ready. Safe to call many times. */
    fun init(context: Context) {
        if (queue != null) return
        val appContext: Context = context.applicationContext
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        this.scope = scope
        repository = try {
            TaskHistoryRepository(appContext)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "The task history is not available", e)
            null
        }
        queue = TaskQueue(
            executor = CommandStepExecutor(appContext, scope),
            scheduler = HandlerScheduler(mainHandler),
            onChanged = { snapshot -> publish(snapshot) },
            timing = TaskTiming(
                perTypeTimeoutMs = mapOf(
                    IntentType.SYSTEM_ACTION to 10_000L,
                    IntentType.MEDIA_CONTROL to 10_000L,
                    IntentType.OPEN_APP to 15_000L
                )
            ),
            log = { message -> NovaLogger.i(TAG, message) },
            retry = RetryPolicy.STANDARD,
            fallback = WebFallbackPlanner
        )
        planner = CommandPlanner(analyze = { part -> analyze(part) })
        loadHistory()
        // The emergency stop cancels the running task and empties the line.
        EmergencyStop.registerHook(HOOK_KEY) { mainHandler.post { queue?.cancelAll() } }
    }

    /** Gets [listener] every time the queue changes (main thread). */
    fun addListener(listener: (QueueSnapshot) -> Unit) {
        listeners.addIfAbsent(listener)
    }

    /** Stops [listener]. */
    fun removeListener(listener: (QueueSnapshot) -> Unit) {
        listeners.remove(listener)
    }

    /**
     * If [text] has several parts, plans it and puts it in the queue and returns true (the caller
     * must not run it any other way). Returns false for an ordinary single command.
     * A part that is not understood is reported through [QueueSnapshot.notice], and nothing starts.
     */
    fun submitIfMultiStep(context: Context, text: String): Boolean {
        init(context)
        val planner: CommandPlanner = planner ?: return false
        if (!planner.isMultiStep(text)) return false
        submit(context, text)
        return true
    }

    /** Plans [text] and puts it in the queue. A failure result carries a Bangla message (also shown as the notice). */
    fun submit(context: Context, text: String): NovaResult<String> {
        init(context)
        val queue: TaskQueue = queue ?: return failed("")
        val planner: CommandPlanner = planner ?: return failed("")
        if (EmergencyStop.isActive) return failed(EmergencyStop.MESSAGE)
        return when (val plan: NovaResult<TaskDraft> = planner.plan(text)) {
            is NovaResult.Failure -> failed(plan.error.message)
            is NovaResult.Success -> when (val queued: NovaResult<String> = queue.submit(plan.value)) {
                is NovaResult.Failure -> failed(queued.error.message)
                is NovaResult.Success -> {
                    recorder.remember(plan.value)
                    setNotice(null)
                    queued
                }
            }
        }
    }

    /** The user picked option number [index] of the question. */
    fun answer(index: Int) {
        val result: NovaResult<Unit> = queue?.answer(index) ?: return
        if (result is NovaResult.Failure) setNotice(result.error.message)
    }

    /** Cancels the task in front. */
    fun cancelCurrent() {
        val id: String = state.current?.takeIf { it.isOpen }?.id ?: return
        queue?.cancel(id)
    }

    /** Cancels the task in front and empties the line. */
    fun cancelAll() {
        queue?.cancelAll()
    }

    /** Pauses the task in front before its next step. */
    fun pause() {
        val id: String = state.current?.id ?: return
        val result: NovaResult<Unit> = queue?.pause(id) ?: return
        if (result is NovaResult.Failure) setNotice(result.error.message)
    }

    /** Lets a paused task go on. */
    fun resume() {
        val id: String = state.current?.id ?: return
        val result: NovaResult<Unit> = queue?.resume(id) ?: return
        if (result is NovaResult.Failure) setNotice(result.error.message)
    }

    /**
     * P25: if [text] is a control word for the task ("থামো", "চালিয়ে যাও", "বাতিল", "আবার চালাও",
     * "কতদূর হলো") that applies now, does it, shows the answer as a notice and returns true.
     * Returns false when the text is something else, so the caller runs it as an ordinary command.
     */
    fun handleControl(context: Context, text: String): Boolean {
        init(context)
        val command: TaskControlCommand = TaskVoiceControl.parse(text) ?: return false
        return execute(command)
    }

    /**
     * P25: the user said a stop word ("থামো") and the conversation ended. If a task is running it
     * is paused (it can be resumed). Returns true if a task was paused.
     */
    fun pauseIfRunning(context: Context): Boolean {
        init(context)
        return execute(TaskControlCommand.PAUSE)
    }

    private fun execute(command: TaskControlCommand): Boolean {
        val queue: TaskQueue = queue ?: return false
        val rerunnable: HistoryItem? = lastRerunnable()
        val rerunSteps: Int = rerunnable?.steps?.count { it.state != StepState.DONE } ?: 0
        val decision: ControlDecision = TaskControlPlanner.decide(command, queue.snapshot(), rerunSteps) ?: return false
        when (decision.action) {
            ControlAction.PAUSE -> pause()
            ControlAction.RESUME -> resume()
            ControlAction.CANCEL_CURRENT -> cancelCurrent()
            ControlAction.CANCEL_ALL -> cancelAll()
            ControlAction.RERUN -> if (rerunnable != null) rerun(rerunnable)
            ControlAction.NONE -> Unit
        }
        decision.reply?.let { setNotice(it, isError = false) }
        return true
    }

    // The newest finished task that can be run again: the one just finished, or the newest in the history.
    private fun lastRerunnable(): HistoryItem? = history.firstOrNull()?.takeIf { it.canRerun }

    /** P25: runs the steps of [item] that did not finish as a new task. Returns false if nothing could be queued. */
    fun rerun(item: HistoryItem): Boolean {
        val queue: TaskQueue = queue ?: return false
        if (EmergencyStop.isActive) {
            setNotice(EmergencyStop.MESSAGE, isError = true)
            return false
        }
        val draft: TaskDraft? = item.toRerunDraft("t" + System.currentTimeMillis())
        if (draft == null) {
            setNotice(if (item.steps.isEmpty()) TaskMessages.MSG_HISTORY_NOT_FOUND else TaskMessages.MSG_NOTHING_LEFT, true)
            return false
        }
        return when (val queued: NovaResult<String> = queue.submit(draft)) {
            is NovaResult.Failure -> {
                setNotice(queued.error.message, isError = true)
                false
            }
            is NovaResult.Success -> {
                recorder.remember(draft)
                setNotice(null)
                true
            }
        }
    }

    /** P25: deletes the task history (the memory copy and the database). */
    fun clearHistory() {
        history = emptyList()
        val repo: TaskHistoryRepository = repository ?: return
        scope?.launch { repo.clear() }
        setNotice(TaskMessages.MSG_HISTORY_CLEARED, isError = false)
    }

    private fun loadHistory() {
        val repo: TaskHistoryRepository = repository ?: return
        scope?.launch {
            val loaded: List<HistoryItem> = repo.recent()
            // A task may have finished while the list was loading; keep it in front.
            val fresh: List<HistoryItem> = history.filter { h -> loaded.none { it.id == h.id } }
            history = (fresh + loaded).take(TaskHistoryRepository.HISTORY_LIMIT)
        }
    }

    private fun record(item: HistoryItem) {
        history = (listOf(item) + history.filter { it.id != item.id }).take(TaskHistoryRepository.HISTORY_LIMIT)
        val repo: TaskHistoryRepository = repository ?: return
        scope?.launch { repo.save(item) }
    }

    /** Closes the result of the last task and the notice. */
    fun dismiss() {
        notice = null
        noticeIsError = true
        val queue: TaskQueue? = queue
        if (queue != null) {
            queue.dismissFinished()
            publish(queue.snapshot())
        } else {
            publish(QueueSnapshot.EMPTY)
        }
    }

    private fun failed(message: String): NovaResult<String> {
        setNotice(message.ifBlank { null })
        return NovaResult.failure(ErrorCode.INVALID_INPUT, message)
    }

    private fun setNotice(message: String?, isError: Boolean = true) {
        notice = message
        noticeIsError = isError
        if (message != null) noticeSeq += 1
        publish(queue?.snapshot() ?: QueueSnapshot.EMPTY)
    }

    private fun publish(snapshot: QueueSnapshot) {
        val merged: QueueSnapshot = snapshot.copy(notice = notice, noticeSeq = noticeSeq, noticeIsError = noticeIsError)
        recorder.onSnapshot(merged)?.let { record(it) }
        state = merged
        for (listener in listeners) {
            try {
                listener(merged)
            } catch (e: Exception) {
                NovaLogger.e(TAG, "A task listener failed", e)
            }
        }
    }

    // The meaning of one part of a command, from the rule-based brain.
    private fun analyze(part: String): NovaIntent? {
        val command = VoiceCommand(
            rawText = part,
            language = LanguageDetector.detect(part),
            timestampMs = System.currentTimeMillis()
        )
        return brain.analyze(command, emptyList()).getOrNull()
    }
}
EOF

# ---------- TaskQueueCard.kt ----------
cat > "$BASE/ui/components/TaskQueueCard.kt" <<'EOF'
package com.nova.ai.ui.components

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.core.NovaResult
import com.nova.ai.core.TaskStatus
import com.nova.ai.tasks.QueueSnapshot
import com.nova.ai.tasks.StepSnapshot
import com.nova.ai.tasks.StepState
import com.nova.ai.tasks.TaskHub
import com.nova.ai.tasks.TaskSnapshot

/**
 * Shows the task NOVA is running (every step with its state), the tasks waiting behind it, a
 * question when a step needs an answer, and the controls (pause, cancel). With [showInput] the card
 * also has a box to type a command with several parts; without it, the card appears only while
 * there is something to show (used on the Home screen).
 */
@Composable
fun TaskQueueCard(modifier: Modifier = Modifier, showInput: Boolean = true) {
    val context: Context = LocalContext.current
    val snapshot: QueueSnapshot = TaskHub.state
    val current: TaskSnapshot? = snapshot.current

    var typed: String by rememberSaveable { mutableStateOf("") }

    if (!showInput && current == null && snapshot.waiting.isEmpty() && snapshot.notice == null) return

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.tsk_card_title),
                style = MaterialTheme.typography.titleMedium
            )

            if (showInput) {
                Text(
                    text = stringResource(R.string.tsk_card_note),
                    style = MaterialTheme.typography.bodySmall
                )
                OutlinedTextField(
                    value = typed,
                    onValueChange = { typed = it },
                    label = { Text(stringResource(R.string.tsk_input_label)) },
                    modifier = Modifier.fillMaxWidth()
                )
                Button(
                    onClick = {
                        if (TaskHub.submit(context, typed) is NovaResult.Success) typed = ""
                    },
                    enabled = typed.isNotBlank(),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.tsk_run))
                }
            }

            snapshot.notice?.let { notice ->
                Text(
                    text = notice,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (snapshot.noticeIsError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
                )
            }

            if (current != null) TaskBlock(current)

            if (snapshot.waiting.isNotEmpty()) {
                Text(
                    text = stringResource(R.string.tsk_waiting, snapshot.waiting.joinToString(" • ")),
                    style = MaterialTheme.typography.bodySmall
                )
                OutlinedButton(
                    onClick = { TaskHub.cancelAll() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.tsk_cancel_all))
                }
            }

            if (current != null && !current.isOpen) {
                OutlinedButton(
                    onClick = { TaskHub.dismiss() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.tsk_dismiss))
                }
            } else if (snapshot.notice != null && current == null) {
                OutlinedButton(
                    onClick = { TaskHub.dismiss() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.tsk_dismiss))
                }
            }
        }
    }
}

// One task: title, progress, the steps, the question (if any) and the pause and cancel buttons.
@Composable
private fun TaskBlock(task: TaskSnapshot) {
    Text(text = task.title, style = MaterialTheme.typography.bodyMedium)
    Text(
        text = stringResource(R.string.tsk_progress, task.doneCount, task.steps.size) +
            " · " + stringResource(statusText(task.status)),
        style = MaterialTheme.typography.bodySmall
    )
    for ((position, step) in task.steps.withIndex()) {
        Text(
            text = "${icon(step.state)} ${position + 1}. ${stepLine(step)}",
            style = MaterialTheme.typography.bodySmall
        )
    }
    task.summary?.let { Text(text = it, style = MaterialTheme.typography.bodyMedium) }

    task.question?.let { question ->
        Text(text = question.text, style = MaterialTheme.typography.bodyMedium)
        for ((index, label) in question.options.withIndex()) {
            Button(
                onClick = { TaskHub.answer(index) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(label)
            }
        }
    }

    if (task.isOpen) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (task.status == TaskStatus.PAUSED) {
                Button(onClick = { TaskHub.resume() }, modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.tsk_resume))
                }
            } else {
                OutlinedButton(onClick = { TaskHub.pause() }, modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.tsk_pause))
                }
            }
            OutlinedButton(onClick = { TaskHub.cancelCurrent() }, modifier = Modifier.weight(1f)) {
                Text(stringResource(R.string.tsk_cancel))
            }
        }
    }
}

private fun stepLine(step: StepSnapshot): String {
    val tries: String = if (step.attempt > 1 && step.state != StepState.DONE) " [${step.attempt}/${step.maxAttempts}]" else ""
    val note: String = if (step.message.isNullOrBlank()) "" else " — ${step.message}"
    return step.title + tries + note
}

private fun icon(state: StepState): String = when (state) {
    StepState.PENDING -> "○"
    StepState.RUNNING -> "▶"
    StepState.RETRYING -> "🔁"
    StepState.WAITING_USER -> "❓"
    StepState.DONE -> "✅"
    StepState.FAILED -> "❌"
    StepState.SKIPPED -> "⏭"
    StepState.CANCELLED -> "⏹"
}

private fun statusText(status: TaskStatus): Int = when (status) {
    TaskStatus.PENDING -> R.string.tsk_status_pending
    TaskStatus.RUNNING -> R.string.tsk_status_running
    TaskStatus.PAUSED -> R.string.tsk_status_paused
    TaskStatus.COMPLETED -> R.string.tsk_status_completed
    TaskStatus.FAILED -> R.string.tsk_status_failed
    TaskStatus.CANCELLED -> R.string.tsk_status_cancelled
}
EOF

# ---------- TaskHistoryCard.kt ----------
cat > "$BASE/ui/components/TaskHistoryCard.kt" <<'EOF'
package com.nova.ai.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.core.TaskStatus
import com.nova.ai.tasks.HistoryItem
import com.nova.ai.tasks.StepState
import com.nova.ai.tasks.TaskHub
import java.text.DateFormat
import java.util.Date

/**
 * The task history: every finished task with its result and time. A failed or cancelled task can be
 * run again (only its unfinished steps). Tap a task to see its steps. Shows the newest [SHOWN] tasks.
 */
@Composable
fun TaskHistoryCard(modifier: Modifier = Modifier) {
    val history: List<HistoryItem> = TaskHub.history
    var openId: String? by rememberSaveable { mutableStateOf(null) }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.automation_history_title),
                style = MaterialTheme.typography.titleMedium
            )
            if (history.isEmpty()) {
                Text(
                    text = stringResource(R.string.tskh_empty),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            for (item in history.take(SHOWN)) {
                HistoryRowView(item, expanded = openId == item.id) {
                    openId = if (openId == item.id) null else item.id
                }
            }
            if (history.isNotEmpty()) {
                OutlinedButton(onClick = { TaskHub.clearHistory() }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.tskh_clear))
                }
            }
        }
    }
}

@Composable
private fun HistoryRowView(item: HistoryItem, expanded: Boolean, onToggle: () -> Unit) {
    val time: String = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(item.finishedAtMs))
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        OutlinedButton(onClick = onToggle, modifier = Modifier.fillMaxWidth()) {
            Text("${statusIcon(item.status)} ${item.title}")
        }
        Text(
            text = "$time · ${stringResource(statusText(item.status))} · " +
                stringResource(R.string.tsk_progress, item.steps.count { it.state == StepState.DONE }, item.steps.size),
            style = MaterialTheme.typography.bodySmall
        )
        if (expanded) {
            item.summary?.let { Text(text = it, style = MaterialTheme.typography.bodyMedium) }
            for ((position, step) in item.steps.withIndex()) {
                val note: String = if (step.message.isNullOrBlank()) "" else " — ${step.message}"
                Text(
                    text = "${stepIcon(step.state)} ${position + 1}. ${step.title}$note",
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (item.canRerun) {
                OutlinedButton(onClick = { TaskHub.rerun(item) }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.tskh_rerun))
                }
            }
        }
    }
}

private const val SHOWN: Int = 20

private fun statusIcon(status: TaskStatus): String = when (status) {
    TaskStatus.COMPLETED -> "✅"
    TaskStatus.FAILED -> "❌"
    TaskStatus.CANCELLED -> "⏹"
    TaskStatus.PAUSED -> "⏸"
    TaskStatus.RUNNING, TaskStatus.PENDING -> "⏳"
}

private fun stepIcon(state: StepState): String = when (state) {
    StepState.DONE -> "✅"
    StepState.FAILED -> "❌"
    StepState.SKIPPED -> "⏭"
    StepState.CANCELLED -> "⏹"
    else -> "○"
}

private fun statusText(status: TaskStatus): Int = when (status) {
    TaskStatus.PENDING -> R.string.tsk_status_pending
    TaskStatus.RUNNING -> R.string.tsk_status_running
    TaskStatus.PAUSED -> R.string.tsk_status_paused
    TaskStatus.COMPLETED -> R.string.tsk_status_completed
    TaskStatus.FAILED -> R.string.tsk_status_failed
    TaskStatus.CANCELLED -> R.string.tsk_status_cancelled
}
EOF

# ---------- strings_p25.xml ----------
cat > "$RES/strings_p25.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<!-- P25: task control and task history. -->
<resources>
    <string name="tskh_empty">এখনো কোনো কাজ শেষ হয়নি। কয়েকটি ধাপের কাজ চালালে এখানে জমা হবে।</string>
    <string name="tskh_rerun">বাকি ধাপ আবার চালাও</string>
    <string name="tskh_clear">ইতিহাস মোছো</string>
    <string name="bub_task_pause">কাজ থামান</string>
    <string name="bub_task_resume">কাজ চালিয়ে যান</string>
</resources>
EOF

# ---------- TaskVoiceControlTest.kt ----------
cat > "$TEST/tasks/TaskVoiceControlTest.kt" <<'EOF'
package com.nova.ai.tasks

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Tests that only whole short control phrases are taken for task controls. */
class TaskVoiceControlTest {

    @Test
    fun banglaAndEnglishWordsAreUnderstood() {
        assertEquals(TaskControlCommand.PAUSE, TaskVoiceControl.parse("থামো"))
        assertEquals(TaskControlCommand.PAUSE, TaskVoiceControl.parse("Pause"))
        assertEquals(TaskControlCommand.RESUME, TaskVoiceControl.parse("চালিয়ে যাও"))
        assertEquals(TaskControlCommand.RESUME, TaskVoiceControl.parse("resume"))
        assertEquals(TaskControlCommand.CANCEL_CURRENT, TaskVoiceControl.parse("বাতিল করো"))
        assertEquals(TaskControlCommand.CANCEL_ALL, TaskVoiceControl.parse("সব বাতিল করো"))
        assertEquals(TaskControlCommand.RERUN, TaskVoiceControl.parse("আবার চালাও"))
        assertEquals(TaskControlCommand.RERUN, TaskVoiceControl.parse("try again"))
        assertEquals(TaskControlCommand.STATUS, TaskVoiceControl.parse("কতদূর হলো"))
    }

    @Test
    fun marksCaseAndFillerWordsAreIgnored() {
        assertEquals(TaskControlCommand.PAUSE, TaskVoiceControl.parse("  নোভা, থামো!  "))
        assertEquals(TaskControlCommand.PAUSE, TaskVoiceControl.parse("Hey Nova, PAUSE."))
        assertEquals(TaskControlCommand.PAUSE, TaskVoiceControl.parse("থামো।"))
        assertEquals(TaskControlCommand.STATUS, TaskVoiceControl.parse("What's the progress?"))
        assertEquals(TaskControlCommand.PAUSE, TaskVoiceControl.parse("please pause"))
    }

    @Test
    fun longerCommandsAreNotControls() {
        assertNull(TaskVoiceControl.parse("গান থামাও"))
        assertNull(TaskVoiceControl.parse("অ্যালার্ম বাতিল করো"))
        assertNull(TaskVoiceControl.parse("ক্রোম খোলো তারপর থামো"))
        assertNull(TaskVoiceControl.parse("cancel my alarm"))
        assertNull(TaskVoiceControl.parse("resume the music"))
    }

    @Test
    fun emptyTextIsNotAControl() {
        assertNull(TaskVoiceControl.parse(""))
        assertNull(TaskVoiceControl.parse("   "))
        assertNull(TaskVoiceControl.parse("..."))
    }
}
EOF

# ---------- TaskControlPlannerTest.kt ----------
cat > "$TEST/tasks/TaskControlPlannerTest.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.TaskStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests what a control word means for the queue as it is now. */
class TaskControlPlannerTest {

    private fun task(status: TaskStatus, states: List<StepState>, question: PendingQuestion? = null) = TaskSnapshot(
        id = "t1", title = "কাজ", status = status,
        steps = states.mapIndexed { i, s -> StepSnapshot("s$i", "ধাপ ${i + 1}", s, null, 1, 3) },
        question = question, summary = null
    )

    private fun queue(task: TaskSnapshot?, waiting: List<String> = emptyList()) = QueueSnapshot(task, waiting)

    private val running = task(TaskStatus.RUNNING, listOf(StepState.DONE, StepState.RUNNING, StepState.PENDING))
    private val paused = task(TaskStatus.PAUSED, listOf(StepState.DONE, StepState.PENDING))
    private val failed = task(TaskStatus.FAILED, listOf(StepState.DONE, StepState.FAILED))

    @Test
    fun pauseWorksOnARunningTask() {
        val d = TaskControlPlanner.decide(TaskControlCommand.PAUSE, queue(running), 0)!!
        assertEquals(ControlAction.PAUSE, d.action)
        assertEquals(TaskMessages.MSG_PAUSED, d.reply)
    }

    @Test
    fun pauseOnAPausedTaskOnlyTellsIt() {
        val d = TaskControlPlanner.decide(TaskControlCommand.PAUSE, queue(paused), 0)!!
        assertEquals(ControlAction.NONE, d.action)
        assertEquals(TaskMessages.MSG_ALREADY_PAUSED, d.reply)
    }

    @Test
    fun pauseWithoutATaskIsNotHandled() {
        assertNull(TaskControlPlanner.decide(TaskControlCommand.PAUSE, queue(null), 0))
        assertNull(TaskControlPlanner.decide(TaskControlCommand.PAUSE, queue(failed), 0))
    }

    @Test
    fun resumeOnlyWorksOnAPausedTask() {
        assertEquals(ControlAction.RESUME, TaskControlPlanner.decide(TaskControlCommand.RESUME, queue(paused), 0)!!.action)
        assertNull(TaskControlPlanner.decide(TaskControlCommand.RESUME, queue(running), 0))
        assertNull(TaskControlPlanner.decide(TaskControlCommand.RESUME, queue(null), 0))
    }

    @Test
    fun cancelNeedsATaskAndCancelAllAlsoCountsTheLine() {
        assertEquals(ControlAction.CANCEL_CURRENT, TaskControlPlanner.decide(TaskControlCommand.CANCEL_CURRENT, queue(running), 0)!!.action)
        assertNull(TaskControlPlanner.decide(TaskControlCommand.CANCEL_CURRENT, queue(null), 0))
        assertEquals(ControlAction.CANCEL_ALL, TaskControlPlanner.decide(TaskControlCommand.CANCEL_ALL, queue(null, listOf("x")), 0)!!.action)
        assertNull(TaskControlPlanner.decide(TaskControlCommand.CANCEL_ALL, queue(null), 0))
    }

    @Test
    fun rerunNeedsAnIdleQueueAndUnfinishedSteps() {
        val d = TaskControlPlanner.decide(TaskControlCommand.RERUN, queue(failed), 2)!!
        assertEquals(ControlAction.RERUN, d.action)
        assertEquals(TaskMessages.rerunStarted(2), d.reply)
        assertNull(TaskControlPlanner.decide(TaskControlCommand.RERUN, queue(failed), 0))
        assertNull(TaskControlPlanner.decide(TaskControlCommand.RERUN, queue(running), 2))
    }

    @Test
    fun statusTellsTheProgress() {
        val d = TaskControlPlanner.decide(TaskControlCommand.STATUS, queue(running), 0)!!
        assertEquals(ControlAction.NONE, d.action)
        assertEquals(TaskMessages.statusRunning(1, 3, "ধাপ 2"), d.reply)
        assertEquals(TaskMessages.statusPaused(1, 2), TaskControlPlanner.decide(TaskControlCommand.STATUS, queue(paused), 0)!!.reply)
        val asking = task(TaskStatus.RUNNING, listOf(StepState.WAITING_USER), PendingQuestion("?", listOf("a")))
        assertEquals(TaskMessages.statusQuestion(0, 1), TaskControlPlanner.decide(TaskControlCommand.STATUS, queue(asking), 0)!!.reply)
        assertNull(TaskControlPlanner.decide(TaskControlCommand.STATUS, queue(null), 0))
        assertTrue(TaskMessages.statusRunning(1, 3, "x").contains("1/3"))
    }
}
EOF

# ---------- TaskHistoryTest.kt ----------
cat > "$TEST/tasks/TaskHistoryTest.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaResult
import com.nova.ai.core.TaskStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests the history record, its text form, the database row, the recorder and the rerun. */
class TaskHistoryTest {

    private fun step(n: Int, type: IntentType = IntentType.OPEN_APP, vararg e: Pair<String, String>) =
        PlannedStep("s$n", "ধাপ $n", "কমান্ড $n", type, entities = mapOf(*e))

    private fun draft(id: String = "t1") = TaskDraft(id, "কাজ", listOf(step(1, IntentType.OPEN_APP, "app" to "ক্রোম"), step(2), step(3)))

    private fun snap(id: String, status: TaskStatus, vararg states: StepState) = QueueSnapshot(
        TaskSnapshot(
            id, "কাজ", status,
            states.mapIndexed { i, s -> StepSnapshot("s${i + 1}", "ধাপ ${i + 1}", s, if (s == StepState.FAILED) "ব্যর্থ" else null, 1, 3) },
            null, "সারাংশ"
        ),
        emptyList()
    )

    private fun item(status: TaskStatus = TaskStatus.FAILED) =
        HistoryItem.from(draft(), snap("t1", status, StepState.DONE, StepState.FAILED, StepState.CANCELLED).current!!, 1000L)

    @Test
    fun itemKeepsPlanAndResult() {
        val i = item()
        assertEquals(3, i.steps.size)
        assertEquals(StepState.DONE, i.steps[0].state)
        assertEquals("ব্যর্থ", i.steps[1].message)
        assertEquals("ক্রোম", i.steps[0].entities["app"])
        assertEquals(1000L, i.finishedAtMs)
    }

    @Test
    fun codecRoundTripKeepsEverything() {
        val i = item()
        val (summary, steps) = HistoryCodec.decode(HistoryCodec.encode(i))
        assertEquals("সারাংশ", summary)
        assertEquals(i.steps, steps)
    }

    @Test
    fun codecRemovesSeparatorsFromTexts() {
        val bad = HistoryItem("x", "t", TaskStatus.FAILED, "a\u001Eb", 1L,
            listOf(HistoryStep("t\u001Fx", "c\u001Dd", IntentType.OPEN_APP, mapOf("k\u001C" to "v\u001E"), StepState.FAILED, "m\u001F")))
        val (summary, steps) = HistoryCodec.decode(HistoryCodec.encode(bad))
        assertEquals("a b", summary)
        assertEquals(1, steps.size)
        assertEquals("t x", steps[0].title)
        assertEquals(mapOf("k " to "v "), steps[0].entities)
    }

    @Test
    fun damagedOrUnknownDetailGivesNothing() {
        assertEquals(null to emptyList<HistoryStep>(), HistoryCodec.decode(null))
        assertEquals(null to emptyList<HistoryStep>(), HistoryCodec.decode(""))
        assertEquals(null to emptyList<HistoryStep>(), HistoryCodec.decode("9\u001Fx"))
        val (_, steps) = HistoryCodec.decode("1\u001F\u001Ea\u001Fb\u001FNO_SUCH\u001FDONE\u001F\u001F")
        assertTrue(steps.isEmpty())
    }

    @Test
    fun rowRoundTripAndUnknownStatus() {
        val i = item()
        val row = HistoryRow.from(i)
        assertEquals("FAILED", row.status)
        assertEquals(3, row.stepCount)
        assertEquals(i, row.toItem())
        assertNull(row.copy(status = "FUTURE_STATUS").toItem())
    }

    @Test
    fun rerunKeepsOnlyUnfinishedStepsInOrder() {
        val d = item().toRerunDraft("new")!!
        assertEquals("new", d.id)
        assertEquals(TaskMessages.rerunTitle("কাজ"), d.title)
        assertEquals(listOf("কমান্ড 2", "কমান্ড 3"), d.steps.map { it.command })
        assertEquals(listOf("s1", "s2"), d.steps.map { it.id })
    }

    @Test
    fun completedTaskCannotBeRerun() {
        val done = HistoryItem.from(draft(), snap("t1", TaskStatus.COMPLETED, StepState.DONE, StepState.DONE, StepState.DONE).current!!, 1L)
        assertFalse(done.canRerun)
        assertNull(done.toRerunDraft("n"))
        assertTrue(item(TaskStatus.CANCELLED).canRerun)
    }

    @Test
    fun recorderSavesAFinishedTaskOnce() {
        val r = HistoryRecorder { 5L }
        r.remember(draft())
        assertNull(r.onSnapshot(snap("t1", TaskStatus.RUNNING, StepState.RUNNING, StepState.PENDING, StepState.PENDING)))
        val saved = r.onSnapshot(snap("t1", TaskStatus.FAILED, StepState.DONE, StepState.FAILED, StepState.CANCELLED))
        assertNotNull(saved)
        assertEquals(5L, saved!!.finishedAtMs)
        assertNull(r.onSnapshot(snap("t1", TaskStatus.FAILED, StepState.DONE, StepState.FAILED, StepState.CANCELLED)))
        assertNull(r.onSnapshot(QueueSnapshot.EMPTY))
    }

    @Test
    fun recorderIgnoresATaskItDoesNotKnow() {
        val r = HistoryRecorder { 5L }
        assertNull(r.onSnapshot(snap("other", TaskStatus.COMPLETED, StepState.DONE)))
    }

    @Test
    fun rerunThroughTheQueueFinishesTheRemainingSteps() {
        val started = mutableListOf<String>()
        var callback: ((StepResult) -> Unit)? = null
        val executor = object : StepExecutor {
            override fun execute(step: PlannedStep, onResult: (StepResult) -> Unit) { started.add(step.command); callback = onResult }
            override fun answer(optionIndex: Int) {}
            override fun cancel() {}
        }
        val scheduler = object : Scheduler {
            override fun postDelayed(delayMs: Long, task: () -> Unit): Cancellable = Cancellable { }
        }
        val q = TaskQueue(executor, scheduler, { }, TaskTiming(), retry = RetryPolicy.NONE)
        val result = q.submit(item().toRerunDraft("again")!!)
        assertTrue(result is NovaResult.Success)
        assertEquals(listOf("কমান্ড 2"), started)
        assertEquals(2, q.snapshot().current!!.steps.size)
    }
}
EOF

# ---------- Small additions to existing files ----------
# History: keep only the newest rows (a query only, the database version stays 2).
insert_before "$DAO_FILE" '    @Query("DELETE FROM tasks")' '    /** Deletes every record except the newest [keep]. */
    @Query("DELETE FROM tasks WHERE id NOT IN (SELECT id FROM tasks ORDER BY updatedAtMs DESC LIMIT :keep)")
    fun trimTo(keep: Int): Int
' "fun trimTo"

# Home screen: control words first, then the multi-step check; "থামো" also pauses a running task.
replace_line "$HOME_FILE" "                    if (TaskHub.submitIfMultiStep(context, command.rawText)) return" \
  "                    if (TaskHub.handleControl(context, command.rawText) || TaskHub.submitIfMultiStep(context, command.rawText)) return" \
  "TaskHub.handleControl(context, command.rawText)"
replace_line "$HOME_FILE" "                    if (TaskHub.submitIfMultiStep(context, commandText)) return@Button" \
  "                    if (TaskHub.handleControl(context, commandText) || TaskHub.submitIfMultiStep(context, commandText)) return@Button" \
  "TaskHub.handleControl(context, commandText)"
insert_after "$HOME_FILE" "                            statusOverride = context.getString(R.string.home_status_ended_phrase)" \
  "                            TaskHub.pauseIfRunning(context)" "TaskHub.pauseIfRunning(context)"

# Bubble: same control words, "থামো" pauses, info notices are not shown as errors, menu buttons.
replace_line "$SERVICE_FILE" "            if (!TaskHub.submitIfMultiStep(applicationContext, command.rawText)) {" \
  "            if (!TaskHub.handleControl(applicationContext, command.rawText) && !TaskHub.submitIfMultiStep(applicationContext, command.rawText)) {" \
  "TaskHub.handleControl(applicationContext"
replace_line "$SERVICE_FILE" "                is ConversationEnd.StopPhrase -> overlay.hidePanel()" \
  "                is ConversationEnd.StopPhrase -> {
                    overlay.hidePanel()
                    // P25: \"থামো\" also pauses a running task (it can be resumed).
                    TaskHub.pauseIfRunning(applicationContext)
                }" \
  "TaskHub.pauseIfRunning(applicationContext)"
replace_line "$SERVICE_FILE" "                overlay.showStatus(notice, MessageKind.ERROR, STATUS_MS)" \
  "                overlay.showStatus(notice, if (snapshot.noticeIsError) MessageKind.ERROR else MessageKind.INFO, STATUS_MS)
                if (!snapshot.noticeIsError) speakResult(notice)" \
  "snapshot.noticeIsError"
insert_before "$SERVICE_FILE" "        buttons.add(PanelButton(getString(R.string.bub_menu_close)) { stopSelf() })" \
  "        // P25: pause, resume or cancel the running task from the menu.
        TaskHub.state.current?.takeIf { it.isOpen }?.let { task ->
            if (task.status == TaskStatus.PAUSED) {
                buttons.add(PanelButton(getString(R.string.bub_task_resume)) { TaskHub.resume() })
            } else {
                buttons.add(PanelButton(getString(R.string.bub_task_pause)) { TaskHub.pause() })
            }
            buttons.add(PanelButton(getString(R.string.bub_task_cancel)) { TaskHub.cancelCurrent() })
        }" \
  "bub_task_pause)) { TaskHub.pause() }"

# Automation screen: the history card replaces the empty placeholder card.
if ! grep -q -F "TaskHistoryCard" "$AUTO_FILE"; then
  tmp="$(mktemp)"; TMP_FILES+=("$tmp")
  awk '
    { lines[NR] = $0 }
    END {
      i = 1
      while (i <= NR) {
        if (lines[i] == "        NovaInfoCard(" && lines[i+1] ~ /automation_history_title/ && lines[i+2] ~ /automation_history_none/ && lines[i+3] == "        )") { i += 4; continue }
        print lines[i]; i++
      }
    }' "$AUTO_FILE" > "$tmp"
  cat "$tmp" > "$AUTO_FILE"
fi
insert_after "$AUTO_FILE" "        TaskQueueCard()" "        TaskHistoryCard()" "TaskHistoryCard()"
insert_after "$AUTO_FILE" "import com.nova.ai.ui.components.TaskQueueCard" "import com.nova.ai.ui.components.TaskHistoryCard" "import com.nova.ai.ui.components.TaskHistoryCard"

# ---------- Commit and push ----------
git add -A
if git diff --cached --quiet; then
  echo "Nothing new to commit."
else
  git commit -m "P25: task control (stop, pause, resume, rerun) and task history"
  git push
fi

echo "P25 files created and pushed."
