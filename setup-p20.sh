#!/usr/bin/env bash
# NOVA AI - Phase 20 setup script: swipe, long press, double tap and two-finger gestures.
# Additive: new gesture classes; GestureRunner, ActionLab and ActionLabCard are rewritten with every
# P19 feature kept; AccessibilityBridge gets new gesture functions inserted (nothing is removed).
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
BRIDGE_FILE="$BASE/accessibility/AccessibilityBridge.kt"

for required in \
  "$BASE/accessibility/AccessibilityBridge.kt" \
  "$BASE/accessibility/GestureRunner.kt" \
  "$BASE/accessibility/ScreenActions.kt" \
  "$BASE/accessibility/ActionGate.kt" \
  "$BASE/accessibility/ActionLab.kt" \
  "$BASE/accessibility/NodeResolver.kt" \
  "$BASE/accessibility/NodeTarget.kt" \
  "$BASE/ui/components/ActionLabCard.kt" \
  "app/src/main/res/values/strings_p19.xml"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after P19 is installed." >&2
    exit 1
  fi
done

# The bridge gets new functions at one known place; stop early if that place is missing.
if ! grep -q "GestureActions" "$BRIDGE_FILE"; then
  grep -qxF '        performGlobal(AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS)' "$BRIDGE_FILE" \
    || { echo "ERROR: AccessibilityBridge anchor not found" >&2; exit 1; }
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------- A. New strings file ----------
cat > app/src/main/res/values/strings_p20.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="gst_title">ইশারা পরীক্ষা (P20)</string>
    <string name="gst_note">নোভা সোয়াইপ, লং প্রেস, ডাবল ট্যাপ এবং দুই আঙুলের ইশারা দিতে পারে। লং প্রেস ও ডাবল ট্যাপের জন্য ওপরের ঘরে স্ক্রিনে যেমন লেখা তেমন নাম লেখো। সোয়াইপ ও দুই আঙুলের ইশারা স্ক্রিনের মাঝখানে হয়।</string>
    <string name="gst_swipe_up">↑ উপরে সোয়াইপ</string>
    <string name="gst_swipe_down">↓ নিচে সোয়াইপ</string>
    <string name="gst_swipe_left">← বামে সোয়াইপ</string>
    <string name="gst_swipe_right">→ ডানে সোয়াইপ</string>
    <string name="gst_long_press">লং প্রেস</string>
    <string name="gst_double_tap">ডাবল ট্যাপ</string>
    <string name="gst_pinch_out">জুম বাড়াও (ছড়াও)</string>
    <string name="gst_pinch_in">জুম কমাও (গুটাও)</string>
    <string name="gst_two_up">দুই আঙুল ↑</string>
    <string name="gst_two_down">দুই আঙুল ↓</string>

    <string name="gst_ok_swipe_up">উপরে সোয়াইপ করেছি।</string>
    <string name="gst_ok_swipe_down">নিচে সোয়াইপ করেছি।</string>
    <string name="gst_ok_swipe_left">বামে সোয়াইপ করেছি।</string>
    <string name="gst_ok_swipe_right">ডানে সোয়াইপ করেছি।</string>
    <string name="gst_ok_long_press">লং প্রেস করেছি: %1$s</string>
    <string name="gst_ok_double_tap">ডাবল ট্যাপ করেছি: %1$s</string>
    <string name="gst_ok_pinch_out">দুই আঙুলে ছড়িয়েছি (জুম বেড়েছে)।</string>
    <string name="gst_ok_pinch_in">দুই আঙুলে গুটিয়েছি (জুম কমেছে)।</string>
    <string name="gst_ok_two_up">দুই আঙুলে উপরে সোয়াইপ করেছি।</string>
    <string name="gst_ok_two_down">দুই আঙুলে নিচে সোয়াইপ করেছি।</string>
</resources>
EOF

# ---------- 1. GestureModels.kt ----------
cat > "$BASE/accessibility/GestureModels.kt" <<'EOF'
package com.nova.ai.accessibility

/**
 * The direction the finger moves in a swipe. Swiping UP moves the finger up,
 * which makes the content of a list move up (like scrolling down).
 */
enum class SwipeDirection { UP, DOWN, LEFT, RIGHT }

