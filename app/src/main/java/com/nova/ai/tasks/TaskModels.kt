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
