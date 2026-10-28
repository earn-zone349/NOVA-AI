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