/**
 * Two-finger zoom. [OUT] moves the fingers apart (the content gets bigger),
 * [IN] moves them together (the content gets smaller).
 */
enum class PinchMode { OUT, IN }

/** A point on the screen in pixels. */
data class GesturePoint(val x: Float, val y: Float)

/**
 * One finger: it touches down at [start] after [startDelayMs], moves in a straight line
 * to [end] and lifts after [durationMs]. A tap or a long press has the same start and end.
 */
data class GestureStroke(
    val start: GesturePoint,
    val end: GesturePoint,
    val startDelayMs: Long,
    val durationMs: Long
) {
    /** When this finger lifts, counted from the start of the gesture. */
    val endTimeMs: Long get() = startDelayMs + durationMs
}

/** Everything that makes up one gesture: one stroke per finger touch. */
data class GesturePlan(val strokes: List<GestureStroke>) {
    /** How long the whole gesture takes. */
    val totalDurationMs: Long get() = strokes.maxOfOrNull { it.endTimeMs } ?: 0L
}
EOF

# ---------- 2. GestureGeometry.kt ----------
cat > "$BASE/accessibility/GestureGeometry.kt" <<'EOF'
package com.nova.ai.accessibility

import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult

/**
 * Works out where the fingers go for each gesture. This is plain arithmetic with no Android
 * classes, so it can be tested without a phone. Swipes stay away from the screen edges and
 * the bottom edge, because the system uses those for its own Back and Home gestures.
 */
object GestureGeometry {

    const val DEFAULT_SWIPE_FRACTION: Float = 0.45f
    const val MIN_SWIPE_FRACTION: Float = 0.15f
    const val MAX_SWIPE_FRACTION: Float = 0.70f
    const val DEFAULT_SWIPE_DURATION_MS: Long = 350L
    const val MIN_SWIPE_DURATION_MS: Long = 100L
    const val MAX_SWIPE_DURATION_MS: Long = 2000L
    const val TAP_DURATION_MS: Long = 60L
    const val DOUBLE_TAP_GAP_MS: Long = 100L
    const val MIN_LONG_PRESS_MS: Long = 600L
    const val MAX_LONG_PRESS_MS: Long = 5000L

    private const val CENTER: Float = 0.5f
    private const val PINCH_DURATION_MS: Long = 400L
    // Distance of each finger from the middle, as a share of the screen width.
    private const val PINCH_NEAR: Float = 0.08f
    private const val PINCH_FAR: Float = 0.32f
    // Where the two fingers of a two-finger swipe stand, as a share of the other screen side.
    private const val FINGER_ONE: Float = 0.40f
    private const val FINGER_TWO: Float = 0.60f

    private const val MSG_BAD_SCREEN: String = "স্ক্রিনের মাপ জানা যায়নি।"
    private const val MSG_BAD_POINT: String = "জায়গাটা স্ক্রিনের বাইরে।"
    private const val MSG_BAD_NUMBER: String = "ইশারার মান ঠিক নয়।"

    /** A single quick tap at ([x], [y]). */
    fun tap(x: Float, y: Float, screenWidth: Int, screenHeight: Int): NovaResult<GesturePlan> {
        checkPoint(x, y, screenWidth, screenHeight)?.let { return it }
        return NovaResult.Success(GesturePlan(listOf(touch(GesturePoint(x, y), 0L, TAP_DURATION_MS))))
    }

    /** Two quick taps at ([x], [y]), close enough for the phone to see a double tap. */
    fun doubleTap(x: Float, y: Float, screenWidth: Int, screenHeight: Int): NovaResult<GesturePlan> {
        checkPoint(x, y, screenWidth, screenHeight)?.let { return it }
        val point = GesturePoint(x, y)
        val secondStart: Long = TAP_DURATION_MS + DOUBLE_TAP_GAP_MS
        return NovaResult.Success(
            GesturePlan(
                listOf(
                    touch(point, 0L, TAP_DURATION_MS),
                    touch(point, secondStart, TAP_DURATION_MS)
                )
            )
        )
    }

