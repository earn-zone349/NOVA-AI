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
