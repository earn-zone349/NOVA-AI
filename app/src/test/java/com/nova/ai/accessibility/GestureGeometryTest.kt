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