    /** Holds the finger at ([x], [y]) for [holdMs] (kept between 0.6 and 5 seconds). */
    fun longPress(
        x: Float,
        y: Float,
        screenWidth: Int,
        screenHeight: Int,
        holdMs: Long
    ): NovaResult<GesturePlan> {
        checkPoint(x, y, screenWidth, screenHeight)?.let { return it }
        val hold: Long = holdMs.coerceIn(MIN_LONG_PRESS_MS, MAX_LONG_PRESS_MS)
        return NovaResult.Success(GesturePlan(listOf(touch(GesturePoint(x, y), 0L, hold))))
    }

    /**
     * One finger swipes through the middle of the screen in [direction]. [distanceFraction]
     * is the share of the screen side that the finger covers (kept between 0.15 and 0.70).
     */
    fun swipe(
        direction: SwipeDirection,
        screenWidth: Int,
        screenHeight: Int,
        distanceFraction: Float = DEFAULT_SWIPE_FRACTION,
        durationMs: Long = DEFAULT_SWIPE_DURATION_MS
    ): NovaResult<GesturePlan> {
        checkScreen(screenWidth, screenHeight)?.let { return it }
        if (distanceFraction.isNaN()) return NovaResult.failure(ErrorCode.INVALID_INPUT, MSG_BAD_NUMBER)
        val fraction: Float = distanceFraction.coerceIn(MIN_SWIPE_FRACTION, MAX_SWIPE_FRACTION)
        val duration: Long = durationMs.coerceIn(MIN_SWIPE_DURATION_MS, MAX_SWIPE_DURATION_MS)
        val stroke: GestureStroke =
            line(direction, screenWidth, screenHeight, fraction, CENTER, duration)
        return NovaResult.Success(GesturePlan(listOf(stroke)))
    }

    /** Two fingers swipe side by side in [direction]. Same limits as [swipe]. */
    fun twoFingerSwipe(
        direction: SwipeDirection,
        screenWidth: Int,
        screenHeight: Int,
        distanceFraction: Float = DEFAULT_SWIPE_FRACTION,
        durationMs: Long = DEFAULT_SWIPE_DURATION_MS
    ): NovaResult<GesturePlan> {
        checkScreen(screenWidth, screenHeight)?.let { return it }
        if (distanceFraction.isNaN()) return NovaResult.failure(ErrorCode.INVALID_INPUT, MSG_BAD_NUMBER)
        val fraction: Float = distanceFraction.coerceIn(MIN_SWIPE_FRACTION, MAX_SWIPE_FRACTION)
        val duration: Long = durationMs.coerceIn(MIN_SWIPE_DURATION_MS, MAX_SWIPE_DURATION_MS)
        return NovaResult.Success(
            GesturePlan(
                listOf(
                    line(direction, screenWidth, screenHeight, fraction, FINGER_ONE, duration),
                    line(direction, screenWidth, screenHeight, fraction, FINGER_TWO, duration)
                )
            )
        )
    }

    /** Two fingers move apart ([PinchMode.OUT]) or together ([PinchMode.IN]) around the middle. */
    fun pinch(mode: PinchMode, screenWidth: Int, screenHeight: Int): NovaResult<GesturePlan> {
        checkScreen(screenWidth, screenHeight)?.let { return it }
        val centerX: Float = screenWidth * CENTER
        val centerY: Float = screenHeight * CENTER
        val near: Float = screenWidth * PINCH_NEAR
        val far: Float = screenWidth * PINCH_FAR

        val startOffset: Float = if (mode == PinchMode.OUT) near else far
        val endOffset: Float = if (mode == PinchMode.OUT) far else near
        val left = GestureStroke(
            start = GesturePoint(centerX - startOffset, centerY),
            end = GesturePoint(centerX - endOffset, centerY),
            startDelayMs = 0L,
            durationMs = PINCH_DURATION_MS
        )
        val right = GestureStroke(
            start = GesturePoint(centerX + startOffset, centerY),
            end = GesturePoint(centerX + endOffset, centerY),
            startDelayMs = 0L,
            durationMs = PINCH_DURATION_MS
        )
        return NovaResult.Success(GesturePlan(listOf(left, right)))
    }

    // ---------------------------------------------------------------- helpers

    private fun touch(point: GesturePoint, startDelayMs: Long, durationMs: Long): GestureStroke =
        GestureStroke(start = point, end = point, startDelayMs = startDelayMs, durationMs = durationMs)

