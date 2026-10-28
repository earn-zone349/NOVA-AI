#!/usr/bin/env bash
# NOVA AI - Phase 23 setup script: the task planner and queue (several steps, one after another).
# Additive: new tasks package (splitter, planner, queue, hub), a task card, strings and tests.
# Existing files get only small additions: a "completed" flag on bubble messages, the bubble's
# task progress, the Home and Automation screens, and the Automation Stop button is switched on.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
RES="app/src/main/res"
TEST="app/src/test/java/com/nova/ai"
OUTPUT_FILE="$BASE/bubble/BubbleOutput.kt"
MAPPER_FILE="$BASE/bubble/BubbleOutputMapper.kt"
SERVICE_FILE="$BASE/bubble/NovaBubbleService.kt"
HOME_FILE="$BASE/ui/screens/HomeScreen.kt"
AUTO_FILE="$BASE/ui/screens/AutomationScreen.kt"
UI_STRINGS="$RES/values/strings_ui.xml"

fail() { echo "ERROR: $*" >&2; exit 1; }

TMP_FILES=()
cleanup() { [ ${#TMP_FILES[@]} -eq 0 ] || rm -f "${TMP_FILES[@]}"; }
trap cleanup EXIT

# ---------- helpers ----------
# Number of lines that equal $2 exactly.
count_line() { grep -c -x -F -- "$2" "$1" || true; }

# Adds $3 right after the single line that equals $2. Skips when $4 is already in the file.
insert_after() {
  local file="$1" anchor="$2" text="$3" marker="$4" tmp
  if grep -q -F -- "$marker" "$file"; then return 0; fi
  [ "$(count_line "$file" "$anchor")" = "1" ] || fail "anchor not found exactly once in $file: $anchor"
  tmp="$(mktemp)"; TMP_FILES+=("$tmp")
  A="$anchor" T="$text" awk '{ print } $0 == ENVIRON["A"] { print ENVIRON["T"] }' "$file" > "$tmp"
  cat "$tmp" > "$file"
}

# Adds $3 right before the single line that equals $2. Skips when $4 is already in the file.
insert_before() {
  local file="$1" anchor="$2" text="$3" marker="$4" tmp
  if grep -q -F -- "$marker" "$file"; then return 0; fi
  [ "$(count_line "$file" "$anchor")" = "1" ] || fail "anchor not found exactly once in $file: $anchor"
  tmp="$(mktemp)"; TMP_FILES+=("$tmp")
  A="$anchor" T="$text" awk '$0 == ENVIRON["A"] { print ENVIRON["T"] } { print }' "$file" > "$tmp"
  cat "$tmp" > "$file"
}

# Replaces the single line that equals $2 with $3. Skips when $4 is already in the file.
replace_line() {
  local file="$1" anchor="$2" text="$3" marker="$4" tmp
  if grep -q -F -- "$marker" "$file"; then return 0; fi
  [ "$(count_line "$file" "$anchor")" = "1" ] || fail "anchor not found exactly once in $file: $anchor"
  tmp="$(mktemp)"; TMP_FILES+=("$tmp")
  A="$anchor" T="$text" awk '$0 == ENVIRON["A"] { print ENVIRON["T"]; next } { print }' "$file" > "$tmp"
  cat "$tmp" > "$file"
}

# Stops early unless the anchor is there once (or the marker shows the edit was made before).
need() {
  local file="$1" anchor="$2" marker="$3"
  grep -q -F -- "$marker" "$file" && return 0
  [ "$(count_line "$file" "$anchor")" = "1" ] || fail "anchor missing in $file: $anchor"
}

# ---------- preflight ----------
for required in "$OUTPUT_FILE" "$MAPPER_FILE" "$SERVICE_FILE" "$BASE/bubble/BubbleCommandRouter.kt" \
  "$BASE/bubble/ResourceBubbleTexts.kt" "$BASE/security/EmergencyStop.kt" "$BASE/brain/RuleBasedBrain.kt" \
  "$BASE/voice/LanguageDetector.kt" "$HOME_FILE" "$AUTO_FILE" "$UI_STRINGS" \
  "$TEST/bubble/BubbleOutputMapperTest.kt"; do
  [ -f "$required" ] || fail "$required not found. Run from the repo root after P22 is installed."
done

need "$OUTPUT_FILE" "    data class Message(val text: String, val kind: MessageKind) : BubbleOutput()" "val completed: Boolean"
need "$MAPPER_FILE" "            OutcomeKind.GUIDED, OutcomeKind.HINT -> BubbleOutput.Message(outcome.message, MessageKind.INFO)" "OutcomeKind.GUIDED ->"
need "$SERVICE_FILE" "import com.nova.ai.logging.NovaLogger" "import com.nova.ai.tasks.TaskHub"
need "$SERVICE_FILE" "    private var destroyed: Boolean = false" "private var taskActive"
need "$SERVICE_FILE" "    private val emergencyListener: (Boolean) -> Unit = { _ -> handler.post { onEmergencyChanged() } }" "private val taskListener"
need "$SERVICE_FILE" "            router.handle(command.rawText)" "TaskHub.submitIfMultiStep"
need "$SERVICE_FILE" "        overlay.setState(BubbleStateMapper.map(EmergencyStop.isActive, conversationState, routing))" "routing || taskActive"
need "$SERVICE_FILE" "        EmergencyStop.addListener(emergencyListener)" "TaskHub.addListener(taskListener)"
need "$SERVICE_FILE" "            EmergencyStop.removeListener(emergencyListener)" "TaskHub.removeListener(taskListener)"
need "$HOME_FILE" "import com.nova.ai.ui.components.NovaInfoCard" "import com.nova.ai.tasks.TaskHub"
need "$HOME_FILE" "                    while (transcript.size > TRANSCRIPT_LIMIT) transcript.removeAt(0)" "TaskHub.submitIfMultiStep(context, command.rawText)"
need "$HOME_FILE" "                    statusOverride = receivedText" "TaskHub.submitIfMultiStep(context, commandText)"
need "$HOME_FILE" "        MediaActionCard(controller = mediaController)" "TaskQueueCard(showInput = false)"
need "$AUTO_FILE" "import com.nova.ai.ui.components.NovaInfoCard" "import com.nova.ai.ui.components.TaskQueueCard"
need "$AUTO_FILE" "import com.nova.ai.R" "import com.nova.ai.security.EmergencyStop"
need "$AUTO_FILE" "        // Disabled until the emergency stop is implemented (P22)." "TaskQueueCard()"
need "$AUTO_FILE" "            onClick = { }," "EmergencyStop.isActive"
need "$AUTO_FILE" "            enabled = false," "enabled = true,"

mkdir -p "$BASE/tasks" "$TEST/tasks"

# ---------- 1. TaskModels.kt ----------
cat > "$BASE/tasks/TaskModels.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.core.TaskStatus

/** Where one step of a task is right now. */
enum class StepState { PENDING, RUNNING, WAITING_USER, DONE, FAILED, SKIPPED, CANCELLED }

/**
 * One step of a task: a single spoken command (for example "ভলিউম বাড়াও"). [intentType] is what
 * the rule-based brain understood, so the queue can wait long enough after steps that open an app.
 */
data class PlannedStep(
    val id: String,
    val title: String,
    val command: String,
    val intentType: IntentType
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

    /** The step could not be done. The task stops here. */
    data class Failed(val message: String) : StepResult()

    /** The step needs the user to pick one of the [options] (by its position in the list). */
    data class NeedsUser(val question: String, val options: List<String>) : StepResult()
}

/** The state of one step, for the screens. */
data class StepSnapshot(
    val id: String,
    val title: String,
    val state: StepState,
    val message: String?
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
        it.state == StepState.RUNNING || it.state == StepState.WAITING_USER
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
    val noticeSeq: Int = 0
) {
    companion object {
        /** An empty queue. */
        val EMPTY: QueueSnapshot = QueueSnapshot(current = null, waiting = emptyList(), notice = null)
    }
}
EOF

# ---------- 2. TaskMessages.kt ----------
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

    /** The command has more steps than NOVA runs in one task. */
    fun tooManySteps(max: Int): String = "একবারে সর্বোচ্চ ${max}টি ধাপ করা যায়। কাজ ছোট করে বলুন।"

    /** One part of the command was not understood. Nothing was started. */
    fun unknownPart(part: String): String = "“$part” অংশটা বুঝতে পারিনি। কিছুই শুরু করিনি।"

    /** All steps finished. */
    fun allDone(count: Int): String = "সব ${count}টি ধাপ শেষ।"

    /** A step failed, so the task stopped there. */
    fun stoppedAt(position: Int, total: Int, reason: String): String =
        "${position}/${total} ধাপে আটকে গেছি: $reason"
}
EOF

# ---------- 3. CommandSplitter.kt ----------
cat > "$BASE/tasks/CommandSplitter.kt" <<'EOF'
package com.nova.ai.tasks

import java.util.Locale

/**
 * Cuts one spoken command into its parts at the words that mean "and after that"
 * (তারপর, এরপর, then, and then, after that). Pure logic with no Android classes.
 * Only these clear words split a command, so a normal single command is never cut by mistake.
 */
object CommandSplitter {

    // One-word connectors, written in lower case.
    private val SINGLE: Set<String> = setOf(
        "তারপর", "তারপরে", "এরপর", "এরপরে", "অতঃপর", "then", "afterwards", "afterward"
    )

    // Two-word connectors: first word to the words that may follow it.
    private val DOUBLE: Map<String, Set<String>> = mapOf(
        "তার" to setOf("পর", "পরে"),
        "এর" to setOf("পর", "পরে"),
        "and" to setOf("then"),
        "after" to setOf("that")
    )

    // Little words that are left hanging at the end of a part ("ক্রোম খোলো এবং").
    private val TRAILING: Set<String> = setOf("এবং", "আর", "ও", "and")

    private const val EDGE_MARKS: String = ",.;:!?।\"'“”‘’"

    /** The parts of [text], in order, without the connecting words. Empty if there is nothing to do. */
    fun split(text: String): List<String> {
        val words: List<String> = text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        val parts: MutableList<MutableList<String>> = mutableListOf(mutableListOf())
        var index = 0
        while (index < words.size) {
            val word: String = words[index]
            val key: String = clean(word)
            val nextKey: String? = words.getOrNull(index + 1)?.let { clean(it) }
            when {
                key in SINGLE -> {
                    parts.add(mutableListOf())
                    index += 1
                }
                nextKey != null && DOUBLE[key]?.contains(nextKey) == true -> {
                    parts.add(mutableListOf())
                    index += 2
                }
                else -> {
                    parts.last().add(word)
                    index += 1
                }
            }
        }
        return parts.map { tidy(it) }.filter { it.isNotEmpty() }
    }

    /** True if [text] holds two or more parts. */
    fun isMultiStep(text: String): Boolean = split(text).size >= 2

    private fun clean(word: String): String = word.trim(*EDGE_MARKS.toCharArray()).lowercase(Locale.ROOT)

    // Drops hanging little words and marks at the end of a part, and marks at its edges.
    private fun tidy(words: List<String>): String {
        val kept: MutableList<String> = words.toMutableList()
        while (kept.isNotEmpty() && clean(kept.last()) in TRAILING) kept.removeAt(kept.lastIndex)
        return kept.joinToString(" ").trim().trim(*EDGE_MARKS.toCharArray()).trim()
    }
}
EOF

# ---------- 4. CommandPlanner.kt ----------
cat > "$BASE/tasks/CommandPlanner.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.ErrorCode
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import java.util.UUID

/**
 * Turns a spoken command into a [TaskDraft]: it cuts the command into parts and checks that every
 * part is understood. If one part is not understood the whole plan is refused and nothing starts,
 * so NOVA never does half of a job by surprise. [analyze] gives the meaning of one part (null if unknown).
 * The old TaskPlanner interface (core steps for clicks and typing) stays for the app adapters of later phases.
 */
class CommandPlanner(
    private val analyze: (String) -> NovaIntent?,
    private val newId: () -> String = { "task-" + UUID.randomUUID().toString().take(8) }
) {

    /** True if [text] has two or more parts, so it should run as a task. */
    fun isMultiStep(text: String): Boolean = CommandSplitter.isMultiStep(text)

    /** Builds the plan for [text]. A failure result carries a Bangla message. */
    fun plan(text: String): NovaResult<TaskDraft> {
        val parts: List<String> = CommandSplitter.split(text)
        if (parts.isEmpty()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, TaskMessages.MSG_EMPTY)
        }
        if (parts.size > MAX_STEPS) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, TaskMessages.tooManySteps(MAX_STEPS))
        }

        val steps: MutableList<PlannedStep> = mutableListOf()
        for ((position, part) in parts.withIndex()) {
            val intent: NovaIntent? = try {
                analyze(part)
            } catch (e: Exception) {
                null
            }
            if (intent == null || intent.type == IntentType.UNKNOWN) {
                return NovaResult.failure(ErrorCode.INVALID_INPUT, TaskMessages.unknownPart(part))
            }
            steps.add(PlannedStep(id = "s${position + 1}", title = part, command = part, intentType = intent.type))
        }
        return NovaResult.Success(TaskDraft(id = newId(), title = shorten(text), steps = steps))
    }

    private fun shorten(text: String): String {
        val single: String = text.trim().replace(Regex("\\s+"), " ")
        return if (single.length <= MAX_TITLE) single else single.take(MAX_TITLE - 1) + "…"
    }

    companion object {
        /** The most steps one task may have. */
        const val MAX_STEPS: Int = 8

        private const val MAX_TITLE: Int = 60
    }
}
EOF

