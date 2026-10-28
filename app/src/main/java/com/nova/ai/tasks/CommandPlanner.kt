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