    // A straight finger line through the screen. [cross] places it across the swipe direction.
    private fun line(
        direction: SwipeDirection,
        width: Int,
        height: Int,
        fraction: Float,
        cross: Float,
        durationMs: Long
    ): GestureStroke {
        val half: Float = fraction / 2f
        val low: Float = CENTER - half
        val high: Float = CENTER + half
        val (start: GesturePoint, end: GesturePoint) = when (direction) {
            SwipeDirection.UP ->
                GesturePoint(width * cross, height * high) to GesturePoint(width * cross, height * low)
            SwipeDirection.DOWN ->
                GesturePoint(width * cross, height * low) to GesturePoint(width * cross, height * high)
            SwipeDirection.LEFT ->
                GesturePoint(width * high, height * cross) to GesturePoint(width * low, height * cross)
            SwipeDirection.RIGHT ->
                GesturePoint(width * low, height * cross) to GesturePoint(width * high, height * cross)
        }
        return GestureStroke(start = start, end = end, startDelayMs = 0L, durationMs = durationMs)
    }

    private fun checkScreen(width: Int, height: Int): NovaResult.Failure? =
        if (width <= 0 || height <= 0) NovaResult.failure(ErrorCode.INVALID_INPUT, MSG_BAD_SCREEN) else null

    private fun checkPoint(x: Float, y: Float, width: Int, height: Int): NovaResult.Failure? {
        checkScreen(width, height)?.let { return it }
        val inside: Boolean = !x.isNaN() && !y.isNaN() && x >= 0f && y >= 0f && x < width && y < height
        return if (inside) null else NovaResult.failure(ErrorCode.INVALID_INPUT, MSG_BAD_POINT)
    }
}
EOF

# ---------- 3. GestureRunner.kt (tap and swipe kept; multi-finger plans added) ----------
cat > "$BASE/accessibility/GestureRunner.kt" <<'EOF'
package com.nova.ai.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Handler
import android.os.HandlerThread
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Performs touch gestures (taps, swipes, long presses, two-finger gestures) through the
 * accessibility service and waits until the phone says the gesture finished. Results come
 * on a helper thread, so waiting never blocks the screen thread. Every gesture first
 * checks the emergency stop.
 */
internal object GestureRunner {

    private const val TAG: String = "GestureRunner"
    private const val WAIT_MARGIN_MS: Long = 1500L

    private const val MSG_REFUSED: String = "ফোন এই ইশারা নিতে রাজি হয়নি।"
    private const val MSG_NOT_DONE: String = "ইশারা সম্পন্ন হয়নি। স্ক্রিন এটা আটকে থাকতে পারে।"
    private const val MSG_FAILED: String = "ইশারা দিতে সমস্যা হয়েছে।"
    private const val MSG_TOO_COMPLEX: String = "এই ইশারা ফোনের সীমার চেয়ে বড়।"

    private val workerThread: HandlerThread = HandlerThread("nova-gesture").apply { start() }
    private val workerHandler: Handler = Handler(workerThread.looper)

    /** Taps the screen at ([x], [y]) in pixels. */
    fun tap(service: AccessibilityService, x: Float, y: Float): NovaResult<Unit> {
        val point = GesturePoint(x, y)
        val stroke = GestureStroke(point, point, 0L, GestureGeometry.TAP_DURATION_MS)
        return execute(service, GesturePlan(listOf(stroke)))
    }

    /** Swipes from the start point to the end point over [durationMs]. */
    fun swipe(
        service: AccessibilityService,
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float,
        durationMs: Long
    ): NovaResult<Unit> {
        val stroke = GestureStroke(GesturePoint(startX, startY), GesturePoint(endX, endY), 0L, durationMs)
        return execute(service, GesturePlan(listOf(stroke)))
    }

