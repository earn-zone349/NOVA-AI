#!/usr/bin/env bash
# NOVA AI - fix pack for P20 and P21 (run after P21 is installed).
#  1. Long press and double tap now look up the item on the live screen and use where it is now;
#     if the item is gone or not visible they fail instead of touching an old position.
#  2. A step can say what it is expected to cause (ExpectedOutcome): a screen change, no change,
#     a text on the screen, or an app in front. The default is the old behavior.
#  3. Unit tests for the gesture paths and the verification engine, run by GitHub Actions.
# Additive: GestureActions and ScreenVerificationEngine are rewritten with every feature kept;
# TaskStep gets two optional fields; build files get the test setup.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
TEST_BASE="app/src/test/java/com/nova/ai"
MODELS_FILE="$BASE/core/Models.kt"
APP_GRADLE="app/build.gradle.kts"
VERSIONS_FILE="gradle/libs.versions.toml"
WORKFLOW=".github/workflows/build-apk.yml"

for required in \
  "$BASE/accessibility/GestureActions.kt" \
  "$BASE/accessibility/GestureGeometry.kt" \
  "$BASE/verification/ScreenVerificationEngine.kt" \
  "$BASE/verification/VerifiedStepRunner.kt" \
  "$MODELS_FILE" "$APP_GRADLE" "$VERSIONS_FILE" "$WORKFLOW"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after P21 is installed." >&2
    exit 1
  fi
done

# Stop early if an edit below cannot be placed.
if ! grep -q "val expectedValue: String? = null" "$MODELS_FILE"; then
  [ "$(grep -c '^    val requiresConfirmation: Boolean = false$' "$MODELS_FILE")" = "1" ] \
    || { echo "ERROR: Models.kt anchor not found" >&2; exit 1; }
fi
if ! grep -q "^junit = " "$VERSIONS_FILE"; then
  grep -q '^navigationCompose = ' "$VERSIONS_FILE" \
    || { echo "ERROR: libs.versions.toml anchor (versions) not found" >&2; exit 1; }
  grep -q '^androidx-navigation-compose = ' "$VERSIONS_FILE" \
    || { echo "ERROR: libs.versions.toml anchor (libraries) not found" >&2; exit 1; }
fi
if ! grep -q "libs.junit" "$APP_GRADLE"; then
  grep -qxF '    ksp(libs.androidx.room.compiler)' "$APP_GRADLE" \
    || { echo "ERROR: app/build.gradle.kts anchor (dependencies) not found" >&2; exit 1; }
fi
if ! grep -q "isReturnDefaultValues" "$APP_GRADLE"; then
  grep -qxF '    packaging {' "$APP_GRADLE" \
    || { echo "ERROR: app/build.gradle.kts anchor (packaging) not found" >&2; exit 1; }
fi

mkdir -p "$TEST_BASE/accessibility" "$TEST_BASE/verification"

# ---------- 1. ExpectedOutcome.kt ----------
cat > "$BASE/core/ExpectedOutcome.kt" <<'EOF'
package com.nova.ai.core

/**
 * What a step is expected to cause on the screen. The task planner sets this for each step, so
 * the verification engine checks the right thing: a copy or a button that only plays a sound
 * changes nothing visible, while opening a page must show that page.
 */
enum class ExpectedOutcome {
    /** Something on the screen changes. This is the default. */
    SCREEN_CHANGES,

    /** Nothing visible needs to change (for example a copy, or a button that only plays a sound). */
    NO_CHANGE_EXPECTED,

    /** The text in [TaskStep.expectedValue] shows up on the screen, outside of input fields. */
    TEXT_VISIBLE,

    /** The app with the package name in [TaskStep.expectedValue] is in front. */
    APP_IN_FRONT
}
EOF

# ---------- 2. GestureActions.kt (live item lookup for long press and double tap) ----------
cat > "$BASE/accessibility/GestureActions.kt" <<'EOF'
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
EOF

# ---------- 3. ScreenVerificationEngine.kt (expected outcomes added) ----------
cat > "$BASE/verification/ScreenVerificationEngine.kt" <<'EOF'
package com.nova.ai.verification

import com.nova.ai.accessibility.SensitiveNodePolicy
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.ExpectedOutcome
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.StepAction
import com.nova.ai.core.TaskStep
import com.nova.ai.core.VerificationReport
import com.nova.ai.logging.NovaLogger