# ---------- 5. TaskQueue.kt ----------
cat > "$BASE/tasks/TaskQueue.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.ErrorCode
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaResult
import com.nova.ai.core.TaskStatus

/** A timer that can be stopped. */
fun interface Cancellable {
    fun cancel()
}

/** Runs a piece of work after a delay. The phone uses the main thread; tests use a fake clock. */
interface Scheduler {
    fun postDelayed(delayMs: Long, task: () -> Unit): Cancellable
}

/** Carries out one step. The queue talks to the phone only through this. */
interface StepExecutor {
    /**
     * Starts [step]. [onResult] is called when the step has an outcome. It may be called once with
     * [StepResult.NeedsUser] and again, after [answer], with the final outcome.
     */
    fun execute(step: PlannedStep, onResult: (StepResult) -> Unit)

    /** The user picked option number [optionIndex] of the last question. */
    fun answer(optionIndex: Int)

    /** Stops whatever the executor is doing and forgets the step. */
    fun cancel()
}

/** The waiting times of the queue, in milliseconds. */
data class TaskTiming(
    val gapMs: Long = 500L,
    val settleAfterLaunchMs: Long = 1500L,
    val stepTimeoutMs: Long = 20_000L,
    val questionTimeoutMs: Long = 60_000L,
    val betweenTasksMs: Long = 1500L
)

/**
 * Runs tasks one after another. Each task is a list of steps that run in order; the queue waits
 * after a step (longer after one that opens an app), watches every step with a timeout, asks the
 * user when a step needs an answer, and stops the task at the first step that fails (the steps
 * after it are skipped). More tasks can wait in line. Pause stops the task before its next step.
 * Use from one thread only (the main thread on the phone). Logic only, no Android classes.
 */