    /** Performs every finger of [plan] at the same time (with their own delays) and waits for the end. */
    fun execute(service: AccessibilityService, plan: GesturePlan): NovaResult<Unit> {
        ActionGate.check()?.let { return it }

        if (plan.strokes.isEmpty() ||
            plan.strokes.size > GestureDescription.getMaxStrokeCount() ||
            plan.totalDurationMs > GestureDescription.getMaxGestureDuration()
        ) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, MSG_TOO_COMPLEX)
        }

        return try {
            val builder = GestureDescription.Builder()
            for (stroke in plan.strokes) {
                builder.addStroke(
                    GestureDescription.StrokeDescription(
                        pathOf(stroke),
                        stroke.startDelayMs,
                        stroke.durationMs
                    )
                )
            }
            val gesture: GestureDescription = builder.build()
            val finished = CountDownLatch(1)
            val completed = AtomicBoolean(false)
            val callback = object : AccessibilityService.GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    completed.set(true)
                    finished.countDown()
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    finished.countDown()
                }
            }

            if (!service.dispatchGesture(gesture, callback, workerHandler)) {
                return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_REFUSED)
            }
            finished.await(plan.totalDurationMs + WAIT_MARGIN_MS, TimeUnit.MILLISECONDS)
            if (completed.get()) {
                NovaResult.Success(Unit)
            } else {
                NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_NOT_DONE)
            }
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            NovaResult.failure(ErrorCode.CANCELLED, MSG_NOT_DONE, e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Gesture failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_FAILED, e)
        }
    }

    // A tap or a long press stays on one spot, so its path is only a starting point.
    private fun pathOf(stroke: GestureStroke): Path = Path().apply {
        moveTo(stroke.start.x, stroke.start.y)
        if (stroke.end != stroke.start) lineTo(stroke.end.x, stroke.end.y)
    }
}
EOF

# ---------- 4. GestureActions.kt ----------
cat > "$BASE/accessibility/GestureActions.kt" <<'EOF'
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
EOF

# ---------- 5. GestureEngine.kt ----------
cat > "$BASE/accessibility/GestureEngine.kt" <<'EOF'
package com.nova.ai.accessibility

import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenNode

/** Finger gestures on the screen, for the task planner of a later phase. Blocking calls. */
interface GestureEngine {
    /** Swipes with one finger in [direction]. */
    fun swipe(
        direction: SwipeDirection,
        distanceFraction: Float = GestureGeometry.DEFAULT_SWIPE_FRACTION
    ): NovaResult<Unit>

    /** Swipes with two fingers side by side in [direction]. */
    fun twoFingerSwipe(
        direction: SwipeDirection,
        distanceFraction: Float = GestureGeometry.DEFAULT_SWIPE_FRACTION
    ): NovaResult<Unit>

    /** Long-presses the given [node]. */
    fun longPress(node: ScreenNode): NovaResult<Unit>

    /** Double-taps the given [node]. */
    fun doubleTap(node: ScreenNode): NovaResult<Unit>

    /** Zooms with two fingers ([PinchMode.OUT] zooms in, [PinchMode.IN] zooms out). */
    fun pinch(mode: PinchMode): NovaResult<Unit>
}
EOF

# ---------- 6. NovaGestureEngine.kt ----------
cat > "$BASE/accessibility/NovaGestureEngine.kt" <<'EOF'
package com.nova.ai.accessibility

import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenNode

/** The real [GestureEngine]: every gesture goes through [AccessibilityBridge]. */
class NovaGestureEngine : GestureEngine {

    override fun swipe(direction: SwipeDirection, distanceFraction: Float): NovaResult<Unit> =
        AccessibilityBridge.swipe(direction, distanceFraction)

    override fun twoFingerSwipe(direction: SwipeDirection, distanceFraction: Float): NovaResult<Unit> =
        AccessibilityBridge.twoFingerSwipe(direction, distanceFraction)

    override fun longPress(node: ScreenNode): NovaResult<Unit> =
        AccessibilityBridge.longPress(targetOf(node))

    override fun doubleTap(node: ScreenNode): NovaResult<Unit> =
        AccessibilityBridge.doubleTap(targetOf(node))

    override fun pinch(mode: PinchMode): NovaResult<Unit> = AccessibilityBridge.pinch(mode)

    // A snapshot item has no saved path, so the live screen is searched by position and class.
    private fun targetOf(node: ScreenNode): NodeTarget =
        NodeTarget(path = null, bounds = node.bounds, className = node.className.orEmpty(), viewId = "")
}
EOF

