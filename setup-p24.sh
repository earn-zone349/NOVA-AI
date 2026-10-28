#!/usr/bin/env bash
# NOVA AI - Phase 24 setup script: retry, timeout, alternative paths and error recovery for tasks.
# Additive: the P23 task files are rewritten with every P23 feature kept (a task still runs its
# steps in order, asks questions, pauses and cancels); new retry policy, alternative-path planner,
# web page opener and tests. Existing bubble files get two small additions: a "retryable" flag on
# bubble messages, set where the phone reported an error.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
TEST="app/src/test/java/com/nova/ai"
OUTPUT_FILE="$BASE/bubble/BubbleOutput.kt"
MAPPER_FILE="$BASE/bubble/BubbleOutputMapper.kt"

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

# Stops early unless the anchor is there once (or the marker shows the edit was made before).
need() {
  local file="$1" anchor="$2" marker="$3"
  grep -q -F -- "$marker" "$file" && return 0
  [ "$(count_line "$file" "$anchor")" = "1" ] || fail "anchor missing in $file: $anchor"
}

for required in "$BASE/tasks/TaskQueue.kt" "$BASE/tasks/TaskHub.kt" "$BASE/tasks/CommandStepExecutor.kt" \
  "$BASE/tasks/StepResultMapper.kt" "$BASE/ui/components/TaskQueueCard.kt" "$OUTPUT_FILE" "$MAPPER_FILE"; do
  [ -f "$required" ] || fail "$required not found. Run from the repo root after P23 is installed."
done

need "$OUTPUT_FILE" "        val completed: Boolean = kind == MessageKind.DONE" "val retryable: Boolean"
need "$MAPPER_FILE" "        is ContactActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR)" "ContactActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR, retryable = true)"
need "$MAPPER_FILE" "        is AppActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR)" "AppActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR, retryable = true)"
need "$MAPPER_FILE" "        is TimeActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR)" "TimeActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR, retryable = true)"
need "$MAPPER_FILE" "            OutcomeKind.FAILED -> BubbleOutput.Message(outcome.message, MessageKind.ERROR)" "OutcomeKind.FAILED -> BubbleOutput.Message(outcome.message, MessageKind.ERROR, retryable = true)"

mkdir -p "$BASE/tasks" "$TEST/tasks" "$TEST/bubble"

# ---------- 1. RetryPolicy.kt ----------
cat > "$BASE/tasks/RetryPolicy.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.nlp.IntentAction
import com.nova.ai.nlp.IntentEntity

/**
 * When and how often a failed step is tried again. A step is repeated only when repeating cannot
 * do harm: if the phone reported an error, nothing happened, so it is repeated; if there was no
 * answer at all, the step may have happened, so it is repeated only if doing it twice changes
 * nothing (opening an app, searching, switching something on). A call, a message or an alarm is
 * never repeated after silence. Pure logic with no Android classes.
 */
data class RetryPolicy(
    /** Tries per step, the first one included. 1 means no retry. */
    val maxAttempts: Int = 1,
    /** Waiting time before the 2nd, the 3rd ... try. The last value is used for any later try. */
    val backoffMs: List<Long> = emptyList(),
    /** After a step failed for good: ask the user (try again, skip, cancel) instead of stopping at once. */
    val askUserOnFailure: Boolean = false
) {

    /** How long to wait before try number [attempt] (2 or more). */
    fun delayBefore(attempt: Int): Long {
        if (backoffMs.isEmpty()) return 0L
        return backoffMs[(attempt - 2).coerceIn(0, backoffMs.lastIndex)]
    }

    /** True if [step], which just failed in try number [attempt] for the reason [kind], may be tried again. */
    fun allowsRetry(step: PlannedStep, kind: FailureKind, attempt: Int): Boolean {
        if (attempt >= maxAttempts) return false
        if (step.isAlternative) return false
        return when (kind) {
            FailureKind.PERMANENT -> false
            FailureKind.RETRYABLE -> true
            FailureKind.UNCERTAIN -> isRepeatable(step)
        }
    }

    companion object {
        /** No retry and no question: a failed step stops the task. */
        val NONE: RetryPolicy = RetryPolicy()

        /** Up to three tries with a short wait, then ask the user what to do. */
        val STANDARD: RetryPolicy = RetryPolicy(
            maxAttempts = 3,
            backoffMs = listOf(1000L, 2500L),
            askUserOnFailure = true
        )

        // Doing these twice leaves the phone in the same state as doing them once.
        private val SETTING_ACTIONS: Set<String> = setOf(
            IntentAction.ON, IntentAction.OFF, IntentAction.SET, IntentAction.MUTE, IntentAction.OPEN_SETTINGS
        )

        /** True if doing [step] twice is the same as doing it once. */
        fun isRepeatable(step: PlannedStep): Boolean = when (step.intentType) {
            IntentType.OPEN_APP, IntentType.WEB_SEARCH, IntentType.NAVIGATE -> true
            IntentType.SYSTEM_ACTION -> step.entities[IntentEntity.ACTION] in SETTING_ACTIONS
            else -> false
        } || step.kind == StepKind.OPEN_URL
    }
}
EOF

# ---------- 2. FallbackPlanner.kt ----------
cat > "$BASE/tasks/FallbackPlanner.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.nlp.IntentEntity
import java.net.URLEncoder

/** Finds another way to do a step that failed. */
interface FallbackPlanner {
    /** An alternative for [step], or null if there is none. */
    fun alternativeFor(step: PlannedStep): PlannedStep?
}

/** No alternatives. */
object NoFallback : FallbackPlanner {
    override fun alternativeFor(step: PlannedStep): PlannedStep? = null
}