class TaskQueue(
    private val executor: StepExecutor,
    private val scheduler: Scheduler,
    private val onChanged: (QueueSnapshot) -> Unit,
    private val timing: TaskTiming = TaskTiming(),
    private val log: (String) -> Unit = {}
) : TaskControl {

    private class ActiveTask(val draft: TaskDraft) {
        val states: MutableList<StepState> = MutableList(draft.steps.size) { StepState.PENDING }
        val messages: MutableList<String?> = MutableList(draft.steps.size) { null }
        var index: Int = 0
        var status: TaskStatus = TaskStatus.RUNNING
        var question: PendingQuestion? = null
        var resumePending: Boolean = false
        var stepOpen: Boolean = false
        var summary: String? = null
    }

    private var active: ActiveTask? = null
    private var finished: TaskSnapshot? = null
    private val waiting: ArrayDeque<TaskDraft> = ArrayDeque()

    // Every started step gets a new token; an answer that arrives with an old token is ignored.
    private var token: Long = 0L
    private var stepTimer: Cancellable? = null
    private var nextStepTimer: Cancellable? = null
    private var nextTaskTimer: Cancellable? = null

    // ---------------------------------------------------------------- what the screens read

    /** The queue as it is now. */
    fun snapshot(): QueueSnapshot = QueueSnapshot(
        current = active?.let { snapshotOf(it) } ?: finished,
        waiting = waiting.map { it.title }
    )

    override fun status(taskId: String): TaskStatus? = when {
        active?.draft?.id == taskId -> active?.status
        waiting.any { it.id == taskId } -> TaskStatus.PENDING
        finished?.id == taskId -> finished?.status
        else -> null
    }

    // ---------------------------------------------------------------- commands

    /** Adds [draft] to the queue. It starts at once if nothing is running. Returns the task id. */
    override fun submit(draft: TaskDraft): NovaResult<String> {
        if (draft.steps.isEmpty()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, TaskMessages.MSG_EMPTY)
        }
        if (waiting.size >= MAX_WAITING) {
            return NovaResult.failure(ErrorCode.TEMPORARY_FAILURE, TaskMessages.MSG_QUEUE_FULL)
        }
        if (active == null && nextTaskTimer == null) {
            start(draft)
        } else {
            waiting.addLast(draft)
            changed()
        }
        return NovaResult.Success(draft.id)
    }

    /** Stops the task before its next step. The step that is running now still finishes. */
    override fun pause(taskId: String): NovaResult<Unit> {
        val task: ActiveTask = active?.takeIf { it.draft.id == taskId }
            ?: return NovaResult.failure(ErrorCode.NOT_FOUND, TaskMessages.MSG_NOT_FOUND)
        if (task.status != TaskStatus.RUNNING) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, TaskMessages.MSG_CANNOT_PAUSE)
        }
        task.status = TaskStatus.PAUSED
        changed()
        return NovaResult.Success(Unit)
    }

    /** Lets a paused task go on. */
    override fun resume(taskId: String): NovaResult<Unit> {
        val task: ActiveTask = active?.takeIf { it.draft.id == taskId }
            ?: return NovaResult.failure(ErrorCode.NOT_FOUND, TaskMessages.MSG_NOT_FOUND)
        if (task.status != TaskStatus.PAUSED) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, TaskMessages.MSG_CANNOT_RESUME)
        }
        task.status = TaskStatus.RUNNING
        changed()
        if (task.resumePending) {
            task.resumePending = false
            proceed()
        }
        return NovaResult.Success(Unit)
    }

    /** Cancels a running task, or removes a waiting one. */
    override fun cancel(taskId: String): NovaResult<Unit> {
        if (active?.draft?.id == taskId) {
            cancelActive(TaskMessages.MSG_CANCELLED)
            return NovaResult.Success(Unit)
        }
        if (waiting.removeAll { it.id == taskId }) {
            changed()
            return NovaResult.Success(Unit)
        }
        return NovaResult.failure(ErrorCode.NOT_FOUND, TaskMessages.MSG_NOT_FOUND)
    }

    /** Cancels the running task and empties the line. */
    override fun cancelAll() {
        val hadWaiting: Boolean = waiting.isNotEmpty()
        waiting.clear()
        nextTaskTimer?.cancel()
        nextTaskTimer = null
        if (active != null) {
            cancelActive(TaskMessages.MSG_CANCELLED)
        } else if (hadWaiting) {
            changed()
        }
    }

    /** The user picked option number [optionIndex] of the question the task waits on. */
    fun answer(optionIndex: Int): NovaResult<Unit> {
        val task: ActiveTask = active ?: return NovaResult.failure(ErrorCode.NOT_FOUND, TaskMessages.MSG_NO_QUESTION)
        val question: PendingQuestion = task.question
            ?: return NovaResult.failure(ErrorCode.INVALID_INPUT, TaskMessages.MSG_NO_QUESTION)
        if (optionIndex !in question.options.indices) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, TaskMessages.MSG_BAD_CHOICE)
        }
        task.question = null
        task.states[task.index] = StepState.RUNNING
        armStepTimer(timing.stepTimeoutMs)
        changed()
        try {
            executor.answer(optionIndex)
        } catch (e: Exception) {
            log("answer failed: ${e.javaClass.simpleName}")
            failTask(TaskMessages.MSG_START_FAILED)
        }
        return NovaResult.Success(Unit)
    }

    /** The user closes the result of the last task. */
    fun dismissFinished() {
        if (finished != null) {
            finished = null
            changed()
        }
    }

    // ---------------------------------------------------------------- running

    private fun start(draft: TaskDraft) {
        finished = null
        val task = ActiveTask(draft)
        active = task
        log("task started: ${draft.id}, ${draft.steps.size} steps")
        runStep(0)
    }

    private fun runStep(index: Int) {
        val task: ActiveTask = active ?: return
        task.index = index
        task.states[index] = StepState.RUNNING
        task.stepOpen = true
        token += 1
        val myToken: Long = token
        armStepTimer(timing.stepTimeoutMs)
        changed()
        try {
            executor.execute(task.draft.steps[index]) { result -> onResult(myToken, result) }
        } catch (e: Exception) {
            log("step start failed: ${e.javaClass.simpleName}")
            if (myToken == token) failTask(TaskMessages.MSG_START_FAILED)
        }
    }

    private fun onResult(myToken: Long, result: StepResult) {
        val task: ActiveTask = active ?: return
        if (myToken != token || !task.stepOpen) return
        when (result) {
            is StepResult.Done -> {
                task.stepOpen = false
                disarmStepTimer()
                task.states[task.index] = StepState.DONE
                task.messages[task.index] = result.message
                changed()
                scheduleNext(task)
            }
            is StepResult.Failed -> failTask(result.message)
            is StepResult.NeedsUser -> {
                if (result.options.isEmpty()) {
                    failTask(result.question)
                    return
                }
                task.states[task.index] = StepState.WAITING_USER
                task.question = PendingQuestion(result.question, result.options)
                armStepTimer(timing.questionTimeoutMs, onQuestionTimeout = true)
                changed()
            }
        }
    }

    // After a step: finish the task, or wait a moment and go on (longer after a step that opens an app).
    private fun scheduleNext(task: ActiveTask) {
        if (task.index >= task.draft.steps.lastIndex) {
            task.summary = TaskMessages.allDone(task.draft.steps.size)
            finish(task, TaskStatus.COMPLETED)
            return
        }
        val step: PlannedStep = task.draft.steps[task.index]
        val delay: Long = if (step.intentType in LAUNCH_TYPES) timing.settleAfterLaunchMs else timing.gapMs
        nextStepTimer?.cancel()
        nextStepTimer = scheduler.postDelayed(delay) { proceed() }
    }

    private fun proceed() {
        nextStepTimer = null
        val task: ActiveTask = active ?: return
        if (task.status == TaskStatus.PAUSED) {
            task.resumePending = true
            return
        }
        runStep(task.index + 1)
    }

    private fun failTask(reason: String) {
        val task: ActiveTask = active ?: return
        task.stepOpen = false
        task.states[task.index] = StepState.FAILED
        task.messages[task.index] = reason
        for (i in task.index + 1 until task.states.size) task.states[i] = StepState.SKIPPED
        task.summary = TaskMessages.stoppedAt(task.index + 1, task.draft.steps.size, reason)
        finish(task, TaskStatus.FAILED)
    }

    private fun cancelActive(reason: String) {
        val task: ActiveTask = active ?: return
        try {
            executor.cancel()
        } catch (e: Exception) {
            log("executor cancel failed: ${e.javaClass.simpleName}")
        }
        for (i in task.states.indices) {
            if (task.states[i] == StepState.PENDING || task.states[i] == StepState.RUNNING ||
                task.states[i] == StepState.WAITING_USER
            ) {
                task.states[i] = StepState.CANCELLED
            }
        }
        task.summary = reason
        finish(task, TaskStatus.CANCELLED)
    }

    private fun finish(task: ActiveTask, status: TaskStatus) {
        disarmStepTimer()
        nextStepTimer?.cancel()
        nextStepTimer = null
        token += 1
        task.status = status
        task.question = null
        task.stepOpen = false
        finished = snapshotOf(task)
        active = null
        log("task finished: ${task.draft.id} $status")
        changed()
        if (waiting.isNotEmpty()) {
            // The result stays visible for a moment before the next task takes its place.
            nextTaskTimer = scheduler.postDelayed(timing.betweenTasksMs) {
                nextTaskTimer = null
                waiting.removeFirstOrNull()?.let { start(it) }
            }
        }
    }

    // ---------------------------------------------------------------- timers

    private fun armStepTimer(delayMs: Long, onQuestionTimeout: Boolean = false) {
        stepTimer?.cancel()
        val timerToken: Long = token
        stepTimer = scheduler.postDelayed(delayMs) {
            if (timerToken != token || active == null) return@postDelayed
            stepTimer = null
            if (onQuestionTimeout) {
                cancelActive(TaskMessages.MSG_QUESTION_TIMEOUT)
            } else {
                try {
                    executor.cancel()
                } catch (e: Exception) {
                    log("executor cancel failed: ${e.javaClass.simpleName}")
                }
                failTask(TaskMessages.MSG_STEP_TIMEOUT)
            }
        }
    }

    private fun disarmStepTimer() {
        stepTimer?.cancel()
        stepTimer = null
    }

    // ---------------------------------------------------------------- snapshots

    private fun changed() {
        try {
            onChanged(snapshot())
        } catch (e: Exception) {
            log("listener failed: ${e.javaClass.simpleName}")
        }
    }

    private fun snapshotOf(task: ActiveTask): TaskSnapshot = TaskSnapshot(
        id = task.draft.id,
        title = task.draft.title,
        status = task.status,
        steps = task.draft.steps.mapIndexed { i, step ->
            StepSnapshot(step.id, step.title, task.states[i], task.messages[i])
        },
        question = task.question,
        summary = task.summary
    )

    companion object {
        /** How many tasks may wait behind the running one. */
        const val MAX_WAITING: Int = 5

        // Steps of these kinds open an app or a page, so the next step waits longer.
        private val LAUNCH_TYPES: Set<IntentType> = setOf(IntentType.OPEN_APP, IntentType.WEB_SEARCH, IntentType.NAVIGATE)
    }
}

