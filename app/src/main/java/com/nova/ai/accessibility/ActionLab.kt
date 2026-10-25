package com.nova.ai.accessibility

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.R
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScrollDirection
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The actions the test card can run. */
enum class LabAction { CLICK, TYPE, SCROLL_UP, SCROLL_DOWN, BACK, HOME, RECENTS }

/** The result line shown in the test card. */
data class ActionLabMessage(val text: String, val success: Boolean)

/**
 * Runs the action test independently of any screen, so the countdown keeps going while
 * the user opens another app. The test card reads [waitingSeconds] and [message].
 * Use from the main thread.
 */
object ActionLab {

    private const val COUNTDOWN_SECONDS: Int = 5
    private const val ONE_SECOND_MS: Long = 1000L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null

    /** Seconds left before the action runs; 0 when no countdown is running. */
    var waitingSeconds: Int by mutableStateOf(0)
        private set

    /** The result of the last action. */
    var message: ActionLabMessage? by mutableStateOf<ActionLabMessage?>(null)
        private set

    /** Runs [action]; with [delayed] it first waits 5 seconds so the user can open another app. */
    fun run(context: Context, action: LabAction, query: String, text: String, delayed: Boolean) {
        cancel()
        val appContext: Context = context.applicationContext
        job = scope.launch {
            if (delayed) {
                for (second in COUNTDOWN_SECONDS downTo 1) {
                    waitingSeconds = second
                    delay(ONE_SECOND_MS)
                }
                waitingSeconds = 0
            }
            // Reading and acting talk to the system many times, so they run off the main thread.
            val outcome: NovaResult<String> = withContext(Dispatchers.Default) {
                perform(appContext, action, query.trim(), text)
            }
            message = when (outcome) {
                is NovaResult.Success -> ActionLabMessage(outcome.value, true)
                is NovaResult.Failure -> ActionLabMessage(
                    appContext.getString(R.string.act_failed, outcome.error.message),
                    false
                )
            }
        }
    }

    /** Stops a running countdown. */
    fun cancel() {
        job?.cancel()
        job = null
        waitingSeconds = 0
    }

    private fun perform(context: Context, action: LabAction, query: String, text: String): NovaResult<String> =
        when (action) {
            LabAction.CLICK -> clickByName(context, query)
            LabAction.TYPE -> typeByName(context, query, text)
            LabAction.SCROLL_UP ->
                AccessibilityBridge.scroll(ScrollDirection.UP).map { context.getString(R.string.act_ok_scroll_up) }
            LabAction.SCROLL_DOWN ->
                AccessibilityBridge.scroll(ScrollDirection.DOWN).map { context.getString(R.string.act_ok_scroll_down) }
            LabAction.BACK -> AccessibilityBridge.pressBack().map { context.getString(R.string.act_ok_back) }
            LabAction.HOME -> AccessibilityBridge.pressHome().map { context.getString(R.string.act_ok_home) }
            LabAction.RECENTS -> AccessibilityBridge.openRecents().map { context.getString(R.string.act_ok_recents) }
        }

    private fun clickByName(context: Context, query: String): NovaResult<String> {
        if (query.isEmpty()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, context.getString(R.string.act_need_name))
        }
        val capture: ScreenCapture = when (val read = AccessibilityBridge.readScreen()) {
            is NovaResult.Success -> read.value
            is NovaResult.Failure -> return read
        }
        val node: UiNode = NodeFinder.findBest(capture, query, NodeFinder.Filter.CLICKABLE)
            ?: NodeFinder.findBest(capture, query, NodeFinder.Filter.ANY)
            ?: return NovaResult.failure(ErrorCode.NOT_FOUND, context.getString(R.string.act_not_found, query))

        return AccessibilityBridge.click(node.toTarget())
            .map { context.getString(R.string.act_ok_click, node.label()) }
    }

    private fun typeByName(context: Context, query: String, text: String): NovaResult<String> {
        if (text.isEmpty()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, context.getString(R.string.act_need_text))
        }
        val capture: ScreenCapture = when (val read = AccessibilityBridge.readScreen()) {
            is NovaResult.Success -> read.value
            is NovaResult.Failure -> return read
        }
        val node: UiNode = (
            if (query.isEmpty()) {
                NodeFinder.firstEditable(capture)
            } else {
                NodeFinder.findBest(capture, query, NodeFinder.Filter.EDITABLE)
            }
            ) ?: return NovaResult.failure(ErrorCode.NOT_FOUND, context.getString(R.string.act_no_field))

        val message: String = if (query.isEmpty()) {
            context.getString(R.string.act_ok_type_first)
        } else {
            context.getString(R.string.act_ok_type, node.label())
        }
        return AccessibilityBridge.typeText(node.toTarget(), text, append = false).map { message }
    }
}