/**
 * The real [VerificationEngine]. After a step it looks at the screen again and decides whether
 * the step really did what it was expected to do ([TaskStep.expected]):
 * - [ExpectedOutcome.SCREEN_CHANGES] (the default): the screen is different from before.
 * - [ExpectedOutcome.NO_CHANGE_EXPECTED]: nothing needs to change, the step passes.
 * - [ExpectedOutcome.TEXT_VISIBLE]: the text in [TaskStep.expectedValue] is on the screen.
 * - [ExpectedOutcome.APP_IN_FRONT]: the app in [TaskStep.expectedValue] is in front.
 * Typed text ([StepAction.TYPE_TEXT]) must show up in a text field. Texts of the screen are never logged.
 */
class ScreenVerificationEngine : VerificationEngine {

    override fun verify(
        step: TaskStep,
        before: ScreenSnapshot?,
        after: ScreenSnapshot?
    ): NovaResult<VerificationReport> = try {
        NovaResult.Success(decide(step, before, after))
    } catch (e: Exception) {
        NovaLogger.e(TAG, "Verification failed", e)
        NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_UNEXPECTED, e)
    }

    private fun decide(step: TaskStep, before: ScreenSnapshot?, after: ScreenSnapshot?): VerificationReport {
        if (after == null) return report(step, false, MSG_NO_AFTER)
        return when (step.action) {
            StepAction.CLICK, StepAction.SCROLL, StepAction.BACK, StepAction.HOME, StepAction.OPEN_APP ->
                expectOutcome(step, before, after)
            StepAction.TYPE_TEXT -> expectTyped(step, after)
            StepAction.WAIT, StepAction.CONFIRM, StepAction.SPEAK ->
                report(step, true, MSG_NOTHING_TO_CHECK)
        }
    }

    private fun expectOutcome(step: TaskStep, before: ScreenSnapshot?, after: ScreenSnapshot): VerificationReport =
        when (step.expected) {
            ExpectedOutcome.SCREEN_CHANGES -> expectChange(step, before, after)
            ExpectedOutcome.NO_CHANGE_EXPECTED -> report(step, true, MSG_NO_CHANGE_OK)
            ExpectedOutcome.TEXT_VISIBLE -> expectVisibleText(step, after)
            ExpectedOutcome.APP_IN_FRONT -> expectApp(step, after)
        }

    private fun expectChange(step: TaskStep, before: ScreenSnapshot?, after: ScreenSnapshot): VerificationReport {
        if (before == null) return report(step, false, MSG_NO_BEFORE)
        val changed: Boolean = ScreenDiff.packageChanged(before, after) ||
            ScreenDiff.changedNodeCount(before, after) >= MIN_CHANGED_NODES
        val opensApp: Boolean = step.action == StepAction.OPEN_APP
        return when {
            changed && opensApp -> report(step, true, MSG_APP_OPENED)
            changed -> report(step, true, MSG_SCREEN_CHANGED)
            opensApp -> report(step, false, MSG_APP_SAME)
            else -> report(step, false, MSG_SCREEN_SAME)
        }
    }

    // The text must be on the screen outside of input fields, so a typed search word in the
    // search box does not count as "the results page is open".
    private fun expectVisibleText(step: TaskStep, after: ScreenSnapshot): VerificationReport {
        val value: String = step.expectedValue.orEmpty()
        if (value.isBlank()) return report(step, false, MSG_NO_EXPECTED_VALUE)
        val expected: String = tidy(SensitiveNodePolicy.maskCodes(value))
        val found: Boolean = after.nodes.any { node -> !node.isEditable && showsText(node, expected) }
        return if (found) report(step, true, MSG_TEXT_SHOWN) else report(step, false, MSG_TEXT_NOT_SHOWN)
    }

    private fun expectApp(step: TaskStep, after: ScreenSnapshot): VerificationReport {
        val expectedPackage: String = step.expectedValue.orEmpty().trim()
        if (expectedPackage.isEmpty()) return report(step, false, MSG_NO_EXPECTED_VALUE)
        val inFront: Boolean = after.packageName == expectedPackage
        return if (inFront) report(step, true, MSG_APP_OPENED) else report(step, false, MSG_APP_SAME)
    }

    private fun expectTyped(step: TaskStep, after: ScreenSnapshot): VerificationReport {
        val value: String = step.value.orEmpty()
        if (value.isBlank()) return report(step, false, MSG_NO_TEXT)
        // The screen reader hides code-like digits, so the expected text is hidden the same way.
        val expected: String = tidy(SensitiveNodePolicy.maskCodes(value))
        val found: Boolean = after.nodes.any { node -> node.isEditable && tidy(node.text.orEmpty()).contains(expected) }
        return if (found) report(step, true, MSG_TEXT_FOUND) else report(step, false, MSG_TEXT_MISSING)
    }

    private fun showsText(node: ScreenNode, expected: String): Boolean =
        listOf(node.text, node.contentDescription).any { label ->
            tidy(label.orEmpty()).contains(expected, ignoreCase = true)
        }

    private fun tidy(text: String): String = text.trim().replace(WHITESPACE, " ")

    private fun report(step: TaskStep, passed: Boolean, detail: String): VerificationReport =
        VerificationReport(stepId = step.id, passed = passed, detail = detail)

    private companion object {
        const val TAG: String = "ScreenVerification"
        const val MIN_CHANGED_NODES: Int = 1
        val WHITESPACE: Regex = Regex("\\s+")

        const val MSG_NO_AFTER: String = "কাজের পরের স্ক্রিন পড়া যায়নি, তাই যাচাই করা গেল না।"
        const val MSG_NO_BEFORE: String = "কাজের আগের স্ক্রিন পড়া যায়নি, তাই যাচাই করা গেল না।"
        const val MSG_SCREEN_CHANGED: String = "স্ক্রিন বদলেছে।"
        const val MSG_SCREEN_SAME: String = "স্ক্রিন বদলায়নি। কাজটা হয়নি বলে মনে হচ্ছে।"
        const val MSG_APP_OPENED: String = "অ্যাপ খুলেছে।"
        const val MSG_APP_SAME: String = "অ্যাপ খোলার কোনো চিহ্ন দেখা যায়নি।"
        const val MSG_NO_CHANGE_OK: String = "স্ক্রিন না বদলানোই প্রত্যাশিত ছিল।"
        const val MSG_TEXT_SHOWN: String = "প্রত্যাশিত লেখা স্ক্রিনে দেখা যাচ্ছে।"
        const val MSG_TEXT_NOT_SHOWN: String = "প্রত্যাশিত লেখা স্ক্রিনে দেখা গেল না।"
        const val MSG_NO_EXPECTED_VALUE: String = "কী দেখার কথা তা জানা নেই।"
        const val MSG_TEXT_FOUND: String = "লেখাটা ঘরে দেখা যাচ্ছে।"
        const val MSG_TEXT_MISSING: String = "লেখাটা কোনো ঘরে দেখা গেল না।"
        const val MSG_NO_TEXT: String = "কী লেখার কথা তা জানা নেই।"
        const val MSG_NOTHING_TO_CHECK: String = "এই ধাপে যাচাই করার কিছু নেই।"
        const val MSG_UNEXPECTED: String = "যাচাই করতে সমস্যা হয়েছে।"
    }
}
EOF

