package com.nova.ai.automation

import com.nova.ai.core.NovaResult
import com.nova.ai.core.TaskPlan
import com.nova.ai.core.TaskStatus

/** Receives progress updates for running tasks. */
interface AutomationListener {
    fun onStatusChanged(taskId: String, status: TaskStatus)
    fun onStepCompleted(taskId: String, stepId: String)
}

/** Queues and runs task plans with pause, resume, and cancel support. */
interface AutomationManager {
    /** Registers the progress listener (null to remove). */
    fun setListener(listener: AutomationListener?)

    /** Adds [plan] to the queue and returns its task id. */
    fun submit(plan: TaskPlan): NovaResult<String>

    fun pause(taskId: String): NovaResult<Unit>
    fun resume(taskId: String): NovaResult<Unit>
    fun cancel(taskId: String): NovaResult<Unit>

    /** Stops every queued and running task. */
    fun cancelAll()

    /** Current status of a task, or null if unknown. */
    fun getStatus(taskId: String): TaskStatus?
}
