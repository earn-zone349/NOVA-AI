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