# ---------- 4. GestureGeometryTest.kt ----------
cat > "$TEST_BASE/accessibility/GestureGeometryTest.kt" <<'EOF'
package com.nova.ai.accessibility

import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests the finger paths of [GestureGeometry]. Plain JVM test, no phone needed. */
class GestureGeometryTest {

    private val width = 1080
    private val height = 2400

    private fun planOf(result: NovaResult<GesturePlan>): GesturePlan = when (result) {
        is NovaResult.Success -> result.value
        is NovaResult.Failure -> throw AssertionError("Expected a plan but got: ${result.error.message}")
    }

    private fun assertRejected(result: NovaResult<GesturePlan>) {
        assertTrue("Expected a failure", result is NovaResult.Failure)
        assertEquals(ErrorCode.INVALID_INPUT, (result as NovaResult.Failure).error.code)
    }

    @Test
    fun swipeUpMovesTheFingerUpThroughTheMiddle() {
        val stroke = planOf(GestureGeometry.swipe(SwipeDirection.UP, width, height)).strokes.single()
        assertTrue(stroke.end.y < stroke.start.y)
        assertEquals(540f, stroke.start.x, 0.01f)
        assertEquals(540f, stroke.end.x, 0.01f)
        assertEquals(height * 0.45f, stroke.start.y - stroke.end.y, 0.01f)
    }

