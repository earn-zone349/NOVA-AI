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
