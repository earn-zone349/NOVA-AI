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