    @Test
    fun swipeDirectionsMoveTheFingerTheRightWay() {
        val down = planOf(GestureGeometry.swipe(SwipeDirection.DOWN, width, height)).strokes.single()
        val left = planOf(GestureGeometry.swipe(SwipeDirection.LEFT, width, height)).strokes.single()
        val right = planOf(GestureGeometry.swipe(SwipeDirection.RIGHT, width, height)).strokes.single()
        assertTrue(down.end.y > down.start.y)
        assertTrue(left.end.x < left.start.x)
        assertTrue(right.end.x > right.start.x)
        assertEquals(1200f, left.start.y, 0.01f)
    }

    @Test
    fun longestSwipeStaysAwayFromTheScreenEdges() {
        for (direction in SwipeDirection.values()) {
            val stroke = planOf(GestureGeometry.swipe(direction, width, height, 5f, 99_999L)).strokes.single()
            for (point in listOf(stroke.start, stroke.end)) {
                assertTrue(point.x in width * 0.14f..width * 0.86f)
                assertTrue(point.y in height * 0.14f..height * 0.86f)
            }
            assertEquals(GestureGeometry.MAX_SWIPE_DURATION_MS, stroke.durationMs)
        }
    }

    @Test
    fun shortestSwipeIsLimitedFromBelow() {
        val stroke = planOf(GestureGeometry.swipe(SwipeDirection.UP, width, height, 0f, 1L)).strokes.single()
        assertEquals(height * 0.15f, stroke.start.y - stroke.end.y, 0.01f)
        assertEquals(GestureGeometry.MIN_SWIPE_DURATION_MS, stroke.durationMs)
    }

    @Test
    fun badNumbersAreRejected() {
        assertRejected(GestureGeometry.swipe(SwipeDirection.UP, width, height, Float.NaN))
        assertRejected(GestureGeometry.swipe(SwipeDirection.UP, 0, height))
        assertRejected(GestureGeometry.tap(Float.NaN, 5f, width, height))
        assertRejected(GestureGeometry.longPress(-1f, 5f, width, height, 900L))
        assertRejected(GestureGeometry.longPress(width.toFloat(), 5f, width, height, 900L))
    }

    @Test
    fun twoFingerSwipeUsesTwoFingersAtTheSameTime() {
        val plan = planOf(GestureGeometry.twoFingerSwipe(SwipeDirection.UP, width, height))
        assertEquals(2, plan.strokes.size)
        assertTrue(plan.strokes.all { it.startDelayMs == 0L })
        assertEquals(width * 0.4f, plan.strokes[0].start.x, 0.01f)
        assertEquals(width * 0.6f, plan.strokes[1].start.x, 0.01f)
    }

    @Test
    fun longPressStaysOnOneSpotAndIsLimited() {
        val stroke = planOf(GestureGeometry.longPress(100f, 200f, width, height, 900L)).strokes.single()
        assertEquals(stroke.start, stroke.end)
        assertEquals(900L, stroke.durationMs)
        val short = planOf(GestureGeometry.longPress(1f, 1f, width, height, 10L)).strokes.single()
        val long = planOf(GestureGeometry.longPress(1f, 1f, width, height, 99_999L)).strokes.single()
        assertEquals(GestureGeometry.MIN_LONG_PRESS_MS, short.durationMs)
        assertEquals(GestureGeometry.MAX_LONG_PRESS_MS, long.durationMs)
    }

    @Test
    fun doubleTapIsTwoQuickTapsOnTheSameSpot() {
        val plan = planOf(GestureGeometry.doubleTap(300f, 400f, width, height))
        assertEquals(2, plan.strokes.size)
        assertEquals(plan.strokes[0].start, plan.strokes[1].start)
        assertEquals(GestureGeometry.TAP_DURATION_MS + GestureGeometry.DOUBLE_TAP_GAP_MS, plan.strokes[1].startDelayMs)
        assertEquals(220L, plan.totalDurationMs)
    }

    @Test
    fun pinchMovesTheFingersApartOrTogether() {
        val out = planOf(GestureGeometry.pinch(PinchMode.OUT, width, height)).strokes
        val inward = planOf(GestureGeometry.pinch(PinchMode.IN, width, height)).strokes
        assertTrue(out[0].end.x < out[0].start.x && out[1].end.x > out[1].start.x)
        assertTrue(inward[0].end.x > inward[0].start.x && inward[1].end.x < inward[1].start.x)
        // Pinch in is pinch out played backwards.
        assertEquals(out[0].start, inward[0].end)
        assertEquals(out[0].end, inward[0].start)
        for (stroke in out + inward) {
            for (point in listOf(stroke.start, stroke.end)) {
                assertTrue(point.x in 0f..width.toFloat())
                assertTrue(point.y in 0f..height.toFloat())
            }
        }
    }

