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
