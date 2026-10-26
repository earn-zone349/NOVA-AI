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