    @Test
    fun totalDurationIsTheLongestFinger() {
        val plan = GesturePlan(
            listOf(
                GestureStroke(GesturePoint(0f, 0f), GesturePoint(1f, 1f), 0L, 100L),
                GestureStroke(GesturePoint(0f, 0f), GesturePoint(1f, 1f), 50L, 300L)
            )
        )
        assertEquals(350L, plan.totalDurationMs)
        assertFalse(GesturePlan(emptyList()).totalDurationMs > 0L)
    }
}
EOF

# ---------- 5. ScreenVerificationEngineTest.kt ----------
cat > "$TEST_BASE/verification/ScreenVerificationEngineTest.kt" <<'EOF'
package com.nova.ai.verification

import com.nova.ai.accessibility.SensitiveNodePolicy
import com.nova.ai.core.ExpectedOutcome
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenBounds
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.StepAction
import com.nova.ai.core.TaskStep
import com.nova.ai.core.VerificationReport
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests how [ScreenVerificationEngine] judges a step from the screen before and after. */
class ScreenVerificationEngineTest {

    private val engine = ScreenVerificationEngine()
    private val area = ScreenBounds(0, 0, 100, 50)

    private fun node(
        text: String?,
        editable: Boolean = false,
        checked: Boolean = false,
        description: String? = null
    ): ScreenNode = ScreenNode(
        text = text,
        contentDescription = description,
        className = "android.widget.Button",
        packageName = "pkg",
        isClickable = true,
        isEditable = editable,
        isScrollable = false,
        bounds = area,
        isChecked = checked
    )

    private fun screen(packageName: String?, vararg nodes: ScreenNode): ScreenSnapshot =
        ScreenSnapshot(packageName, nodes.toList(), 0L)

    private fun step(
        action: StepAction,
        value: String? = null,
        expected: ExpectedOutcome = ExpectedOutcome.SCREEN_CHANGES,
        expectedValue: String? = null
    ): TaskStep = TaskStep(
        id = "s1",
        action = action,
        value = value,
        expected = expected,
        expectedValue = expectedValue
    )

    private fun verdict(step: TaskStep, before: ScreenSnapshot?, after: ScreenSnapshot?): VerificationReport =
        when (val result = engine.verify(step, before, after)) {
            is NovaResult.Success -> result.value
            is NovaResult.Failure -> throw AssertionError(result.error.message)
        }

    private val home = screen("launcher", node("Chrome"), node("Phone"))
    private val chrome = screen("chrome", node("Search"), node("Menu"))

    // ------------------------------------------------------------ the screen must change

    @Test
    fun clickPassesWhenAnotherAppComesToFront() {
        assertTrue(verdict(step(StepAction.CLICK), home, chrome).passed)
    }

    @Test
    fun clickFailsWhenTheScreenIsTheSame() {
        val same = screen("launcher", node("Chrome"), node("Phone"))
        assertFalse(verdict(step(StepAction.CLICK), home, same).passed)
    }

    @Test
    fun clickPassesWhenAnItemAppearsInTheSameApp() {
        val withDialog = screen("launcher", node("Chrome"), node("Phone"), node("Dialog"))
        assertTrue(verdict(step(StepAction.CLICK), home, withDialog).passed)
    }

    @Test
    fun switchToggleCountsAsAChange() {
        val off = screen("s", node("Wi-Fi", checked = false))
        val on = screen("s", node("Wi-Fi", checked = true))
        assertTrue(verdict(step(StepAction.CLICK), off, on).passed)
    }

    @Test
    fun aTickingClockDoesNotHideAFailedClick() {
        val before = screen("s", node("Ok"), node("10:52"))
        val after = screen("s", node("Ok"), node("10:53"))
        assertFalse(verdict(step(StepAction.CLICK), before, after).passed)
        val banglaBefore = screen("s", node("Ok"), node("১০:৫২"))
        val banglaAfter = screen("s", node("Ok"), node("১০:৫৩"))
        assertFalse(verdict(step(StepAction.CLICK), banglaBefore, banglaAfter).passed)
    }