/** What the screens and the hub may ask of a queue. */
interface TaskControl {
    fun submit(draft: TaskDraft): NovaResult<String>
    fun pause(taskId: String): NovaResult<Unit>
    fun resume(taskId: String): NovaResult<Unit>
    fun cancel(taskId: String): NovaResult<Unit>
    fun cancelAll()
    fun status(taskId: String): TaskStatus?
}
EOF

# ---------- 6. StepResultMapper.kt ----------
cat > "$BASE/tasks/StepResultMapper.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.bubble.BubbleOutput

/**
 * Turns what a command controller reported (as a [BubbleOutput]) into the outcome of a task step.
 * A message that says the job is done (or that the right screen was opened for the user) is
 * success; every other message (not found, needs a permission, not understood, error) stops the task.
 * A question is handed to the user.
 */
internal object StepResultMapper {

    /** The step result for [output], or null if there is nothing yet. */
    fun fromOutput(output: BubbleOutput): StepResult? = when (output) {
        is BubbleOutput.None -> null
        is BubbleOutput.Message ->
            if (output.completed) StepResult.Done(output.text) else StepResult.Failed(output.text)
        is BubbleOutput.Decision ->
            StepResult.NeedsUser(output.question, output.options.map { it.label })
        is BubbleOutput.NeedsApp -> StepResult.Failed(output.text)
    }
}
EOF

# ---------- 7. HandlerScheduler.kt ----------
cat > "$BASE/tasks/HandlerScheduler.kt" <<'EOF'
package com.nova.ai.tasks

import android.os.Handler

/** A [Scheduler] that runs its work on the thread of [handler] (the main thread on the phone). */
class HandlerScheduler(private val handler: Handler) : Scheduler {

    override fun postDelayed(delayMs: Long, task: () -> Unit): Cancellable {
        val runnable = Runnable { task() }
        handler.postDelayed(runnable, delayMs)
        return Cancellable { handler.removeCallbacks(runnable) }
    }
}
EOF

# ---------- 8. CommandStepExecutor.kt ----------
cat > "$BASE/tasks/CommandStepExecutor.kt" <<'EOF'
package com.nova.ai.tasks

import android.content.Context
import com.nova.ai.bubble.BubbleCommandRouter
import com.nova.ai.bubble.BubbleOutput
import com.nova.ai.bubble.ResourceBubbleTexts
import kotlinx.coroutines.CoroutineScope

/**
 * Runs one step of a task as a spoken command through the same five command controllers the Home
 * screen and the bubble use, and reports what happened. A question from a controller (which app,
 * which number, call now) is passed on to the user and answered later through [answer].
 * Use from the main thread.
 */
internal class CommandStepExecutor(
    context: Context,
    scope: CoroutineScope
) : StepExecutor {

    private var callback: ((StepResult) -> Unit)? = null
    private var decision: BubbleOutput.Decision? = null

    private val router = BubbleCommandRouter(
        context = context,
        scope = scope,
        texts = ResourceBubbleTexts(context),
        onOutput = { output -> handleOutput(output) },
        onBusyChanged = { }
    )

    override fun execute(step: PlannedStep, onResult: (StepResult) -> Unit) {
        callback = onResult
        decision = null
        router.handle(step.command)
    }

    override fun answer(optionIndex: Int) {
        val question: BubbleOutput.Decision = decision ?: return
        val option = question.options.getOrNull(optionIndex) ?: return
        decision = null
        router.choose(question, option)
    }

    override fun cancel() {
        callback = null
        decision = null
        router.cancel()
        router.dismissQuestion()
    }

    /** Releases the controllers. Call when the executor is no longer needed. */
    fun release() {
        cancel()
        router.release()
    }

    private fun handleOutput(output: BubbleOutput) {
        val result: StepResult = StepResultMapper.fromOutput(output) ?: return
        val target: ((StepResult) -> Unit)? = callback
        if (output is BubbleOutput.Decision) {
            decision = output
        } else {
            decision = null
            callback = null
        }
        target?.invoke(result)
    }
}
EOF

