package com.nova.ai.planner

import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.TaskPlan

/** Breaks an intent into an ordered, executable list of steps. */
interface TaskPlanner {
    /** Builds a plan for [intent], or fails if the intent cannot be planned. */
    fun createPlan(intent: NovaIntent): NovaResult<TaskPlan>
}