    @Test
    fun aCounterThatChangesIsAChange() {
        assertTrue(verdict(step(StepAction.CLICK), screen("s", node("3")), screen("s", node("4"))).passed)
    }

    @Test
    fun missingScreensMeanNotVerified() {
        assertFalse(verdict(step(StepAction.CLICK), home, null).passed)
        assertFalse(verdict(step(StepAction.CLICK), null, chrome).passed)
    }

    @Test
    fun twoCopiesBecomingOneIsAChange() {
        val two = screen("s", node("A"), node("A"))
        val one = screen("s", node("A"))
        assertTrue(verdict(step(StepAction.SCROLL), two, one).passed)
    }

    @Test
    fun openAppNeedsAnotherAppOrAChange() {
        assertTrue(verdict(step(StepAction.OPEN_APP), home, chrome).passed)
        assertFalse(verdict(step(StepAction.OPEN_APP), home, home).passed)
    }

    @Test
    fun backAndHomeNeedAChange() {
        assertTrue(verdict(step(StepAction.HOME), chrome, home).passed)
        assertFalse(verdict(step(StepAction.BACK), chrome, chrome).passed)
    }

    @Test
    fun reportCarriesTheStepId() {
        assertEquals("s1", verdict(step(StepAction.CLICK), home, chrome).stepId)
    }

    // ------------------------------------------------------------ expected outcomes

    @Test
    fun noChangeExpectedPassesOnAnUnchangedScreen() {
        val copy = step(StepAction.CLICK, expected = ExpectedOutcome.NO_CHANGE_EXPECTED)
        assertTrue(verdict(copy, home, home).passed)
    }

    @Test
    fun noChangeExpectedStillNeedsTheScreenToBeReadable() {
        val copy = step(StepAction.CLICK, expected = ExpectedOutcome.NO_CHANGE_EXPECTED)
        assertFalse(verdict(copy, home, null).passed)
    }

    @Test
    fun expectedTextMustBeOnTheScreenOutsideInputFields() {
        val search = step(
            StepAction.CLICK, expected = ExpectedOutcome.TEXT_VISIBLE, expectedValue = "results for cats"
        )
        val results = screen("chrome", node("Results for CATS"))
        assertTrue(verdict(search, home, results).passed)
        val onlyInBox = screen("chrome", node("results for cats", editable = true))
        assertFalse(verdict(search, home, onlyInBox).passed)
        assertFalse(verdict(search, home, chrome).passed)
    }

    @Test
    fun expectedTextIsAlsoFoundInDescriptions() {
        val send = step(StepAction.CLICK, expected = ExpectedOutcome.TEXT_VISIBLE, expectedValue = "Sent")
        assertTrue(verdict(send, home, screen("wa", node(null, description = "Sent"))).passed)
    }

    @Test
    fun expectedTextWithoutAValueFails() {
        val broken = step(StepAction.CLICK, expected = ExpectedOutcome.TEXT_VISIBLE)
        assertFalse(verdict(broken, home, chrome).passed)
    }

    @Test
    fun expectedAppMustBeInFront() {
        val open = step(StepAction.OPEN_APP, expected = ExpectedOutcome.APP_IN_FRONT, expectedValue = "chrome")
        assertTrue(verdict(open, home, chrome).passed)
        assertFalse(verdict(open, chrome, home).passed)
        val noPackage = step(StepAction.OPEN_APP, expected = ExpectedOutcome.APP_IN_FRONT)
        assertFalse(verdict(noPackage, home, chrome).passed)
    }

    // ------------------------------------------------------------ typed text

    @Test
    fun typedTextMustAppearInAnInputField() {
        val typed = screen("c", node("hello world", editable = true))
        assertTrue(verdict(step(StepAction.TYPE_TEXT, "hello world"), null, typed).passed)
        assertTrue(verdict(step(StepAction.TYPE_TEXT, " hello   world "), null, typed).passed)
        assertFalse(verdict(step(StepAction.TYPE_TEXT, "bye"), null, typed).passed)
        assertFalse(verdict(step(StepAction.TYPE_TEXT, " "), null, typed).passed)
        assertFalse(verdict(step(StepAction.TYPE_TEXT, "hello world"), null, screen("c", node("hello world"))).passed)
    }

