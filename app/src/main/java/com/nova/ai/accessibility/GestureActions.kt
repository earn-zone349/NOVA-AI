package com.nova.ai.accessibility

import android.accessibilityservice.AccessibilityService
import android.view.ViewConfiguration
import android.view.accessibility.AccessibilityNodeInfo
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenBounds
import com.nova.ai.logging.NovaLogger

/**
 * The finger gestures NOVA can make: swipe, long press, double tap, pinch and two-finger
 * swipe. Every gesture first checks the emergency stop (inside [GestureRunner]). A long press
 * prefers the app's own long-click action and falls back to holding a finger on the item.
 * Blocking: call from a background thread.
 */
object GestureActions {

    private const val TAG: String = "GestureActions"
    private const val MAX_ANCESTORS: Int = 6
    // Added to the system long-press time so the phone surely sees a long press.
    private const val LONG_PRESS_EXTRA_MS: Long = 400L

    private const val MSG_NO_SCREEN: String =
        "স্ক্রিনের তথ্য পাওয়া যায়নি। অ্যাপটি পড়তে দিচ্ছে না, বা স্ক্রিন বন্ধ।"
    private const val MSG_BAD_ITEM: String = "জায়গাটা বোঝা যায়নি।"
    private const val MSG_UNEXPECTED: String = "ইশারা দিতে সমস্যা হয়েছে।"

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

    /** Long-presses the item described by [target]. */
    fun longPress(service: AccessibilityService, target: NodeTarget): NovaResult<Unit> {
        ActionGate.check()?.let { return it }

        val root: AccessibilityNodeInfo? = service.rootInActiveWindow
        if (root == null) return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_NO_SCREEN)

        var done = false
        try {
            val resolved: AccessibilityNodeInfo? = NodeResolver.resolve(root, target)
            if (resolved != null) {
                try {
                    done = performLongClickOn(resolved)
                } finally {
                    NodeResolver.recycleQuietly(resolved)
                }
            }
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Long click failed", e)
        } finally {
            NodeResolver.recycleQuietly(root)
        }

        if (done) return NovaResult.Success(Unit)
        // No long-click action worked: hold a finger on the middle of the item instead.
        val holdMs: Long = ViewConfiguration.getLongPressTimeout() + LONG_PRESS_EXTRA_MS
        return centerOf(target.bounds)?.let { point ->
            dispatch(service) { width, height ->
                GestureGeometry.longPress(point.x, point.y, width, height, holdMs)
            }
        } ?: NovaResult.failure(ErrorCode.INVALID_INPUT, MSG_BAD_ITEM)
    }

    /** Taps the item described by [target] two times quickly. */
    fun doubleTap(service: AccessibilityService, target: NodeTarget): NovaResult<Unit> {
        val point: GesturePoint = centerOf(target.bounds)
            ?: return NovaResult.failure(ErrorCode.INVALID_INPUT, MSG_BAD_ITEM)
        return dispatch(service) { width, height ->
            GestureGeometry.doubleTap(point.x, point.y, width, height)
        }
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

    // The middle of an item, or null when the item has no size.
    private fun centerOf(bounds: ScreenBounds): GesturePoint? {
        if (bounds.right <= bounds.left || bounds.bottom <= bounds.top) return null
        return GesturePoint(
            x = (bounds.left + bounds.right) / 2f,
            y = (bounds.top + bounds.bottom) / 2f
        )
    }
}
