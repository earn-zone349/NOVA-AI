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