    @Test
    fun typedDigitsAreComparedTheWayTheScreenReaderShowsThem() {
        val masked = SensitiveNodePolicy.maskCodes("12345")
        val typed = screen("c", node(masked, editable = true))
        assertTrue(verdict(step(StepAction.TYPE_TEXT, "12345"), null, typed).passed)
    }

    @Test
    fun waitConfirmAndSpeakNeedNoCheck() {
        for (action in listOf(StepAction.WAIT, StepAction.CONFIRM, StepAction.SPEAK)) {
            assertTrue(verdict(step(action), null, home).passed)
        }
    }
}
EOF

# ---------- 6. VerifiedStepRunnerTest.kt ----------
cat > "$TEST_BASE/verification/VerifiedStepRunnerTest.kt" <<'EOF'
package com.nova.ai.verification

import com.nova.ai.accessibility.AccessibilityEngine
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenBounds
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.ScrollDirection
import com.nova.ai.core.StepAction
import com.nova.ai.core.TaskStep
import com.nova.ai.core.VerificationReport
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests the look-again loop of [VerifiedStepRunner] with a fake screen and a fake clock. */
class VerifiedStepRunnerTest {

    /** A screen that returns the given captures one after another (the last one repeats). */
    private class FakeScreen(private val captures: List<NovaResult<ScreenSnapshot>>) : AccessibilityEngine {
        var captureCalls: Int = 0
            private set

        override fun isServiceEnabled(): Boolean = true

        override fun captureScreen(): NovaResult<ScreenSnapshot> {
            val result = captures[minOf(captureCalls, captures.size - 1)]
            captureCalls += 1
            return result
        }

        override fun click(node: ScreenNode): NovaResult<Unit> = NovaResult.Success(Unit)
        override fun typeText(node: ScreenNode, text: String): NovaResult<Unit> = NovaResult.Success(Unit)
        override fun scroll(direction: ScrollDirection): NovaResult<Unit> = NovaResult.Success(Unit)
        override fun pressBack(): NovaResult<Unit> = NovaResult.Success(Unit)
        override fun pressHome(): NovaResult<Unit> = NovaResult.Success(Unit)
    }

    private fun shot(packageName: String, label: String): NovaResult<ScreenSnapshot> {
        val node = ScreenNode(label, null, "android.widget.Button", packageName, true, false, false, ScreenBounds(0, 0, 10, 10))
        return NovaResult.Success(ScreenSnapshot(packageName, listOf(node), 0L))
    }

    private val home = shot("launcher", "Chrome")
    private val chrome = shot("chrome", "Search")
    private val click = TaskStep("s1", StepAction.CLICK)
    private var sleeps = 0
    private val sleeper: (Long) -> Unit = { sleeps += 1 }

    private fun report(result: NovaResult<VerificationReport>): VerificationReport = when (result) {
        is NovaResult.Success -> result.value
        is NovaResult.Failure -> throw AssertionError(result.error.message)
    }

    @Test
    fun passesRightAwayWhenTheScreenChangesAtOnce() {
        val screen = FakeScreen(listOf(home, chrome))
        val result = VerifiedStepRunner(screen, sleep = sleeper).run(click) { NovaResult.Success(Unit) }
        assertTrue(report(result).passed)
        assertEquals(0, sleeps)
        assertEquals(2, screen.captureCalls)
    }

    @Test
    fun waitsAndSeesAChangeThatComesLate() {
        val screen = FakeScreen(listOf(home, home, home, chrome))
        val result = VerifiedStepRunner(screen, sleep = sleeper).run(click) { NovaResult.Success(Unit) }
        assertTrue(report(result).passed)
        assertEquals(2, sleeps)
    }

    @Test
    fun reportsFailureAfterEightLooksWhenNothingChanges() {
        val screen = FakeScreen(listOf(home))
        val result = VerifiedStepRunner(screen, sleep = sleeper).run(click) { NovaResult.Success(Unit) }
        assertFalse(report(result).passed)
        assertEquals(7, sleeps)
        assertEquals(9, screen.captureCalls)
    }

    @Test
    fun handsBackAnActionFailureUnchanged() {
        val screen = FakeScreen(listOf(home))
        val result = VerifiedStepRunner(screen, sleep = sleeper)
            .run(click) { NovaResult.failure(ErrorCode.SECURITY_BLOCKED, "stop") }
        assertTrue(result is NovaResult.Failure)
        assertEquals(ErrorCode.SECURITY_BLOCKED, (result as NovaResult.Failure).error.code)
        assertEquals(1, screen.captureCalls)
    }