# ---------- 7. ActionLab.kt (all P19 actions kept; gestures added) ----------
cat > "$BASE/accessibility/ActionLab.kt" <<'EOF'
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
EOF

# ---------- 8. ActionLabCard.kt (all P19 buttons kept; gesture buttons added) ----------
cat > "$BASE/ui/components/ActionLabCard.kt" <<'EOF'
package com.nova.ai.ui.components

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.accessibility.AccessibilityBridge
import com.nova.ai.accessibility.ActionGate
import com.nova.ai.accessibility.ActionLab
import com.nova.ai.accessibility.ActionLabMessage
import com.nova.ai.accessibility.LabAction

/**
 * Test card for NOVA's hands: click a button by its name, type into a field, scroll,
 * press Back, Home or recent apps, and make finger gestures (swipe, long press, double tap,
 * pinch, two-finger swipe). With the 5-second option the action runs after a countdown,
 * so it can be tested on another app. Also tests the emergency stop.
 */
@Composable
fun ActionLabCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val connected: Boolean = AccessibilityBridge.isConnected
    val waitingSeconds: Int = ActionLab.waitingSeconds
    val message: ActionLabMessage? = ActionLab.message
    val stopped: Boolean = ActionGate.isStopped

    var query: String by rememberSaveable { mutableStateOf("") }
    var typed: String by rememberSaveable { mutableStateOf("") }
    var delayed: Boolean by rememberSaveable { mutableStateOf(false) }

    fun run(action: LabAction) {
        ActionLab.run(context, action, query, typed, delayed)
    }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.act_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.act_note),
                style = MaterialTheme.typography.bodySmall
            )
            if (!connected) {
                Text(
                    text = stringResource(R.string.act_need_service),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }

            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text(stringResource(R.string.act_query_label)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedTextField(
                value = typed,
                onValueChange = { typed = it },
                label = { Text(stringResource(R.string.act_text_label)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.act_delay_label),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f)
                )
                Switch(checked = delayed, onCheckedChange = { delayed = it })
            }

            if (waitingSeconds > 0) {
                Text(text = stringResource(R.string.act_waiting, waitingSeconds))
                OutlinedButton(
                    onClick = { ActionLab.cancel() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.act_cancel))
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = { run(LabAction.CLICK) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_click))
                }
                Button(
                    onClick = { run(LabAction.TYPE) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_type))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { run(LabAction.SCROLL_UP) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_scroll_up))
                }
                OutlinedButton(
                    onClick = { run(LabAction.SCROLL_DOWN) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_scroll_down))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { run(LabAction.BACK) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_back))
                }
                OutlinedButton(
                    onClick = { run(LabAction.HOME) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_home))
                }
                OutlinedButton(
                    onClick = { run(LabAction.RECENTS) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_recents))
                }
            }

            Text(
                text = stringResource(R.string.gst_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.gst_note),
                style = MaterialTheme.typography.bodySmall
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_swipe_up, connected) { run(LabAction.SWIPE_UP) }
                GestureButton(R.string.gst_swipe_down, connected) { run(LabAction.SWIPE_DOWN) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_swipe_left, connected) { run(LabAction.SWIPE_LEFT) }
                GestureButton(R.string.gst_swipe_right, connected) { run(LabAction.SWIPE_RIGHT) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_long_press, connected) { run(LabAction.LONG_PRESS) }
                GestureButton(R.string.gst_double_tap, connected) { run(LabAction.DOUBLE_TAP) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_pinch_out, connected) { run(LabAction.PINCH_OUT) }
                GestureButton(R.string.gst_pinch_in, connected) { run(LabAction.PINCH_IN) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_two_up, connected) { run(LabAction.TWO_FINGER_UP) }
                GestureButton(R.string.gst_two_down, connected) { run(LabAction.TWO_FINGER_DOWN) }
            }

            message?.let { shown ->
                Text(
                    text = (if (shown.success) "✅ " else "⚠️ ") + shown.text,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (shown.success) {
                        MaterialTheme.colorScheme.onSurface
                    } else {
                        MaterialTheme.colorScheme.error
                    }
                )
            }

            Text(
                text = stringResource(R.string.act_stop_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(if (stopped) R.string.act_stop_on else R.string.act_stop_off),
                style = MaterialTheme.typography.bodySmall
            )
            OutlinedButton(
                onClick = { if (stopped) ActionGate.resume() else ActionGate.stop() },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    stringResource(if (stopped) R.string.act_stop_disable else R.string.act_stop_enable)
                )
            }
        }
    }
}

