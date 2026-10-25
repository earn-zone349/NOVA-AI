package com.nova.ai.accessibility

import com.nova.ai.core.ScreenBounds

/**
 * Describes the item an action is meant for, so it can be found again on the live screen.
 * [path] is the position in the screen tree (when known); [bounds], [className] and
 * [viewId] are used to check that the right item was found, or to search for it.
 */
data class NodeTarget(
    val path: List<Int>?,
    val bounds: ScreenBounds,
    val className: String,
    val viewId: String
)

/** The target that points at this item. */
fun UiNode.toTarget(): NodeTarget =
    NodeTarget(path = path, bounds = bounds, className = className, viewId = viewId)
