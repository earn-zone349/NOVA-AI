package com.nova.ai.accessibility

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.view.ViewConfiguration
import android.view.accessibility.AccessibilityNodeInfo
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenBounds
import com.nova.ai.logging.NovaLogger

/**
 * The finger gestures NOVA can make: swipe, long press, double tap, pinch and two-finger
 * swipe. Every gesture first checks the emergency stop (inside [GestureRunner]).
 *
 * Long press and double tap always look up the item on the live screen first and use where it
 * is now. If the item is gone or not visible, they fail instead of touching an old position.
 * A long press prefers the app's own long-click action and falls back to holding a finger on
 * the item. Blocking: call from a background thread.
 */
object GestureActions {

    private const val TAG: String = "GestureActions"
    private const val MAX_ANCESTORS: Int = 6
    // Added to the system long-press time so the phone surely sees a long press.
    private const val LONG_PRESS_EXTRA_MS: Long = 400L

    private const val MSG_NO_SCREEN: String =
        "স্ক্রিনের তথ্য পাওয়া যায়নি। অ্যাপটি পড়তে দিচ্ছে না, বা স্ক্রিন বন্ধ।"
    private const val MSG_ITEM_GONE: String = "জিনিসটা এখন স্ক্রিনে নেই। স্ক্রিন বদলে গেছে।"
    private const val MSG_ITEM_HIDDEN: String = "জিনিসটা এখন স্ক্রিনে দেখা যাচ্ছে না।"
    private const val MSG_BAD_ITEM: String = "জিনিসটার মাপ বোঝা যায়নি।"
    private const val MSG_UNEXPECTED: String = "ইশারা দিতে সমস্যা হয়েছে।"

    /** What a live item needs after the long-click action was tried on it. */
    private sealed class PressOutcome {
        /** The app handled the long click itself. */
        object Handled : PressOutcome()

        /** The app did not handle it: hold a finger at [point]. */
        data class NeedsFinger(val point: GesturePoint) : PressOutcome()
    }

    // ---------------------------------------------------------------- swipe, pinch, two fingers

    /** Swipes with one finger in [direction] through the middle of the screen. */
    fun swipe(
        service: AccessibilityService,
        direction: SwipeDirection,
        distanceFraction: Float,
        durationMs: Long
    ): NovaResult<Unit> = dispatch(service) { width, height ->
        GestureGeometry.swipe(direction, width, height, distanceFraction, durationMs)
    }

    /** Swipes with two fingers side by side in [direction]. */
    fun twoFingerSwipe(
        service: AccessibilityService,
        direction: SwipeDirection,
        distanceFraction: Float,
        durationMs: Long
    ): NovaResult<Unit> = dispatch(service) { width, height ->
        GestureGeometry.twoFingerSwipe(direction, width, height, distanceFraction, durationMs)
    }

    /** Zooms with two fingers around the middle of the screen. */
    fun pinch(service: AccessibilityService, mode: PinchMode): NovaResult<Unit> =
        dispatch(service) { width, height -> GestureGeometry.pinch(mode, width, height) }

    // ---------------------------------------------------------------- long press, double tap

    /** Long-presses the item described by [target], at the place where it is on the screen now. */
    fun longPress(service: AccessibilityService, target: NodeTarget): NovaResult<Unit> {
        ActionGate.check()?.let { return it }

        val live: NovaResult<PressOutcome?> = withLiveNode(service, target) { node -> longClickOrPoint(node) }
        val outcome: PressOutcome = when (live) {
            is NovaResult.Success -> live.value ?: return NovaResult.failure(ErrorCode.INVALID_INPUT, MSG_BAD_ITEM)
            is NovaResult.Failure -> return live
        }
        return when (outcome) {
            is PressOutcome.Handled -> NovaResult.Success(Unit)
            is PressOutcome.NeedsFinger -> {
                val holdMs: Long = ViewConfiguration.getLongPressTimeout() + LONG_PRESS_EXTRA_MS
                dispatch(service) { width, height ->
                    GestureGeometry.longPress(outcome.point.x, outcome.point.y, width, height, holdMs)
                }
            }
        }
    }

