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
enum class LabAction {
    CLICK, TYPE, SCROLL_UP, SCROLL_DOWN, BACK, HOME, RECENTS,
    SWIPE_UP, SWIPE_DOWN, SWIPE_LEFT, SWIPE_RIGHT,
    LONG_PRESS, DOUBLE_TAP, PINCH_OUT, PINCH_IN, TWO_FINGER_UP, TWO_FINGER_DOWN
}

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
            LabAction.SWIPE_UP ->
                AccessibilityBridge.swipe(SwipeDirection.UP).map { context.getString(R.string.gst_ok_swipe_up) }
            LabAction.SWIPE_DOWN ->
                AccessibilityBridge.swipe(SwipeDirection.DOWN).map { context.getString(R.string.gst_ok_swipe_down) }
            LabAction.SWIPE_LEFT ->
                AccessibilityBridge.swipe(SwipeDirection.LEFT).map { context.getString(R.string.gst_ok_swipe_left) }
            LabAction.SWIPE_RIGHT ->
                AccessibilityBridge.swipe(SwipeDirection.RIGHT).map { context.getString(R.string.gst_ok_swipe_right) }
            LabAction.LONG_PRESS -> longPressByName(context, query)
            LabAction.DOUBLE_TAP -> doubleTapByName(context, query)
            LabAction.PINCH_OUT ->
                AccessibilityBridge.pinch(PinchMode.OUT).map { context.getString(R.string.gst_ok_pinch_out) }
            LabAction.PINCH_IN ->
                AccessibilityBridge.pinch(PinchMode.IN).map { context.getString(R.string.gst_ok_pinch_in) }
            LabAction.TWO_FINGER_UP ->
                AccessibilityBridge.twoFingerSwipe(SwipeDirection.UP).map { context.getString(R.string.gst_ok_two_up) }
            LabAction.TWO_FINGER_DOWN ->
                AccessibilityBridge.twoFingerSwipe(SwipeDirection.DOWN).map { context.getString(R.string.gst_ok_two_down) }
        }

    // Reads the screen and finds the item that best matches [query] (clickable ones first).
    private fun findNodeByName(context: Context, query: String): NovaResult<UiNode> {
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
        return NovaResult.Success(node)
    }

    private fun clickByName(context: Context, query: String): NovaResult<String> {
        val node: UiNode = when (val found = findNodeByName(context, query)) {
            is NovaResult.Success -> found.value
            is NovaResult.Failure -> return found
        }
        return AccessibilityBridge.click(node.toTarget())
            .map { context.getString(R.string.act_ok_click, node.label()) }
    }

    private fun longPressByName(context: Context, query: String): NovaResult<String> {
        val node: UiNode = when (val found = findNodeByName(context, query)) {
            is NovaResult.Success -> found.value
            is NovaResult.Failure -> return found
        }
        return AccessibilityBridge.longPress(node.toTarget())
            .map { context.getString(R.string.gst_ok_long_press, node.label()) }
    }

    private fun doubleTapByName(context: Context, query: String): NovaResult<String> {
        val node: UiNode = when (val found = findNodeByName(context, query)) {
            is NovaResult.Success -> found.value
            is NovaResult.Failure -> return found
        }
        return AccessibilityBridge.doubleTap(node.toTarget())
            .map { context.getString(R.string.gst_ok_double_tap, node.label()) }
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