// One equally wide gesture button inside a row of the test card.
@Composable
private fun RowScope.GestureButton(label: Int, enabled: Boolean, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.weight(1f)
    ) {
        Text(stringResource(label))
    }
}
EOF

# ---------- B. AccessibilityBridge.kt: gesture functions inserted (idempotent) ----------
if ! grep -q "GestureActions" "$BRIDGE_FILE"; then
  cat > "$TMP_DIR/bridge_gestures.txt" <<'EOF'

    // ---------------------------------------------------------------- gestures (P20)

    /** Swipes with one finger in [direction]; the finger covers [distanceFraction] of the screen side. */
    fun swipe(
        direction: SwipeDirection,
        distanceFraction: Float = GestureGeometry.DEFAULT_SWIPE_FRACTION
    ): NovaResult<Unit> = withService { service ->
        GestureActions.swipe(service, direction, distanceFraction, GestureGeometry.DEFAULT_SWIPE_DURATION_MS)
    }

    /** Swipes with two fingers side by side in [direction]. */
    fun twoFingerSwipe(
        direction: SwipeDirection,
        distanceFraction: Float = GestureGeometry.DEFAULT_SWIPE_FRACTION
    ): NovaResult<Unit> = withService { service ->
        GestureActions.twoFingerSwipe(service, direction, distanceFraction, GestureGeometry.DEFAULT_SWIPE_DURATION_MS)
    }

    /** Long-presses the item described by [target]. */
    fun longPress(target: NodeTarget): NovaResult<Unit> =
        withService { service -> GestureActions.longPress(service, target) }

    /** Double-taps the item described by [target]. */
    fun doubleTap(target: NodeTarget): NovaResult<Unit> =
        withService { service -> GestureActions.doubleTap(service, target) }

    /** Zooms with two fingers around the middle of the screen. */
    fun pinch(mode: PinchMode): NovaResult<Unit> =
        withService { service -> GestureActions.pinch(service, mode) }
EOF
  sed -i "/^        performGlobal(AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS)$/r $TMP_DIR/bridge_gestures.txt" "$BRIDGE_FILE"
fi
grep -q "GestureActions.longPress" "$BRIDGE_FILE" || { echo "ERROR: AccessibilityBridge edit failed" >&2; exit 1; }

# ---------- C. README.md (only if the repo has none yet) ----------
if [ ! -f README.md ]; then
  cat > README.md <<'EOF'
# NOVA AI

Android-এর জন্য Personal Phone Agent: বাংলা ও ইংরেজি ভয়েসে ফোন চালায়। Paid API লাগে না, root লাগে না, অফলাইনেও কাজ করতে পারে।

## Build

GitHub Actions (`.github/workflows/build-apk.yml`) debug APK বানায়। `main`-এ push করলে বা Actions ট্যাব থেকে হাতে চালালে `nova-ai-debug-apk` নামে APK পাওয়া যায়।

## Project layout

- `app/src/main/java/com/nova/ai/` : Kotlin কোড, প্রতিটি মডিউল আলাদা প্যাকেজে (voice, nlp, apps, accessibility ইত্যাদি)।
- `setup-*.sh` : প্রতিটি ফেজের ইনস্টল স্ক্রিপ্ট। রিপো রুট থেকে চালাতে হয়।

## Rules

1. কোনো ফিচার বাদ যাবে না, শুধু যোগ হবে।
2. কোড প্রফেশনাল হবে: টাইপড ভ্যারিয়েবল, এরর হ্যান্ডলিং, কমেন্ট।
3. প্রতিটি ফেজ শেষে commit এবং APK টেস্ট।
EOF
fi

# ---------- Commit and push ----------
git add -A
if git diff --cached --quiet; then
  echo "Nothing new to commit."
else
  git commit -m "P20: swipe, long press, double tap and two-finger gestures with the emergency-stop gate"
  git push
fi

echo "P20 files created and pushed."