# ---------- 9. TaskHub.kt ----------
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
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.security.EmergencyStop
import com.nova.ai.voice.LanguageDetector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
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

    private var queue: TaskQueue? = null
    private var planner: CommandPlanner? = null
    private var notice: String? = null
    private var noticeSeq: Int = 0

    /** Gets everything ready. Safe to call many times. */
    fun init(context: Context) {
        if (queue != null) return
        val appContext: Context = context.applicationContext
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        queue = TaskQueue(
            executor = CommandStepExecutor(appContext, scope),
            scheduler = HandlerScheduler(mainHandler),
            onChanged = { snapshot -> publish(snapshot) },
            log = { message -> NovaLogger.i(TAG, message) }
        )
        planner = CommandPlanner(analyze = { part -> analyze(part) })
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

    /** Closes the result of the last task and the notice. */
    fun dismiss() {
        notice = null
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

    private fun setNotice(message: String?) {
        notice = message
        if (message != null) noticeSeq += 1
        publish(queue?.snapshot() ?: QueueSnapshot.EMPTY)
    }

    private fun publish(snapshot: QueueSnapshot) {
        val merged: QueueSnapshot = snapshot.copy(notice = notice, noticeSeq = noticeSeq)
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

# ---------- 10. TaskQueueCard.kt ----------
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
                    color = MaterialTheme.colorScheme.error
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

private fun stepLine(step: StepSnapshot): String =
    if (step.message.isNullOrBlank() || step.state == StepState.DONE) step.title else "${step.title} — ${step.message}"

private fun icon(state: StepState): String = when (state) {
    StepState.PENDING -> "○"
    StepState.RUNNING -> "▶"
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

# ---------- 11. strings_p23.xml ----------
cat > "$RES/values/strings_p23.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Task card (Automation and Home screens) -->
    <string name="tsk_card_title">ধাপে ধাপে কাজ</string>
    <string name="tsk_card_note">একটি কমান্ডে কয়েকটি কাজ বলুন, “তারপর” দিয়ে আলাদা করে। যেমন: ক্রোম খোলো তারপর ভলিউম বাড়াও তারপর টর্চ জ্বালাও। নোভা একটার পর একটা করবে, কোনো অংশ না বুঝলে কিছুই শুরু করবে না।</string>
    <string name="tsk_input_label">কয়েকটি কাজ (তারপর দিয়ে আলাদা)</string>
    <string name="tsk_run">চালাও</string>
    <string name="tsk_progress">%1$d/%2$d ধাপ শেষ</string>
    <string name="tsk_waiting">লাইনে অপেক্ষায়: %1$s</string>
    <string name="tsk_pause">থামাও</string>
    <string name="tsk_resume">চালিয়ে যাও</string>
    <string name="tsk_cancel">বাতিল</string>
    <string name="tsk_cancel_all">সব বাতিল</string>
    <string name="tsk_dismiss">ঠিক আছে</string>
    <string name="tsk_status_pending">অপেক্ষায়</string>
    <string name="tsk_status_running">চলছে</string>
    <string name="tsk_status_paused">থামানো আছে</string>
    <string name="tsk_status_completed">শেষ</string>
    <string name="tsk_status_failed">ব্যর্থ</string>
    <string name="tsk_status_cancelled">বাতিল</string>

    <!-- Bubble: task progress -->
    <string name="bub_task_progress">⏳ %1$d/%2$d · %3$s</string>
    <string name="bub_task_paused">⏸ থামানো আছে · %1$d/%2$d</string>
    <string name="bub_task_cancel">কাজ বাতিল করুন</string>
</resources>
EOF

# ---------- 12. CommandSplitterTest.kt ----------
cat > "$TEST/tasks/CommandSplitterTest.kt" <<'EOF'
package com.nova.ai.tasks

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests how a command is cut into parts. Plain JVM test, no phone needed. */
class CommandSplitterTest {

    @Test
    fun banglaConnectorSplitsIntoParts() {
        assertEquals(
            listOf("ক্রোম খোলো", "ভলিউম বাড়াও", "টর্চ জ্বালাও"),
            CommandSplitter.split("ক্রোম খোলো তারপর ভলিউম বাড়াও তারপর টর্চ জ্বালাও")
        )
    }

    @Test
    fun otherBanglaConnectorsWork() {
        assertEquals(listOf("ক্রোম খোলো", "গান চালাও"), CommandSplitter.split("ক্রোম খোলো এরপর গান চালাও"))
        assertEquals(listOf("ক্রোম খোলো", "গান চালাও"), CommandSplitter.split("ক্রোম খোলো তারপরে গান চালাও"))
        assertEquals(listOf("ক্রোম খোলো", "গান চালাও"), CommandSplitter.split("ক্রোম খোলো তার পর গান চালাও"))
        assertEquals(listOf("ক্রোম খোলো", "গান চালাও"), CommandSplitter.split("ক্রোম খোলো এর পর গান চালাও"))
    }

    @Test
    fun englishConnectorsWorkInAnyCase() {
        assertEquals(listOf("open chrome", "turn on wifi"), CommandSplitter.split("open chrome then turn on wifi"))
        assertEquals(listOf("open chrome", "turn on wifi"), CommandSplitter.split("open chrome and then turn on wifi"))
        assertEquals(listOf("Open Chrome", "turn on wifi"), CommandSplitter.split("Open Chrome After That turn on wifi"))
        assertEquals(listOf("open chrome", "turn on wifi"), CommandSplitter.split("open chrome THEN turn on wifi"))
    }

    @Test
    fun commasAndHangingWordsAreRemoved() {
        assertEquals(
            listOf("ক্রোম খোলো", "ভলিউম বাড়াও"),
            CommandSplitter.split("ক্রোম খোলো, এবং তারপর, ভলিউম বাড়াও।")
        )
        assertEquals(listOf("open chrome", "play music"), CommandSplitter.split("open chrome, and then, play music."))
    }

    @Test
    fun aSingleCommandIsNeverCut() {
        assertEquals(listOf("ক্রোম খোলো"), CommandSplitter.split("ক্রোম খোলো"))
        assertEquals(listOf("রহিমকে ফোন করো"), CommandSplitter.split("রহিমকে ফোন করো"))
        assertFalse(CommandSplitter.isMultiStep("ক্রোম খুলে ভিডিও সার্চ করো"))
    }

    @Test
    fun connectorsAtTheEdgesAndEmptyPartsAreIgnored() {
        assertEquals(listOf("ক্রোম খোলো"), CommandSplitter.split("তারপর ক্রোম খোলো তারপর"))
        assertEquals(listOf("ক্রোম খোলো", "গান চালাও"), CommandSplitter.split("ক্রোম খোলো তারপর তারপর গান চালাও"))
        assertTrue(CommandSplitter.split("   ").isEmpty())
        assertTrue(CommandSplitter.split("তারপর").isEmpty())
    }

    @Test
    fun extraSpacesAreHandled() {
        assertEquals(listOf("a b", "c"), CommandSplitter.split("  a   b   then    c  "))
    }

    @Test
    fun multiStepNeedsTwoParts() {
        assertTrue(CommandSplitter.isMultiStep("ক্রোম খোলো তারপর গান চালাও"))
        assertFalse(CommandSplitter.isMultiStep("ক্রোম খোলো তারপর"))
    }
}
EOF

# ---------- 13. CommandPlannerTest.kt ----------
cat > "$TEST/tasks/CommandPlannerTest.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.ErrorCode
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests how a spoken command becomes a task. Plain JVM test. */
class CommandPlannerTest {

    // A tiny fake brain: knows a few words.
    private val known: Map<String, IntentType> = mapOf(
        "open chrome" to IntentType.OPEN_APP,
        "volume up" to IntentType.SYSTEM_ACTION,
        "call rahim" to IntentType.MAKE_CALL,
        "mumble" to IntentType.UNKNOWN
    )

    private val planner = CommandPlanner(
        analyze = { part -> known[part]?.let { NovaIntent(it, emptyMap(), 0.9f) } },
        newId = { "task-1" }
    )

    private fun draftOf(result: NovaResult<TaskDraft>): TaskDraft = when (result) {
        is NovaResult.Success -> result.value
        is NovaResult.Failure -> throw AssertionError("Expected a plan but got: ${result.error.message}")
    }

    private fun failureOf(result: NovaResult<TaskDraft>): com.nova.ai.core.NovaError = when (result) {
        is NovaResult.Failure -> result.error
        is NovaResult.Success -> throw AssertionError("Expected a failure")
    }

    @Test
    fun threePartsBecomeThreeStepsInOrder() {
        val draft = draftOf(planner.plan("open chrome then volume up then call rahim"))
        assertEquals("task-1", draft.id)
        assertEquals(listOf("s1", "s2", "s3"), draft.steps.map { it.id })
        assertEquals(listOf("open chrome", "volume up", "call rahim"), draft.steps.map { it.command })
        assertEquals(
            listOf(IntentType.OPEN_APP, IntentType.SYSTEM_ACTION, IntentType.MAKE_CALL),
            draft.steps.map { it.intentType }
        )
    }

    @Test
    fun oneUnknownPartRefusesTheWholePlanAndNamesIt() {
        val error = failureOf(planner.plan("open chrome then mumble then volume up"))
        assertEquals(ErrorCode.INVALID_INPUT, error.code)
        assertTrue(error.message.contains("mumble"))
    }

    @Test
    fun aPartTheBrainDoesNotKnowAtAllIsRefused() {
        val error = failureOf(planner.plan("open chrome then something else"))
        assertTrue(error.message.contains("something else"))
    }

    @Test
    fun aBrainThatThrowsIsTreatedAsUnknown() {
        val crashing = CommandPlanner(analyze = { throw IllegalStateException("boom") })
        val error = failureOf(crashing.plan("open chrome then volume up"))
        assertEquals(ErrorCode.INVALID_INPUT, error.code)
    }

    @Test
    fun emptyCommandIsRefused() {
        assertEquals(ErrorCode.INVALID_INPUT, failureOf(planner.plan("  ")).code)
        assertEquals(ErrorCode.INVALID_INPUT, failureOf(planner.plan("then")).code)
    }

    @Test
    fun tooManyStepsAreRefused() {
        val text = (1..9).joinToString(" then ") { "volume up" }
        val error = failureOf(planner.plan(text))
        assertEquals(ErrorCode.INVALID_INPUT, error.code)
        assertTrue(error.message.contains(CommandPlanner.MAX_STEPS.toString()))
    }

    @Test
    fun exactlyTheMaximumIsAccepted() {
        val text = (1..CommandPlanner.MAX_STEPS).joinToString(" then ") { "volume up" }
        assertEquals(CommandPlanner.MAX_STEPS, draftOf(planner.plan(text)).steps.size)
    }

    @Test
    fun aSingleKnownCommandMakesAOneStepPlanButIsNotMultiStep() {
        assertEquals(1, draftOf(planner.plan("open chrome")).steps.size)
        assertTrue(!planner.isMultiStep("open chrome"))
        assertTrue(planner.isMultiStep("open chrome then volume up"))
    }

    @Test
    fun longTitlesAreShortened() {
        val long = "open chrome then " + "volume up then ".repeat(3) + "volume up"
        val title = draftOf(planner.plan(long)).title
        assertNotNull(title)
        assertTrue(title.length <= 60)
    }

    @Test
    fun generatedIdsDifferBetweenPlans() {
        val real = CommandPlanner(analyze = { NovaIntent(IntentType.OPEN_APP, emptyMap(), 1f) })
        val a = draftOf(real.plan("x then y")).id
        val b = draftOf(real.plan("x then y")).id
        assertTrue(a != b)
    }
}
EOF

# ---------- 14. TaskQueueTest.kt ----------
cat > "$TEST/tasks/TaskQueueTest.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.ErrorCode
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaResult
import com.nova.ai.core.TaskStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests the task queue with a fake clock and a fake phone. Plain JVM test. */
class TaskQueueTest {

    /** A clock that only moves when the test says so. */
    private class FakeScheduler : Scheduler {
        private class Item(val at: Long, val task: () -> Unit) { var cancelled = false }
        private val items = mutableListOf<Item>()
        var now = 0L

        override fun postDelayed(delayMs: Long, task: () -> Unit): Cancellable {
            val item = Item(now + delayMs, task)
            items.add(item)
            return Cancellable { item.cancelled = true }
        }

        fun advance(ms: Long) {
            val target = now + ms
            while (true) {
                val next = items.filter { !it.cancelled && it.at <= target }.minByOrNull { it.at } ?: break
                items.remove(next)
                now = next.at
                next.task()
            }
            now = target
        }

        fun pendingCount() = items.count { !it.cancelled }
    }

    /** A phone that answers only when the test tells it to. */
    private class FakeExecutor : StepExecutor {
        val started = mutableListOf<String>()
        val answers = mutableListOf<Int>()
        var cancels = 0
        var throwOnExecute = false
        private var callback: ((StepResult) -> Unit)? = null

        override fun execute(step: PlannedStep, onResult: (StepResult) -> Unit) {
            if (throwOnExecute) throw IllegalStateException("boom")
            started.add(step.id)
            callback = onResult
        }

        override fun answer(optionIndex: Int) { answers.add(optionIndex) }
        override fun cancel() { cancels += 1 }
        fun reply(result: StepResult) { callback?.invoke(result) }
    }

    private val clock = FakeScheduler()
    private val executor = FakeExecutor()
    private val snapshots = mutableListOf<QueueSnapshot>()
    private val timing = TaskTiming(
        gapMs = 100, settleAfterLaunchMs = 1000, stepTimeoutMs = 5000, questionTimeoutMs = 20000, betweenTasksMs = 300
    )
    private val queue = TaskQueue(executor, clock, { snapshots.add(it) }, timing)

    private fun step(n: Int, type: IntentType = IntentType.SYSTEM_ACTION) =
        PlannedStep("s$n", "step $n", "cmd $n", type)

    private fun draft(id: String, vararg types: IntentType) =
        TaskDraft(id, "task $id", types.mapIndexed { i, t -> step(i + 1, t) })

    private fun threeSteps(id: String = "t1") =
        draft(id, IntentType.SYSTEM_ACTION, IntentType.SYSTEM_ACTION, IntentType.SYSTEM_ACTION)

    private fun current() = queue.snapshot().current!!

    @Test
    fun threeStepsRunInOrderAndTheTaskCompletes() {
        queue.submit(threeSteps())
        assertEquals(listOf("s1"), executor.started)
        executor.reply(StepResult.Done("one"))
        assertEquals(listOf("s1"), executor.started)          // waits for the gap
        clock.advance(100)
        assertEquals(listOf("s1", "s2"), executor.started)
        executor.reply(StepResult.Done("two"))
        clock.advance(100)
        executor.reply(StepResult.Done("three"))
        val task = current()
        assertEquals(TaskStatus.COMPLETED, task.status)
        assertEquals(3, task.doneCount)
        assertEquals(TaskMessages.allDone(3), task.summary)
        assertEquals(listOf("one", "two", "three"), task.steps.map { it.message })
    }

    @Test
    fun aStepThatOpensAnAppWaitsLongerBeforeTheNextOne() {
        queue.submit(draft("t1", IntentType.OPEN_APP, IntentType.SYSTEM_ACTION))
        executor.reply(StepResult.Done("opened"))
        clock.advance(999)
        assertEquals(listOf("s1"), executor.started)
        clock.advance(1)
        assertEquals(listOf("s1", "s2"), executor.started)
    }

    @Test
    fun aFailedStepStopsTheTaskAndSkipsTheRest() {
        queue.submit(threeSteps())
        executor.reply(StepResult.Done("one"))
        clock.advance(100)
        executor.reply(StepResult.Failed("no such app"))
        val task = current()
        assertEquals(TaskStatus.FAILED, task.status)
        assertEquals(
            listOf(StepState.DONE, StepState.FAILED, StepState.SKIPPED),
            task.steps.map { it.state }
        )
        assertEquals(TaskMessages.stoppedAt(2, 3, "no such app"), task.summary)
        clock.advance(10_000)
        assertEquals(listOf("s1", "s2"), executor.started)
    }

    @Test
    fun aStepThatNeverAnswersTimesOut() {
        queue.submit(threeSteps())
        clock.advance(5000)
        val task = current()
        assertEquals(TaskStatus.FAILED, task.status)
        assertEquals(TaskMessages.MSG_STEP_TIMEOUT, task.steps[0].message)
        assertEquals(1, executor.cancels)
    }

    @Test
    fun aQuestionWaitsForTheUserThenGoesOn() {
        queue.submit(threeSteps())
        executor.reply(StepResult.NeedsUser("which?", listOf("A", "B")))
        assertEquals(StepState.WAITING_USER, current().steps[0].state)
        assertEquals("which?", current().question?.text)
        // No step timeout while waiting for the user (5 s timeout, 20 s question time).
        clock.advance(6000)
        assertEquals(TaskStatus.RUNNING, current().status)

        assertTrue(queue.answer(1) is NovaResult.Success)
        assertEquals(listOf(1), executor.answers)
        assertNull(current().question)
        assertEquals(StepState.RUNNING, current().steps[0].state)
        executor.reply(StepResult.Done("opened B"))
        clock.advance(100)
        assertEquals(listOf("s1", "s2"), executor.started)
    }

    @Test
    fun anUnansweredQuestionCancelsTheTask() {
        queue.submit(threeSteps())
        executor.reply(StepResult.NeedsUser("which?", listOf("A")))
        clock.advance(20000)
        val task = current()
        assertEquals(TaskStatus.CANCELLED, task.status)
        assertEquals(TaskMessages.MSG_QUESTION_TIMEOUT, task.summary)
        assertEquals(1, executor.cancels)
    }

    @Test
    fun answeringWithoutAQuestionOrWithABadNumberFails() {
        assertEquals(ErrorCode.NOT_FOUND, (queue.answer(0) as NovaResult.Failure).error.code)
        queue.submit(threeSteps())
        assertEquals(ErrorCode.INVALID_INPUT, (queue.answer(0) as NovaResult.Failure).error.code)
        executor.reply(StepResult.NeedsUser("which?", listOf("A", "B")))
        assertEquals(ErrorCode.INVALID_INPUT, (queue.answer(5) as NovaResult.Failure).error.code)
        assertEquals(ErrorCode.INVALID_INPUT, (queue.answer(-1) as NovaResult.Failure).error.code)
        assertTrue(executor.answers.isEmpty())
    }

    @Test
    fun aQuestionWithoutOptionsFailsTheStep() {
        queue.submit(threeSteps())
        executor.reply(StepResult.NeedsUser("nothing to pick", emptyList()))
        assertEquals(TaskStatus.FAILED, current().status)
    }

    @Test
    fun cancelStopsTheRunningTask() {
        queue.submit(threeSteps())
        executor.reply(StepResult.Done("one"))
        assertTrue(queue.cancel("t1") is NovaResult.Success)
        val task = current()
        assertEquals(TaskStatus.CANCELLED, task.status)
        assertEquals(listOf(StepState.DONE, StepState.CANCELLED, StepState.CANCELLED), task.steps.map { it.state })
        clock.advance(10_000)
        assertEquals(listOf("s1"), executor.started)
        assertEquals(1, executor.cancels)
    }

    @Test
    fun aLateAnswerAfterCancelIsIgnored() {
        queue.submit(threeSteps())
        queue.cancel("t1")
        executor.reply(StepResult.Done("too late"))
        assertEquals(TaskStatus.CANCELLED, current().status)
        assertEquals(StepState.CANCELLED, current().steps[0].state)
    }

    @Test
    fun cancelOfAnUnknownTaskFails() {
        assertEquals(ErrorCode.NOT_FOUND, (queue.cancel("nope") as NovaResult.Failure).error.code)
    }

    @Test
    fun pauseHoldsTheTaskBeforeItsNextStepAndResumeContinues() {
        queue.submit(threeSteps())
        assertTrue(queue.pause("t1") is NovaResult.Success)
        assertEquals(TaskStatus.PAUSED, queue.status("t1"))
        executor.reply(StepResult.Done("one"))   // the running step still finishes
        clock.advance(10_000)
        assertEquals(listOf("s1"), executor.started)
        assertTrue(queue.resume("t1") is NovaResult.Success)
        assertEquals(listOf("s1", "s2"), executor.started)
        assertEquals(TaskStatus.RUNNING, queue.status("t1"))
    }

    @Test
    fun resumeBeforeTheStepFinishedLetsTheGapRunNormally() {
        queue.submit(threeSteps())
        queue.pause("t1")
        queue.resume("t1")
        executor.reply(StepResult.Done("one"))
        clock.advance(100)
        assertEquals(listOf("s1", "s2"), executor.started)
    }

    @Test
    fun pauseAndResumeCheckTheState() {
        assertEquals(ErrorCode.NOT_FOUND, (queue.pause("x") as NovaResult.Failure).error.code)
        queue.submit(threeSteps())
        assertEquals(ErrorCode.INVALID_INPUT, (queue.resume("t1") as NovaResult.Failure).error.code)
        queue.pause("t1")
        assertEquals(ErrorCode.INVALID_INPUT, (queue.pause("t1") as NovaResult.Failure).error.code)
    }

    @Test
    fun secondTaskWaitsThenStartsAfterTheFirstResultShowed() {
        queue.submit(draft("t1", IntentType.SYSTEM_ACTION))
        queue.submit(draft("t2", IntentType.SYSTEM_ACTION))
        assertEquals(TaskStatus.PENDING, queue.status("t2"))
        assertEquals(listOf("task t2"), queue.snapshot().waiting)
        executor.reply(StepResult.Done("one"))
        assertEquals("t1", current().id)                  // the result of t1 is still shown
        assertEquals(TaskStatus.COMPLETED, current().status)
        clock.advance(300)
        assertEquals("t2", current().id)
        assertEquals(listOf("s1", "s1"), executor.started)
        assertTrue(queue.snapshot().waiting.isEmpty())
    }

    @Test
    fun aFailedTaskDoesNotBlockTheNextOne() {
        queue.submit(draft("t1", IntentType.SYSTEM_ACTION))
        queue.submit(draft("t2", IntentType.SYSTEM_ACTION))
        executor.reply(StepResult.Failed("bad"))
        clock.advance(300)
        assertEquals("t2", current().id)
        assertEquals(TaskStatus.RUNNING, current().status)
    }

    @Test
    fun theLineHasALimit() {
        queue.submit(draft("running", IntentType.SYSTEM_ACTION))
        for (i in 1..TaskQueue.MAX_WAITING) assertTrue(queue.submit(draft("w$i", IntentType.SYSTEM_ACTION)) is NovaResult.Success)
        val full = queue.submit(draft("extra", IntentType.SYSTEM_ACTION)) as NovaResult.Failure
        assertEquals(ErrorCode.TEMPORARY_FAILURE, full.error.code)
    }

    @Test
    fun aWaitingTaskCanBeCancelled() {
        queue.submit(draft("t1", IntentType.SYSTEM_ACTION))
        queue.submit(draft("t2", IntentType.SYSTEM_ACTION))
        assertTrue(queue.cancel("t2") is NovaResult.Success)
        assertTrue(queue.snapshot().waiting.isEmpty())
        assertNull(queue.status("t2"))
    }

    @Test
    fun cancelAllStopsEverythingAndNothingStartsLater() {
        queue.submit(threeSteps("t1"))
        queue.submit(threeSteps("t2"))
        queue.cancelAll()
        assertEquals(TaskStatus.CANCELLED, current().status)
        assertTrue(queue.snapshot().waiting.isEmpty())
        clock.advance(60_000)
        assertEquals(listOf("s1"), executor.started)
        assertEquals(0, clock.pendingCount())
    }

    @Test
    fun cancelAllAlsoClearsATaskThatWaitsForTheNextSlot() {
        queue.submit(draft("t1", IntentType.SYSTEM_ACTION))
        queue.submit(draft("t2", IntentType.SYSTEM_ACTION))
        executor.reply(StepResult.Done("one"))         // t2 now waits for its slot
        queue.cancelAll()
        clock.advance(60_000)
        assertEquals(listOf("s1"), executor.started)
    }

    @Test
    fun anExecutorThatThrowsFailsTheStepCleanly() {
        executor.throwOnExecute = true
        queue.submit(threeSteps())
        val task = current()
        assertEquals(TaskStatus.FAILED, task.status)
        assertEquals(TaskMessages.MSG_START_FAILED, task.steps[0].message)
    }

    @Test
    fun anEmptyTaskIsRefused() {
        val result = queue.submit(TaskDraft("e", "empty", emptyList())) as NovaResult.Failure
        assertEquals(ErrorCode.INVALID_INPUT, result.error.code)
    }

    @Test
    fun aDuplicateResultForTheSameStepIsIgnored() {
        queue.submit(threeSteps())
        executor.reply(StepResult.Done("one"))
        executor.reply(StepResult.Failed("duplicate"))
        clock.advance(100)
        assertEquals(StepState.DONE, current().steps[0].state)
        assertEquals(listOf("s1", "s2"), executor.started)
    }

    @Test
    fun dismissClearsTheFinishedResult() {
        queue.submit(draft("t1", IntentType.SYSTEM_ACTION))
        executor.reply(StepResult.Done("one"))
        queue.dismissFinished()
        assertNull(queue.snapshot().current)
    }

    @Test
    fun aNewTaskAfterAFinishedOneStartsAtOnce() {
        queue.submit(draft("t1", IntentType.SYSTEM_ACTION))
        executor.reply(StepResult.Done("one"))
        queue.submit(draft("t2", IntentType.SYSTEM_ACTION))
        assertEquals("t2", current().id)
        assertEquals(listOf("s1", "s1"), executor.started)
    }

    @Test
    fun theListenerIsToldAboutChangesAndAFailingListenerDoesNotBreakTheQueue() {
        val broken = TaskQueue(executor, clock, { throw IllegalStateException("ui crashed") }, timing)
        broken.submit(threeSteps("b1"))
        executor.reply(StepResult.Done("one"))
        clock.advance(100)
        assertEquals(listOf("s1", "s2"), executor.started)
        queue.submit(threeSteps("t1"))
        assertTrue(snapshots.isNotEmpty())
    }
}
EOF

# ---------- 15. StepResultMapperTest.kt ----------
cat > "$TEST/tasks/StepResultMapperTest.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.bubble.BubbleOption
import com.nova.ai.bubble.BubbleOutput
import com.nova.ai.bubble.MessageKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Tests how a controller's answer becomes the result of a task step. Plain JVM test. */
class StepResultMapperTest {

    @Test
    fun nothingYetGivesNoResult() {
        assertNull(StepResultMapper.fromOutput(BubbleOutput.None))
    }

    @Test
    fun doneMessageIsSuccess() {
        assertEquals(
            StepResult.Done("ok"),
            StepResultMapper.fromOutput(BubbleOutput.Message("ok", MessageKind.DONE))
        )
    }

    @Test
    fun errorAndPlainInfoMessagesStopTheTask() {
        assertEquals(
            StepResult.Failed("bad"),
            StepResultMapper.fromOutput(BubbleOutput.Message("bad", MessageKind.ERROR))
        )
        assertEquals(
            StepResult.Failed("not found"),
            StepResultMapper.fromOutput(BubbleOutput.Message("not found", MessageKind.INFO))
        )
    }

    @Test
    fun aGuidedInfoMessageMarkedCompletedIsSuccess() {
        assertEquals(
            StepResult.Done("screen opened"),
            StepResultMapper.fromOutput(BubbleOutput.Message("screen opened", MessageKind.INFO, completed = true))
        )
    }

    @Test
    fun aQuestionIsHandedToTheUser() {
        val decision = BubbleOutput.Decision(
            source = Any(),
            question = "which?",
            options = listOf(BubbleOption("A") {}, BubbleOption("B") {})
        )
        assertEquals(StepResult.NeedsUser("which?", listOf("A", "B")), StepResultMapper.fromOutput(decision))
    }

    @Test
    fun needingTheAppScreenStopsTheTask() {
        assertEquals(StepResult.Failed("allow it"), StepResultMapper.fromOutput(BubbleOutput.NeedsApp("allow it")))
    }
}
EOF

# ---------- 16. CommandPlannerBrainTest.kt ----------
cat > "$TEST/tasks/CommandPlannerBrainTest.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.voice.LanguageDetector
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests the planner with the real rule-based brain, with the same wiring the app uses. */
class CommandPlannerBrainTest {

    private val brain = RuleBasedBrain()

    private val planner = CommandPlanner(analyze = { part ->
        brain.analyze(VoiceCommand(part, LanguageDetector.detect(part), 0L), emptyList()).getOrNull()
    })

    private fun types(text: String): List<IntentType> {
        val plan = planner.plan(text)
        assertTrue("Expected a plan for: $text", plan is NovaResult.Success)
        return (plan as NovaResult.Success).value.steps.map { it.intentType }
    }

    @Test
    fun banglaThreeStepCommandIsPlannedCorrectly() {
        assertEquals(
            listOf(IntentType.OPEN_APP, IntentType.SYSTEM_ACTION, IntentType.SYSTEM_ACTION),
            types("ক্রোম খোলো তারপর ভলিউম বাড়াও তারপর টর্চ জ্বালাও")
        )
    }

    @Test
    fun englishCommandIsPlannedCorrectly() {
        assertEquals(
            listOf(IntentType.OPEN_APP, IntentType.SYSTEM_ACTION),
            types("open chrome then turn on wifi")
        )
    }

    @Test
    fun callAndAlarmPartsAreRecognised() {
        assertEquals(
            listOf(IntentType.MAKE_CALL, IntentType.SET_ALARM),
            types("রহিমকে ফোন করো এরপর সকাল ৭টায় অ্যালার্ম দাও")
        )
    }

    @Test
    fun aPartThatIsNotUnderstoodRefusesTheWholeTask() {
        val plan = planner.plan("ক্রোম খোলো তারপর hello")
        assertTrue(plan is NovaResult.Failure)
        assertTrue((plan as NovaResult.Failure).error.message.contains("hello"))
    }
}
EOF

# ---------- Bubble messages get a "completed" flag (default: DONE means completed) ----------
replace_line "$OUTPUT_FILE" \
  "    data class Message(val text: String, val kind: MessageKind) : BubbleOutput()" \
  "    data class Message(
        val text: String,
        val kind: MessageKind,
        /** True if the job is finished. A guided screen (the user taps the last step) counts as finished. */
        val completed: Boolean = kind == MessageKind.DONE
    ) : BubbleOutput()" \
  "val completed: Boolean"
replace_line "$MAPPER_FILE" \
  "            OutcomeKind.GUIDED, OutcomeKind.HINT -> BubbleOutput.Message(outcome.message, MessageKind.INFO)" \
  "            OutcomeKind.GUIDED -> BubbleOutput.Message(outcome.message, MessageKind.INFO, completed = true)
            OutcomeKind.HINT -> BubbleOutput.Message(outcome.message, MessageKind.INFO)" \
  "OutcomeKind.GUIDED ->"

# ---------- Bubble service: runs multi-part commands as a task and shows the progress ----------
insert_after "$SERVICE_FILE" "import com.nova.ai.logging.NovaLogger" \
"import com.nova.ai.core.TaskStatus
import com.nova.ai.tasks.PendingQuestion
import com.nova.ai.tasks.QueueSnapshot
import com.nova.ai.tasks.TaskHub
import com.nova.ai.tasks.TaskSnapshot" \
  "import com.nova.ai.tasks.TaskHub"
insert_after "$SERVICE_FILE" "    private var destroyed: Boolean = false" \
"    private var taskActive: Boolean = false
    private var lastFinishedId: String? = null
    private var lastNoticeSeq: Int = 0
    private var lastQuestionKey: String? = null" \
  "private var taskActive"
insert_after "$SERVICE_FILE" "    private val emergencyListener: (Boolean) -> Unit = { _ -> handler.post { onEmergencyChanged() } }" \
'
    // P23: the progress of a multi-step task is shown on the bubble.
    private val taskListener: (QueueSnapshot) -> Unit = { snapshot -> onTaskChanged(snapshot) }

    private fun onTaskChanged(snapshot: QueueSnapshot) {
        if (!running || destroyed) return
        val current: TaskSnapshot? = snapshot.current
        val busy: Boolean = current?.isOpen == true || snapshot.waiting.isNotEmpty()
        if (busy != taskActive) {
            taskActive = busy
            refreshState()
        }
        // While the emergency stop is on, its own message stays on the bubble.
        if (EmergencyStop.isActive) return

        val notice: String? = snapshot.notice
        if (notice != null) {
            if (snapshot.noticeSeq != lastNoticeSeq) {
                lastNoticeSeq = snapshot.noticeSeq
                overlay.showStatus(notice, MessageKind.ERROR, STATUS_MS)
            }
            return
        }
        if (current == null) return

        val question: PendingQuestion? = current.question
        when {
            question != null -> showTaskQuestion(current.id, question)
            current.isOpen -> {
                lastQuestionKey = null
                overlay.showStatus(taskProgressText(current), null, 0L)
            }
            current.id != lastFinishedId -> {
                lastFinishedId = current.id
                lastQuestionKey = null
                val text: String = current.summary ?: current.title
                val ok: Boolean = current.status == TaskStatus.COMPLETED
                overlay.showStatus(text, if (ok) MessageKind.DONE else MessageKind.ERROR, STATUS_MS)
                speakResult(text)
            }
        }
    }

    private fun taskProgressText(task: TaskSnapshot): String {
        val total: Int = task.steps.size
        if (task.status == TaskStatus.PAUSED) return getString(R.string.bub_task_paused, task.doneCount, total)
        val index: Int = if (task.activeIndex >= 0) task.activeIndex else minOf(task.doneCount, total - 1)
        return getString(R.string.bub_task_progress, index + 1, total, task.steps[index].title)
    }

    private fun showTaskQuestion(taskId: String, question: PendingQuestion) {
        val key = "$taskId|${question.text}"
        if (key == lastQuestionKey) return
        lastQuestionKey = key
        val buttons: MutableList<PanelButton> = question.options.mapIndexed { index, label ->
            PanelButton(label, if (index == 0) PanelStyle.PRIMARY else PanelStyle.NORMAL) { TaskHub.answer(index) }
        }.toMutableList()
        buttons.add(PanelButton(getString(R.string.bub_task_cancel)) { TaskHub.cancelCurrent() })
        overlay.showPanel(question.text, buttons, QUESTION_MS) { TaskHub.cancelCurrent() }
        speakResult(question.text)
    }' \
  "private val taskListener"
replace_line "$SERVICE_FILE" "            router.handle(command.rawText)" \
"            // P23: a command with several parts (\"... তারপর ...\") runs as a task, step by step.
            if (!TaskHub.submitIfMultiStep(applicationContext, command.rawText)) {
                router.handle(command.rawText)
            }" \
  "TaskHub.submitIfMultiStep"
replace_line "$SERVICE_FILE" \
  "        overlay.setState(BubbleStateMapper.map(EmergencyStop.isActive, conversationState, routing))" \
  "        overlay.setState(BubbleStateMapper.map(EmergencyStop.isActive, conversationState, routing || taskActive))" \
  "routing || taskActive"
insert_after "$SERVICE_FILE" "        EmergencyStop.addListener(emergencyListener)" \
  "        TaskHub.addListener(taskListener)" "TaskHub.addListener(taskListener)"
insert_after "$SERVICE_FILE" "            EmergencyStop.removeListener(emergencyListener)" \
  "            TaskHub.removeListener(taskListener)" "TaskHub.removeListener(taskListener)"

# ---------- Home screen: multi-part commands go to the task queue; progress card ----------
insert_after "$HOME_FILE" "import com.nova.ai.ui.components.NovaInfoCard" \
"import com.nova.ai.tasks.TaskHub
import com.nova.ai.ui.components.TaskQueueCard" \
  "import com.nova.ai.tasks.TaskHub"
insert_after "$HOME_FILE" "                    while (transcript.size > TRANSCRIPT_LIMIT) transcript.removeAt(0)" \
"                    // P23: a command with several parts (\"... তারপর ...\") runs as a task, step by step.
                    if (TaskHub.submitIfMultiStep(context, command.rawText)) return" \
  "TaskHub.submitIfMultiStep(context, command.rawText)"
insert_after "$HOME_FILE" "                    statusOverride = receivedText" \
  "                    if (TaskHub.submitIfMultiStep(context, commandText)) return@Button" \
  "TaskHub.submitIfMultiStep(context, commandText)"
insert_after "$HOME_FILE" "        MediaActionCard(controller = mediaController)" \
"
        TaskQueueCard(showInput = false)" \
  "TaskQueueCard(showInput = false)"

# ---------- Automation screen: the task card, and the Stop button works now ----------
insert_after "$AUTO_FILE" "import com.nova.ai.ui.components.NovaInfoCard" \
  "import com.nova.ai.ui.components.TaskQueueCard" "import com.nova.ai.ui.components.TaskQueueCard"
insert_after "$AUTO_FILE" "import com.nova.ai.R" \
  "import com.nova.ai.security.EmergencyStop" "import com.nova.ai.security.EmergencyStop"
insert_before "$AUTO_FILE" "        // Disabled until the emergency stop is implemented (P22)." \
"        TaskQueueCard()
" \
  "TaskQueueCard()"
replace_line "$AUTO_FILE" "            onClick = { }," \
  "            onClick = { if (EmergencyStop.isActive) EmergencyStop.release(\"automation screen\") else EmergencyStop.trigger(\"automation screen\") }," \
  "EmergencyStop.isActive"
replace_line "$AUTO_FILE" "            enabled = false," "            enabled = true," "enabled = true,"
if grep -q "জরুরি Stop P22-তে চালু হবে।" "$UI_STRINGS"; then
  sed -i 's/জরুরি Stop P22-তে চালু হবে।/এই বাটন জরুরি Stop চালু করে। আবার চাপলে ছেড়ে দেয়।/' "$UI_STRINGS"
fi

# ---------- Commit and push ----------
git add -A
if git diff --cached --quiet; then
  echo "Nothing new to commit."
else
  git commit -m "P23: task planner and queue (multi-step commands run step by step)"
  git push
fi

echo "P23 files created and pushed."