    @Test
    fun anUnreadableScreenAfterwardsIsNotAPass() {
        val screen = FakeScreen(listOf(home, NovaResult.failure(ErrorCode.NOT_AVAILABLE, "no")))
        val result = VerifiedStepRunner(screen, sleep = sleeper).run(click) { NovaResult.Success(Unit) }
        assertFalse(report(result).passed)
    }

    @Test
    fun anInterruptStopsTheCheckAsCancelled() {
        val screen = FakeScreen(listOf(home))
        val runner = VerifiedStepRunner(screen, sleep = { throw InterruptedException() })
        val result = runner.run(click) { NovaResult.Success(Unit) }
        // Clear the flag the runner sets again, so it does not leak into other tests.
        Thread.interrupted()
        assertTrue(result is NovaResult.Failure)
        assertEquals(ErrorCode.CANCELLED, (result as NovaResult.Failure).error.code)
    }
}
EOF

# ---------- A. Models.kt: TaskStep gets two optional fields (idempotent) ----------
if ! grep -q "val expectedValue: String? = null" "$MODELS_FILE"; then
  sed -i 's/^    val requiresConfirmation: Boolean = false$/    val requiresConfirmation: Boolean = false,\n    val expected: ExpectedOutcome = ExpectedOutcome.SCREEN_CHANGES,\n    val expectedValue: String? = null/' "$MODELS_FILE"
fi
grep -q "val expectedValue: String? = null" "$MODELS_FILE" || { echo "ERROR: Models.kt edit failed" >&2; exit 1; }

# ---------- B. libs.versions.toml: JUnit for unit tests (idempotent) ----------
if ! grep -q "^junit = " "$VERSIONS_FILE"; then
  sed -i 's/^navigationCompose = .*/&\njunit = "4.13.2"/' "$VERSIONS_FILE"
  sed -i 's/^androidx-navigation-compose = .*/&\njunit = { group = "junit", name = "junit", version.ref = "junit" }/' "$VERSIONS_FILE"
fi
grep -q '^junit = "4.13.2"$' "$VERSIONS_FILE" || { echo "ERROR: libs.versions.toml edit failed (version)" >&2; exit 1; }
grep -q '^junit = { group = "junit"' "$VERSIONS_FILE" || { echo "ERROR: libs.versions.toml edit failed (library)" >&2; exit 1; }

# ---------- C. app/build.gradle.kts: test dependency and test options (idempotent) ----------
if ! grep -q "libs.junit" "$APP_GRADLE"; then
  sed -i 's/^    ksp(libs.androidx.room.compiler)$/&\n    testImplementation(libs.junit)/' "$APP_GRADLE"
fi
if ! grep -q "isReturnDefaultValues" "$APP_GRADLE"; then
  # Android calls (such as logging) return empty values in plain JVM tests instead of failing.
  sed -i 's/^    packaging {$/    testOptions {\n        unitTests.isReturnDefaultValues = true\n    }\n\n&/' "$APP_GRADLE"
fi
grep -q "testImplementation(libs.junit)" "$APP_GRADLE" || { echo "ERROR: build.gradle.kts edit failed (dependency)" >&2; exit 1; }
grep -q "isReturnDefaultValues = true" "$APP_GRADLE" || { echo "ERROR: build.gradle.kts edit failed (test options)" >&2; exit 1; }

# ---------- D. Workflow: run the unit tests after the APK is uploaded (idempotent) ----------
# The APK is uploaded first, so a failing test still leaves an APK to try on the phone.
if ! grep -q "testDebugUnitTest" "$WORKFLOW"; then
  cat >> "$WORKFLOW" <<'EOF'

      - name: Run unit tests
        run: gradle testDebugUnitTest --stacktrace
EOF
fi
grep -q "testDebugUnitTest" "$WORKFLOW" || { echo "ERROR: workflow edit failed" >&2; exit 1; }

# ---------- Commit and push ----------
git add -A
if git diff --cached --quiet; then
  echo "Nothing new to commit."
else
  git commit -m "Fix pack P20/P21: live-item long press and double tap, expected outcomes for verification, unit tests"
  git push
fi

echo "P20/P21 fix pack installed and pushed."