/**
 * Alternatives that use the web: an app that is not on the phone is opened as its website, and a
 * search that could not be done in an app is done in the browser. Only fixed https addresses are
 * used (plus a search address with the encoded query), so a spoken word can never become another kind of link.
 */
object WebFallbackPlanner : FallbackPlanner {

    private const val NOTE_SITE: String = "অ্যাপ খোলা যায়নি, তাই ওয়েবসাইটে খুলেছি।"
    private const val NOTE_SEARCH: String = "অ্যাপে সার্চ হয়নি, তাই ব্রাউজারে সার্চ করেছি।"

    // The standard app names of the brain (see AppAliases) and their websites.
    private val SITES: Map<String, String> = mapOf(
        "chrome" to "https://www.google.com",
        "google" to "https://www.google.com",
        "whatsapp" to "https://web.whatsapp.com",
        "facebook" to "https://www.facebook.com",
        "messenger" to "https://www.messenger.com",
        "tiktok" to "https://www.tiktok.com",
        "youtube" to "https://www.youtube.com",
        "gmail" to "https://mail.google.com",
        "instagram" to "https://www.instagram.com",
        "telegram" to "https://web.telegram.org",
        "maps" to "https://maps.google.com",
        "x" to "https://x.com",
        "netflix" to "https://www.netflix.com",
        "spotify" to "https://open.spotify.com",
        "play store" to "https://play.google.com/store",
        "snapchat" to "https://www.snapchat.com"
    )

    override fun alternativeFor(step: PlannedStep): PlannedStep? {
        if (step.isAlternative) return null
        return when (step.intentType) {
            IntentType.OPEN_APP -> siteFor(step)
            IntentType.WEB_SEARCH -> searchFor(step)
            else -> null
        }
    }

    private fun siteFor(step: PlannedStep): PlannedStep? {
        val app: String = step.entities[IntentEntity.APP]?.trim().orEmpty()
        val url: String = SITES[app.lowercase()] ?: return null
        return alternative(step, url, NOTE_SITE)
    }

    private fun searchFor(step: PlannedStep): PlannedStep? {
        val query: String = step.entities[IntentEntity.QUERY]?.trim().orEmpty()
        if (query.isEmpty()) return null
        val encoded: String = URLEncoder.encode(query, "UTF-8")
        val app: String = step.entities[IntentEntity.APP]?.trim()?.lowercase().orEmpty()
        val url: String = if (app == "youtube") {
            "https://www.youtube.com/results?search_query=$encoded"
        } else {
            "https://www.google.com/search?q=$encoded"
        }
        return alternative(step, url, NOTE_SEARCH)
    }

    private fun alternative(step: PlannedStep, url: String, note: String): PlannedStep = PlannedStep(
        id = step.id + "-alt",
        title = step.title,
        command = step.command,
        intentType = step.intentType,
        entities = step.entities,
        kind = StepKind.OPEN_URL,
        url = url,
        note = note,
        isAlternative = true
    )
}
EOF

# ---------- 3. UrlOpener.kt ----------
cat > "$BASE/tasks/UrlOpener.kt" <<'EOF'
package com.nova.ai.tasks

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/** Opens a web page in the phone's browser. Only https addresses are accepted. */
class UrlOpener(context: Context) {

    private val appContext: Context = context.applicationContext

    /** Opens [url]. A failure result carries a Bangla message for the user. */
    fun open(url: String): NovaResult<Unit> {
        if (!url.startsWith(HTTPS_PREFIX)) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, "এই ঠিকানা খোলা নিরাপদ নয়।")
        }
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appContext.startActivity(intent)
            NovaLogger.i(TAG, "Web page opened")
            NovaResult.Success(Unit)
        } catch (e: ActivityNotFoundException) {
            NovaLogger.e(TAG, "No browser found", e)
            NovaResult.failure(ErrorCode.NOT_FOUND, "ফোনে ব্রাউজার পাওয়া যায়নি।", e)
        } catch (e: SecurityException) {
            NovaLogger.e(TAG, "Opening the page was blocked", e)
            NovaResult.failure(ErrorCode.PERMISSION_DENIED, "ফোন পেজটি খুলতে দিচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Opening the page failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "পেজ খুলতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "UrlOpener"
        const val HTTPS_PREFIX: String = "https://"
    }
}
EOF

# ---------- 4. TaskModels.kt ----------
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
    val noticeSeq: Int = 0
) {
    companion object {
        /** An empty queue. */
        val EMPTY: QueueSnapshot = QueueSnapshot(current = null, waiting = emptyList(), notice = null)
    }
}
EOF

# ---------- 5. TaskMessages.kt ----------
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

# ---------- 6. CommandPlanner.kt ----------
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
            steps.add(
                PlannedStep(
                    id = "s${position + 1}",
                    title = part,
                    command = part,
                    intentType = intent.type,
                    entities = intent.entities
                )
            )
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

# ---------- 7. TaskQueue.kt ----------
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
    val betweenTasksMs: Long = 1500L,
    /** Own timeouts for kinds of steps that should be quicker or slower than [stepTimeoutMs]. */
    val perTypeTimeoutMs: Map<IntentType, Long> = emptyMap()
) {
    /** How long a step of kind [type] may take. */
    fun stepTimeoutFor(type: IntentType): Long = perTypeTimeoutMs[type] ?: stepTimeoutMs
}

/**
 * Runs tasks one after another. Each task is a list of steps that run in order; the queue waits
 * after a step (longer after one that opens an app), watches every step with a timeout, and asks the
 * user when a step needs an answer. A step that fails is tried again as [retry] allows (waiting a
 * little longer each time); when the tries are used up, an alternative path from [fallback] is
 * tried once (for example the website of an app that is not installed). If that fails too, the user
 * is asked what to do (try again, skip the step, cancel) when [RetryPolicy.askUserOnFailure] is on;
 * otherwise the task stops there and the steps after it are skipped.
 * More tasks can wait in line. Pause stops the task before its next step.
 * Use from one thread only (the main thread on the phone). Logic only, no Android classes.
 */
