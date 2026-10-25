package com.nova.ai.accessibility

import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.ScrollDirection

/**
 * The real [AccessibilityEngine] of the app (the "hands and eyes"). The task planner
 * of a later phase uses this class to read the screen and act on it.
 */
class NovaAccessibilityEngine : AccessibilityEngine {

    override fun isServiceEnabled(): Boolean = AccessibilityBridge.isConnected

    override fun captureScreen(): NovaResult<ScreenSnapshot> =
        AccessibilityBridge.readScreen().map { capture -> toSnapshot(capture) }

    override fun click(node: ScreenNode): NovaResult<Unit> =
        AccessibilityBridge.click(targetOf(node))

    override fun typeText(node: ScreenNode, text: String): NovaResult<Unit> =
        AccessibilityBridge.typeText(targetOf(node), text, append = false)

    override fun scroll(direction: ScrollDirection): NovaResult<Unit> =
        AccessibilityBridge.scroll(direction)

    override fun pressBack(): NovaResult<Unit> = AccessibilityBridge.pressBack()

    override fun pressHome(): NovaResult<Unit> = AccessibilityBridge.pressHome()

    // A snapshot item has no saved path, so the live screen is searched by position and class.
    private fun targetOf(node: ScreenNode): NodeTarget =
        NodeTarget(path = null, bounds = node.bounds, className = node.className.orEmpty(), viewId = "")

    private fun toSnapshot(capture: ScreenCapture): ScreenSnapshot = ScreenSnapshot(
        packageName = capture.packageName,
        nodes = capture.nodes.map { item ->
            ScreenNode(
                text = item.text.ifBlank { null },
                contentDescription = item.description.ifBlank { null },
                className = item.className.ifBlank { null },
                packageName = capture.packageName,
                isClickable = item.isClickable,
                isEditable = item.isEditable,
                isScrollable = item.isScrollable,
                bounds = item.bounds
            )
        },
        capturedAtMs = capture.capturedAtMs
    )
}
