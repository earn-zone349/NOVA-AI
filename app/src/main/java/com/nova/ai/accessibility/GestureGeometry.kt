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