class TaskQueue(
    private val executor: StepExecutor,
    private val scheduler: Scheduler,
    private val onChanged: (QueueSnapshot) -> Unit,
    private val timing: TaskTiming = TaskTiming(),
    private val log: (String) -> Unit = {},
    private val retry: RetryPolicy = RetryPolicy.NONE,
    private val fallback: FallbackPlanner = NoFallback
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

        // The try number of each step (for the retry rule), and all tries together (for the user).
        val attempts: IntArray = IntArray(draft.steps.size)
        val tries: IntArray = IntArray(draft.steps.size)
        val triedAlternative: BooleanArray = BooleanArray(draft.steps.size)

        // The step that runs now (the original, or an alternative made for it).
        var currentStep: PlannedStep = draft.steps.first()

        // While the question is about a failed step: what each option does.
        var recoveryActions: List<RecoveryAction>? = null
        var failureReason: String? = null
    }

    private enum class RecoveryAction { RETRY, SKIP, CANCEL }

    private var active: ActiveTask? = null
    private var finished: TaskSnapshot? = null
    private val waiting: ArrayDeque<TaskDraft> = ArrayDeque()

    // Every started step gets a new token; an answer that arrives with an old token is ignored.
    private var token: Long = 0L
    private var stepTimer: Cancellable? = null
    private var nextStepTimer: Cancellable? = null
    private var nextTaskTimer: Cancellable? = null
    private var retryTimer: Cancellable? = null

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
        val recovery: List<RecoveryAction>? = task.recoveryActions
        if (recovery != null) {
            answerRecovery(task, recovery[optionIndex])
            return NovaResult.Success(Unit)
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
        runOriginal(0)
    }

    // Runs the step as the plan has it, for the first time.
    private fun runOriginal(index: Int) {
        val task: ActiveTask = active ?: return
        runStep(index, task.draft.steps[index], 1)
    }

    private fun runStep(index: Int, step: PlannedStep, attempt: Int) {
        val task: ActiveTask = active ?: return
        task.index = index
        task.currentStep = step
        task.attempts[index] = attempt
        task.tries[index] += 1
        task.states[index] = StepState.RUNNING
        task.messages[index] = null
        task.stepOpen = true
        token += 1
        val myToken: Long = token
        armStepTimer(timing.stepTimeoutFor(step.intentType))
        changed()
        try {
            executor.execute(step) { result -> onResult(myToken, result) }
        } catch (e: Exception) {
            log("step start failed: ${e.javaClass.simpleName}")
            if (myToken == token) handleFailure(task, TaskMessages.MSG_START_FAILED, FailureKind.RETRYABLE)
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
                task.messages[task.index] = task.currentStep.note ?: result.message
                changed()
                scheduleNext(task)
            }
            is StepResult.Failed -> handleFailure(task, result.message, result.kind)
            is StepResult.NeedsUser -> {
                if (result.options.isEmpty()) {
                    handleFailure(task, result.question, FailureKind.PERMANENT)
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
            val skipped: Int = task.states.count { it == StepState.SKIPPED }
            task.summary = if (skipped == 0) {
                TaskMessages.allDone(task.draft.steps.size)
            } else {
                TaskMessages.doneWithSkips(task.states.count { it == StepState.DONE }, skipped)
            }
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
        runOriginal(task.index + 1)
    }

    // A step did not work. Try again, or try another way, or ask the user, or stop.
    private fun handleFailure(task: ActiveTask, reason: String, kind: FailureKind) {
        val index: Int = task.index
        val step: PlannedStep = task.currentStep
        val attempt: Int = task.attempts[index]
        task.stepOpen = false
        disarmStepTimer()
        token += 1   // answers of the failed try that arrive late are ignored

        if (retry.allowsRetry(step, kind, attempt)) {
            val next: Int = attempt + 1
            task.states[index] = StepState.RETRYING
            task.messages[index] = TaskMessages.retrying(next, retry.maxAttempts, reason)
            log("retry $next/${retry.maxAttempts} of ${step.id}")
            changed()
            retryTimer?.cancel()
            retryTimer = scheduler.postDelayed(retry.delayBefore(next)) {
                retryTimer = null
                if (active === task) runStep(index, step, next)
            }
            return
        }

        if (!task.triedAlternative[index]) {
            val alternative: PlannedStep? = try {
                fallback.alternativeFor(task.draft.steps[index])
            } catch (e: Exception) {
                log("fallback failed: ${e.javaClass.simpleName}")
                null
            }
            if (alternative != null) {
                task.triedAlternative[index] = true
                log("alternative path for ${step.id}")
                runStep(index, alternative, 1)
                return
            }
        }

        if (retry.askUserOnFailure) askWhatToDo(task, reason) else failTask(reason)
    }

    // The step failed for good: the user decides (try again, skip it if steps follow, or cancel).
    private fun askWhatToDo(task: ActiveTask, reason: String) {
        val index: Int = task.index
        val options: MutableList<String> = mutableListOf(TaskMessages.OPTION_RETRY)
        val actions: MutableList<RecoveryAction> = mutableListOf(RecoveryAction.RETRY)
        if (index < task.draft.steps.lastIndex) {
            options.add(TaskMessages.OPTION_SKIP)
            actions.add(RecoveryAction.SKIP)
        }
        options.add(TaskMessages.OPTION_CANCEL)
        actions.add(RecoveryAction.CANCEL)

        task.recoveryActions = actions
        task.failureReason = reason
        task.states[index] = StepState.WAITING_USER
        task.messages[index] = reason
        task.question = PendingQuestion(
            TaskMessages.recoveryQuestion(index + 1, task.draft.steps.size, reason),
            options
        )
        armStepTimer(timing.questionTimeoutMs, onQuestionTimeout = true)
        changed()
    }

    private fun answerRecovery(task: ActiveTask, action: RecoveryAction) {
        val index: Int = task.index
        task.question = null
        task.recoveryActions = null
        disarmStepTimer()
        when (action) {
            RecoveryAction.RETRY -> {
                task.triedAlternative[index] = false
                runStep(index, task.draft.steps[index], 1)
            }
            RecoveryAction.SKIP -> {
                task.states[index] = StepState.SKIPPED
                changed()
                scheduleNext(task)
            }
            RecoveryAction.CANCEL -> cancelActive(TaskMessages.MSG_CANCELLED)
        }
    }

    private fun failTask(reason: String) {
        val task: ActiveTask = active ?: return
        task.stepOpen = false
        task.question = null
        task.recoveryActions = null
        task.states[task.index] = StepState.FAILED
        task.messages[task.index] = reason
        for (i in task.index + 1 until task.states.size) task.states[i] = StepState.SKIPPED
        task.summary = TaskMessages.stoppedAt(
            task.index + 1,
            task.draft.steps.size,
            reason,
            attempts = task.tries[task.index],
            triedAlternative = task.triedAlternative[task.index]
        )
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
                task.states[i] == StepState.RETRYING || task.states[i] == StepState.WAITING_USER
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
        retryTimer?.cancel()
        retryTimer = null
        token += 1
        task.status = status
        task.question = null
        task.recoveryActions = null
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
            val task: ActiveTask = active ?: return@postDelayed
            if (onQuestionTimeout) {
                // A question about a failed step ends as a failure; any other question cancels the task.
                val reason: String? = task.failureReason.takeIf { task.recoveryActions != null }
                if (reason != null) failTask(reason) else cancelActive(TaskMessages.MSG_QUESTION_TIMEOUT)
            } else {
                try {
                    executor.cancel()
                } catch (e: Exception) {
                    log("executor cancel failed: ${e.javaClass.simpleName}")
                }
                handleFailure(task, TaskMessages.MSG_STEP_TIMEOUT, FailureKind.UNCERTAIN)
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
            StepSnapshot(
                id = step.id,
                title = step.title,
                state = task.states[i],
                message = task.messages[i],
                attempt = maxOf(1, task.attempts[i]),
                maxAttempts = retry.maxAttempts
            )
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

# ---------- 8. StepResultMapper.kt ----------
cat > "$BASE/tasks/StepResultMapper.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.bubble.BubbleOutput

/**
 * Turns what a command controller reported (as a [BubbleOutput]) into the outcome of a task step.
 * A message that says the job is done (or that the right screen was opened for the user) is
 * success; every other message (not found, needs a permission, not understood, error) stops the task.
 * An error the phone reported (the action did not happen) may be tried again; the rest cannot be
 * helped by trying again. A question is handed to the user.
 */
internal object StepResultMapper {

    /** The step result for [output], or null if there is nothing yet. */
    fun fromOutput(output: BubbleOutput): StepResult? = when (output) {
        is BubbleOutput.None -> null
        is BubbleOutput.Message -> when {
            output.completed -> StepResult.Done(output.text)
            output.retryable -> StepResult.Failed(output.text, FailureKind.RETRYABLE)
            else -> StepResult.Failed(output.text, FailureKind.PERMANENT)
        }
        is BubbleOutput.Decision ->
            StepResult.NeedsUser(output.question, output.options.map { it.label })
        is BubbleOutput.NeedsApp -> StepResult.Failed(output.text)
    }
}
EOF

# ---------- 9. CommandStepExecutor.kt ----------
cat > "$BASE/tasks/CommandStepExecutor.kt" <<'EOF'
package com.nova.ai.tasks

import android.content.Context
import com.nova.ai.bubble.BubbleCommandRouter
import com.nova.ai.bubble.BubbleOutput
import com.nova.ai.bubble.ResourceBubbleTexts
import com.nova.ai.core.NovaResult
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
    private val urlOpener = UrlOpener(context)

    private val router = BubbleCommandRouter(
        context = context,
        scope = scope,
        texts = ResourceBubbleTexts(context),
        onOutput = { output -> handleOutput(output) },
        onBusyChanged = { }
    )

    override fun execute(step: PlannedStep, onResult: (StepResult) -> Unit) {
        decision = null
        if (step.kind == StepKind.OPEN_URL) {
            // An alternative path: the page opens at once, there is nothing to wait for.
            callback = null
            val url: String = step.url ?: return onResult(StepResult.Failed(TaskMessages.MSG_START_FAILED))
            when (val opened: NovaResult<Unit> = urlOpener.open(url)) {
                is NovaResult.Success -> onResult(StepResult.Done(step.note ?: step.title))
                is NovaResult.Failure -> onResult(StepResult.Failed(opened.error.message))
            }
            return
        }
        callback = onResult
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

# ---------- 10. TaskHub.kt ----------
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

# ---------- 11. TaskQueueCard.kt ----------
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

# ---------- 12. StepResultMapperTest.kt ----------
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
    fun anErrorTheAppReportedMayBeTriedAgainButOtherFailuresMayNot() {
        assertEquals(
            StepResult.Failed("could not open", FailureKind.RETRYABLE),
            StepResultMapper.fromOutput(BubbleOutput.Message("could not open", MessageKind.ERROR, retryable = true))
        )
        assertEquals(
            StepResult.Failed("not found", FailureKind.PERMANENT),
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

# ---------- 13. RetryPolicyTest.kt ----------
cat > "$TEST/tasks/RetryPolicyTest.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.nlp.IntentAction
import com.nova.ai.nlp.IntentEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests when a failed step may be tried again. Plain JVM test. */
class RetryPolicyTest {

    private val policy = RetryPolicy(maxAttempts = 3, backoffMs = listOf(1000L, 2500L))

    private fun step(type: IntentType, action: String? = null) = PlannedStep(
        id = "s1", title = "t", command = "c", intentType = type,
        entities = if (action == null) emptyMap() else mapOf(IntentEntity.ACTION to action)
    )

    @Test
    fun anErrorTheAppReportedIsRepeatedForAnyKindOfStep() {
        for (type in listOf(IntentType.OPEN_APP, IntentType.MAKE_CALL, IntentType.SET_ALARM, IntentType.SYSTEM_ACTION)) {
            assertTrue(policy.allowsRetry(step(type), FailureKind.RETRYABLE, attempt = 1))
        }
    }

    @Test
    fun aPermanentFailureIsNeverRepeated() {
        assertFalse(policy.allowsRetry(step(IntentType.OPEN_APP), FailureKind.PERMANENT, 1))
    }

    @Test
    fun silenceIsRepeatedOnlyWhenDoingItTwiceIsHarmless() {
        assertTrue(policy.allowsRetry(step(IntentType.OPEN_APP), FailureKind.UNCERTAIN, 1))
        assertTrue(policy.allowsRetry(step(IntentType.WEB_SEARCH), FailureKind.UNCERTAIN, 1))
        assertTrue(policy.allowsRetry(step(IntentType.SYSTEM_ACTION, IntentAction.ON), FailureKind.UNCERTAIN, 1))
        assertFalse(policy.allowsRetry(step(IntentType.SYSTEM_ACTION, IntentAction.UP), FailureKind.UNCERTAIN, 1))
        assertFalse(policy.allowsRetry(step(IntentType.MAKE_CALL), FailureKind.UNCERTAIN, 1))
        assertFalse(policy.allowsRetry(step(IntentType.SET_ALARM), FailureKind.UNCERTAIN, 1))
        assertFalse(policy.allowsRetry(step(IntentType.SEND_MESSAGE), FailureKind.UNCERTAIN, 1))
        assertFalse(policy.allowsRetry(step(IntentType.MEDIA_CONTROL, IntentAction.NEXT), FailureKind.UNCERTAIN, 1))
    }

    @Test
    fun theNumberOfTriesIsLimited() {
        val s = step(IntentType.OPEN_APP)
        assertTrue(policy.allowsRetry(s, FailureKind.RETRYABLE, 2))
        assertFalse(policy.allowsRetry(s, FailureKind.RETRYABLE, 3))
        assertFalse(RetryPolicy.NONE.allowsRetry(s, FailureKind.RETRYABLE, 1))
    }

    @Test
    fun anAlternativeStepIsNeverRepeated() {
        val alt = step(IntentType.OPEN_APP).copy(isAlternative = true)
        assertFalse(policy.allowsRetry(alt, FailureKind.RETRYABLE, 1))
    }

    @Test
    fun theWaitGrowsAndTheLastValueRepeats() {
        assertEquals(1000L, policy.delayBefore(2))
        assertEquals(2500L, policy.delayBefore(3))
        assertEquals(2500L, policy.delayBefore(9))
        assertEquals(0L, RetryPolicy.NONE.delayBefore(2))
    }

    @Test
    fun standardPolicyAsksTheUserAndNonePolicyDoesNot() {
        assertTrue(RetryPolicy.STANDARD.askUserOnFailure)
        assertEquals(3, RetryPolicy.STANDARD.maxAttempts)
        assertFalse(RetryPolicy.NONE.askUserOnFailure)
    }
}
EOF

# ---------- 14. WebFallbackPlannerTest.kt ----------
cat > "$TEST/tasks/WebFallbackPlannerTest.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.nlp.IntentEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests the alternative paths (website instead of app, browser search). Plain JVM test. */
class WebFallbackPlannerTest {

    private fun step(type: IntentType, vararg entities: Pair<String, String>) = PlannedStep(
        id = "s2", title = "t", command = "c", intentType = type, entities = mapOf(*entities)
    )

    @Test
    fun anAppThatCannotBeOpenedIsOpenedAsAWebsite() {
        val alt = WebFallbackPlanner.alternativeFor(step(IntentType.OPEN_APP, IntentEntity.APP to "Facebook"))!!
        assertEquals(StepKind.OPEN_URL, alt.kind)
        assertEquals("https://www.facebook.com", alt.url)
        assertEquals("s2-alt", alt.id)
        assertTrue(alt.isAlternative)
        assertNotNull(alt.note)
    }

    @Test
    fun appNamesAreMatchedIgnoringCase() {
        assertEquals(
            "https://www.youtube.com",
            WebFallbackPlanner.alternativeFor(step(IntentType.OPEN_APP, IntentEntity.APP to "YouTube"))!!.url
        )
    }

    @Test
    fun anAppWithoutAWebsiteHasNoAlternative() {
        assertNull(WebFallbackPlanner.alternativeFor(step(IntentType.OPEN_APP, IntentEntity.APP to "Calculator")))
        assertNull(WebFallbackPlanner.alternativeFor(step(IntentType.OPEN_APP)))
    }

    @Test
    fun aSearchThatFailedInAnAppIsDoneInTheBrowser() {
        val alt = WebFallbackPlanner.alternativeFor(
            step(IntentType.WEB_SEARCH, IntentEntity.APP to "Chrome", IntentEntity.QUERY to "free 3d model")
        )!!
        assertEquals("https://www.google.com/search?q=free+3d+model", alt.url)
    }

    @Test
    fun aYouTubeSearchGoesToYouTubeResults() {
        val alt = WebFallbackPlanner.alternativeFor(
            step(IntentType.WEB_SEARCH, IntentEntity.APP to "YouTube", IntentEntity.QUERY to "গান")
        )!!
        assertTrue(alt.url!!.startsWith("https://www.youtube.com/results?search_query="))
        assertTrue(alt.url!!.contains("%E0%A6%97")) // the Bangla word is encoded
    }

    @Test
    fun theSearchWordsCannotChangeTheKindOfLink() {
        val alt = WebFallbackPlanner.alternativeFor(
            step(IntentType.WEB_SEARCH, IntentEntity.QUERY to "x&url=javascript:alert(1)")
        )!!
        assertTrue(alt.url!!.startsWith("https://www.google.com/search?q="))
        assertTrue(!alt.url!!.contains("&url="))
    }

    @Test
    fun emptySearchOrOtherKindsOfStepsHaveNoAlternative() {
        assertNull(WebFallbackPlanner.alternativeFor(step(IntentType.WEB_SEARCH)))
        assertNull(WebFallbackPlanner.alternativeFor(step(IntentType.MAKE_CALL)))
        assertNull(WebFallbackPlanner.alternativeFor(step(IntentType.SYSTEM_ACTION)))
    }

    @Test
    fun anAlternativeHasNoAlternative() {
        val alt = WebFallbackPlanner.alternativeFor(step(IntentType.OPEN_APP, IntentEntity.APP to "Facebook"))!!
        assertNull(WebFallbackPlanner.alternativeFor(alt))
    }

    @Test
    fun noFallbackGivesNothing() {
        assertNull(NoFallback.alternativeFor(step(IntentType.OPEN_APP, IntentEntity.APP to "Facebook")))
    }
}
EOF

# ---------- 15. TaskQueueRecoveryTest.kt ----------
cat > "$TEST/tasks/TaskQueueRecoveryTest.kt" <<'EOF'
package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaResult
import com.nova.ai.core.TaskStatus
import com.nova.ai.nlp.IntentAction
import com.nova.ai.nlp.IntentEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests retry, alternative paths and the question after a failure. Fake clock, fake phone. */
class TaskQueueRecoveryTest {

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

    private class FakeExecutor : StepExecutor {
        val started = mutableListOf<PlannedStep>()
        val answers = mutableListOf<Int>()
        var cancels = 0
        private var callback: ((StepResult) -> Unit)? = null

        override fun execute(step: PlannedStep, onResult: (StepResult) -> Unit) {
            started.add(step)
            callback = onResult
        }

        override fun answer(optionIndex: Int) { answers.add(optionIndex) }
        override fun cancel() { cancels += 1 }
        fun reply(result: StepResult) { callback?.invoke(result) }
        fun ids() = started.map { it.id }
    }

    private val clock = FakeScheduler()
    private val executor = FakeExecutor()
    private val timing = TaskTiming(gapMs = 100, settleAfterLaunchMs = 1000, stepTimeoutMs = 5000, questionTimeoutMs = 20000, betweenTasksMs = 300)
    private val policy = RetryPolicy(maxAttempts = 3, backoffMs = listOf(1000L, 2500L), askUserOnFailure = true)

    private fun queue(
        retry: RetryPolicy = policy,
        fallback: FallbackPlanner = NoFallback
    ) = TaskQueue(executor, clock, { }, timing, retry = retry, fallback = fallback)

    private fun step(n: Int, type: IntentType = IntentType.OPEN_APP, vararg entities: Pair<String, String>) =
        PlannedStep("s$n", "step $n", "cmd $n", type, entities = mapOf(*entities))

    private fun draft(vararg steps: PlannedStep) = TaskDraft("t1", "task", steps.toList())

    private fun TaskQueue.current() = snapshot().current!!

    private val retryable = StepResult.Failed("could not open", FailureKind.RETRYABLE)

    // ---------------------------------------------------------------- retry

    @Test
    fun aFailedStepIsTriedAgainAfterAShortWaitAndCanSucceed() {
        val q = queue()
        q.submit(draft(step(1), step(2)))
        executor.reply(retryable)
        assertEquals(StepState.RETRYING, q.current().steps[0].state)
        assertEquals(listOf("s1"), executor.ids())
        clock.advance(999)
        assertEquals(listOf("s1"), executor.ids())
        clock.advance(1)
        assertEquals(listOf("s1", "s1"), executor.ids())
        assertEquals(2, q.current().steps[0].attempt)
        executor.reply(StepResult.Done("opened"))
        assertEquals(StepState.DONE, q.current().steps[0].state)
        clock.advance(1000)
        assertEquals(listOf("s1", "s1", "s2"), executor.ids())
    }

    @Test
    fun theWaitGrowsBetweenTries() {
        val q = queue()
        q.submit(draft(step(1)))
        executor.reply(retryable)
        clock.advance(1000)
        executor.reply(retryable)
        clock.advance(2499)
        assertEquals(2, executor.started.size)
        clock.advance(1)
        assertEquals(3, executor.started.size)
    }

    @Test
    fun afterTheLastTryTheUserIsAsked() {
        val q = queue()
        q.submit(draft(step(1), step(2)))
        executor.reply(retryable)
        clock.advance(1000)
        executor.reply(retryable)
        clock.advance(2500)
        executor.reply(retryable)
        val task = q.current()
        assertEquals(TaskStatus.RUNNING, task.status)
        assertEquals(StepState.WAITING_USER, task.steps[0].state)
        assertEquals(
            listOf(TaskMessages.OPTION_RETRY, TaskMessages.OPTION_SKIP, TaskMessages.OPTION_CANCEL),
            task.question!!.options
        )
        assertEquals(3, executor.started.size)
    }

    @Test
    fun aPermanentFailureIsNotRepeatedButTheUserIsStillAsked() {
        val q = queue()
        q.submit(draft(step(1)))
        executor.reply(StepResult.Failed("not found", FailureKind.PERMANENT))
        assertEquals(1, executor.started.size)
        assertEquals(StepState.WAITING_USER, q.current().steps[0].state)
    }

    @Test
    fun silenceIsRepeatedForAnOpenAppStepButNotForACall() {
        val q = queue()
        q.submit(draft(step(1, IntentType.OPEN_APP)))
        clock.advance(5000)                               // step timeout
        assertEquals(StepState.RETRYING, q.current().steps[0].state)
        assertEquals(1, executor.cancels)
        clock.advance(1000)
        assertEquals(2, executor.started.size)
        q.cancelAll()

        val q2 = queue()
        executor.started.clear()
        q2.submit(draft(step(1, IntentType.MAKE_CALL)))
        clock.advance(5000)
        assertEquals(1, executor.started.size)
        assertEquals(StepState.WAITING_USER, q2.current().steps[0].state)
    }

    @Test
    fun withoutAPolicyAFailureStopsTheTaskLikeBefore() {
        val q = queue(retry = RetryPolicy.NONE)
        q.submit(draft(step(1), step(2)))
        executor.reply(retryable)
        assertEquals(TaskStatus.FAILED, q.current().status)
        assertEquals(StepState.SKIPPED, q.current().steps[1].state)
    }

    @Test
    fun aLateAnswerFromAFailedTryIsIgnored() {
        val q = queue()
        q.submit(draft(step(1)))
        clock.advance(5000)                               // timeout, retry starts later
        executor.reply(StepResult.Done("too late"))
        assertEquals(StepState.RETRYING, q.current().steps[0].state)
    }

    // ---------------------------------------------------------------- alternative path

    private class OneAlternative : FallbackPlanner {
        override fun alternativeFor(step: PlannedStep): PlannedStep? =
            if (step.isAlternative) null else PlannedStep(
                id = step.id + "-alt", title = step.title, command = step.command, intentType = step.intentType,
                kind = StepKind.OPEN_URL, url = "https://example.com", note = "opened the website", isAlternative = true
            )
    }

    @Test
    fun whenTheTriesAreUsedUpAnAlternativeIsTriedOnce() {
        val q = queue(fallback = OneAlternative())
        q.submit(draft(step(1)))
        executor.reply(StepResult.Failed("no app", FailureKind.PERMANENT))
        assertEquals(listOf("s1", "s1-alt"), executor.ids())
        assertEquals(StepKind.OPEN_URL, executor.started.last().kind)
        executor.reply(StepResult.Done("page opened"))
        val task = q.current()
        assertEquals(TaskStatus.COMPLETED, task.status)
        assertEquals("opened the website", task.steps[0].message)
    }

    @Test
    fun theAlternativeComesAfterTheRetries() {
        val q = queue(fallback = OneAlternative())
        q.submit(draft(step(1)))
        executor.reply(retryable)
        clock.advance(1000)
        executor.reply(retryable)
        clock.advance(2500)
        executor.reply(retryable)
        assertEquals(listOf("s1", "s1", "s1", "s1-alt"), executor.ids())
    }

    @Test
    fun aFailingAlternativeIsNotRepeatedAndTheUserIsAsked() {
        val q = queue(fallback = OneAlternative())
        q.submit(draft(step(1)))
        executor.reply(StepResult.Failed("no app", FailureKind.PERMANENT))
        executor.reply(StepResult.Failed("no browser", FailureKind.RETRYABLE))
        assertEquals(listOf("s1", "s1-alt"), executor.ids())
        assertEquals(StepState.WAITING_USER, q.current().steps[0].state)
        assertTrue(q.current().question!!.text.contains("no browser"))
    }

    @Test
    fun aFallbackThatThrowsIsIgnored() {
        val q = queue(fallback = object : FallbackPlanner {
            override fun alternativeFor(step: PlannedStep): PlannedStep? = throw IllegalStateException("boom")
        })
        q.submit(draft(step(1)))
        executor.reply(StepResult.Failed("no app", FailureKind.PERMANENT))
        assertEquals(StepState.WAITING_USER, q.current().steps[0].state)
    }

    // ---------------------------------------------------------------- the question after a failure

    private fun failedForGood(q: TaskQueue, vararg steps: PlannedStep) {
        q.submit(draft(*steps))
        executor.reply(StepResult.Failed("not found", FailureKind.PERMANENT))
    }

    @Test
    fun chosenRetryStartsTheStepAgainWithFreshTries() {
        val q = queue()
        failedForGood(q, step(1), step(2))
        assertTrue(q.answer(0) is NovaResult.Success)
        assertEquals(listOf("s1", "s1"), executor.ids())
        assertEquals(StepState.RUNNING, q.current().steps[0].state)
        assertNull(q.current().question)
        assertTrue(executor.answers.isEmpty())            // this answer is for the queue, not the phone
        executor.reply(StepResult.Done("ok"))
        clock.advance(1000)
        assertEquals(listOf("s1", "s1", "s2"), executor.ids())
    }

    @Test
    fun chosenSkipMovesOnAndTheTaskEndsWithTheSkipReported() {
        val q = queue()
        failedForGood(q, step(1), step(2, IntentType.SYSTEM_ACTION))
        q.answer(1)
        assertEquals(StepState.SKIPPED, q.current().steps[0].state)
        clock.advance(1000)
        assertEquals(listOf("s1", "s2"), executor.ids())
        executor.reply(StepResult.Done("ok"))
        val task = q.current()
        assertEquals(TaskStatus.COMPLETED, task.status)
        assertEquals(TaskMessages.doneWithSkips(1, 1), task.summary)
    }

    @Test
    fun chosenCancelEndsTheTask() {
        val q = queue()
        failedForGood(q, step(1), step(2))
        q.answer(2)
        assertEquals(TaskStatus.CANCELLED, q.current().status)
        clock.advance(10_000)
        assertEquals(listOf("s1"), executor.ids())
    }

    @Test
    fun theLastStepCannotBeSkipped() {
        val q = queue()
        failedForGood(q, step(1))
        assertEquals(listOf(TaskMessages.OPTION_RETRY, TaskMessages.OPTION_CANCEL), q.current().question!!.options)
    }

    @Test
    fun anUnansweredFailureQuestionEndsTheTaskAsFailed() {
        val q = queue()
        failedForGood(q, step(1), step(2))
        clock.advance(20_000)
        val task = q.current()
        assertEquals(TaskStatus.FAILED, task.status)
        assertEquals(StepState.FAILED, task.steps[0].state)
        assertEquals(StepState.SKIPPED, task.steps[1].state)
        assertEquals(TaskMessages.stoppedAt(1, 2, "not found", attempts = 1), task.summary)
    }

    @Test
    fun theFailureSummaryTellsHowOftenItWasTriedAndThatAnAlternativeFailedToo() {
        val q = queue(retry = RetryPolicy(maxAttempts = 2, backoffMs = listOf(10L), askUserOnFailure = false), fallback = OneAlternative())
        q.submit(draft(step(1)))
        executor.reply(retryable)
        clock.advance(10)
        executor.reply(retryable)
        executor.reply(StepResult.Failed("no browser", FailureKind.PERMANENT))
        val task = q.current()
        assertEquals(TaskStatus.FAILED, task.status)
        assertEquals(TaskMessages.stoppedAt(1, 1, "no browser", attempts = 3, triedAlternative = true), task.summary)
        assertTrue(task.summary!!.contains("3"))
    }

    // ---------------------------------------------------------------- cancel and pause

    @Test
    fun cancelDuringTheWaitBeforeARetryStopsEverything() {
        val q = queue()
        q.submit(draft(step(1)))
        executor.reply(retryable)
        q.cancel("t1")
        assertEquals(StepState.CANCELLED, q.current().steps[0].state)
        clock.advance(60_000)
        assertEquals(1, executor.started.size)
        assertEquals(0, clock.pendingCount())
    }

    @Test
    fun answeringWithABadNumberAfterAFailureIsRefused() {
        val q = queue()
        failedForGood(q, step(1), step(2))
        assertTrue(q.answer(9) is NovaResult.Failure)
        assertTrue(q.answer(-1) is NovaResult.Failure)
        assertEquals(StepState.WAITING_USER, q.current().steps[0].state)
    }

    @Test
    fun anOrdinaryQuestionStillGoesToThePhone() {
        val q = queue()
        q.submit(draft(step(1)))
        executor.reply(StepResult.NeedsUser("which?", listOf("A", "B")))
        q.answer(1)
        assertEquals(listOf(1), executor.answers)
    }

    @Test
    fun perTypeTimeoutsAreUsed() {
        val fastTiming = timing.copy(perTypeTimeoutMs = mapOf(IntentType.SYSTEM_ACTION to 1000L))
        val q = TaskQueue(executor, clock, { }, fastTiming)
        q.submit(draft(step(1, IntentType.SYSTEM_ACTION, IntentEntity.ACTION to IntentAction.UP)))
        clock.advance(1000)
        assertEquals(TaskStatus.FAILED, q.current().status)
    }
}
EOF

# ---------- 16. BubbleOutputRetryableTest.kt ----------
cat > "$TEST/bubble/BubbleOutputRetryableTest.kt" <<'EOF'
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
EOF

# ---------- Bubble messages: "retryable" means the phone reported an error, so nothing happened ----------
replace_line "$OUTPUT_FILE" "        val completed: Boolean = kind == MessageKind.DONE" \
"        val completed: Boolean = kind == MessageKind.DONE,
        /** True if the phone reported an error: the action did not happen, so doing it again is safe. */
        val retryable: Boolean = false" \
  "val retryable: Boolean"
replace_line "$MAPPER_FILE" "        is ContactActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR)" \
  "        is ContactActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR, retryable = true)" \
  "ContactActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR, retryable = true)"
replace_line "$MAPPER_FILE" "        is AppActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR)" \
  "        is AppActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR, retryable = true)" \
  "AppActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR, retryable = true)"
replace_line "$MAPPER_FILE" "        is TimeActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR)" \
  "        is TimeActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR, retryable = true)" \
  "TimeActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR, retryable = true)"
replace_line "$MAPPER_FILE" "            OutcomeKind.FAILED -> BubbleOutput.Message(outcome.message, MessageKind.ERROR)" \
  "            OutcomeKind.FAILED -> BubbleOutput.Message(outcome.message, MessageKind.ERROR, retryable = true)" \
  "OutcomeKind.FAILED -> BubbleOutput.Message(outcome.message, MessageKind.ERROR, retryable = true)"

# ---------- Commit and push ----------
git add -A
if git diff --cached --quiet; then
  echo "Nothing new to commit."
else
  git commit -m "P24: retry, timeouts, alternative paths and error recovery for tasks"
  git push
fi

echo "P24 files created and pushed."
