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