    /** Taps the item described by [target] two times quickly, at the place where it is now. */
    fun doubleTap(service: AccessibilityService, target: NodeTarget): NovaResult<Unit> {
        ActionGate.check()?.let { return it }

        val live: NovaResult<GesturePoint?> = withLiveNode(service, target) { node -> liveCenterOf(node) }
        val point: GesturePoint = when (live) {
            is NovaResult.Success -> live.value ?: return NovaResult.failure(ErrorCode.INVALID_INPUT, MSG_BAD_ITEM)
            is NovaResult.Failure -> return live
        }
        return dispatch(service) { width, height ->
            GestureGeometry.doubleTap(point.x, point.y, width, height)
        }
    }

    // ---------------------------------------------------------------- live items

    // Finds the item on the live screen and runs [block] on it. The item is released afterwards,
    // so [block] must not keep it. An item that is gone or not visible is a failure.
    private fun <T> withLiveNode(
        service: AccessibilityService,
        target: NodeTarget,
        block: (AccessibilityNodeInfo) -> T
    ): NovaResult<T> {
        val root: AccessibilityNodeInfo = service.rootInActiveWindow
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_NO_SCREEN)
        try {
            val node: AccessibilityNodeInfo = NodeResolver.resolve(root, target)
                ?: return NovaResult.failure(ErrorCode.NOT_FOUND, MSG_ITEM_GONE)
            try {
                if (!node.isVisibleToUser) {
                    return NovaResult.failure(ErrorCode.NOT_FOUND, MSG_ITEM_HIDDEN)
                }
                return NovaResult.Success(block(node))
            } finally {
                NodeResolver.recycleQuietly(node)
            }
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Looking up the item failed", e)
            return NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_UNEXPECTED, e)
        } finally {
            NodeResolver.recycleQuietly(root)
        }
    }

    // Tries the app's own long click; if it does not work, tells where a finger must be held
    // (null when the item has no size).
    private fun longClickOrPoint(node: AccessibilityNodeInfo): PressOutcome? {
        if (performLongClickOn(node)) return PressOutcome.Handled
        val point: GesturePoint = liveCenterOf(node) ?: return null
        return PressOutcome.NeedsFinger(point)
    }

    // The item itself or its nearest long-clickable parent receives the long click.
    private fun performLongClickOn(start: AccessibilityNodeInfo): Boolean {
        var current: AccessibilityNodeInfo = start
        var ownsCurrent = false
        try {
            for (step in 0..MAX_ANCESTORS) {
                if (current.isLongClickable && current.isEnabled) {
                    return current.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK)
                }
                val parent: AccessibilityNodeInfo = current.parent ?: return false
                if (ownsCurrent) NodeResolver.recycleQuietly(current)
                current = parent
                ownsCurrent = true
            }
            return false
        } finally {
            if (ownsCurrent) NodeResolver.recycleQuietly(current)
        }
    }

    // The middle of the item as it is on the screen now, or null when the item has no size.
    private fun liveCenterOf(node: AccessibilityNodeInfo): GesturePoint? {
        val rect = Rect()
        node.getBoundsInScreen(rect)
        return centerOf(ScreenBounds(rect.left, rect.top, rect.right, rect.bottom))
    }

    // ---------------------------------------------------------------- helpers

    // Reads the screen size, asks [planner] for the finger paths and performs them.
    private inline fun dispatch(
        service: AccessibilityService,
        planner: (width: Int, height: Int) -> NovaResult<GesturePlan>
    ): NovaResult<Unit> {
        ActionGate.check()?.let { return it }
        return try {
            val metrics = service.resources.displayMetrics
            when (val plan: NovaResult<GesturePlan> = planner(metrics.widthPixels, metrics.heightPixels)) {
                is NovaResult.Success -> GestureRunner.execute(service, plan.value)
                is NovaResult.Failure -> plan
            }
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Gesture failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_UNEXPECTED, e)
        }
    }

    // The middle of an area, or null when the area has no size.
    private fun centerOf(bounds: ScreenBounds): GesturePoint? {
        if (bounds.right <= bounds.left || bounds.bottom <= bounds.top) return null
        return GesturePoint(
            x = (bounds.left + bounds.right) / 2f,
            y = (bounds.top + bounds.bottom) / 2f
        )
    }
}
