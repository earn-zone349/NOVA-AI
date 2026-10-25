package com.nova.ai.accessibility

import android.graphics.Rect
import android.os.Build
import android.view.accessibility.AccessibilityNodeInfo
import com.nova.ai.logging.NovaLogger

/**
 * Finds the live screen item that belongs to a [NodeTarget]. It follows the saved
 * path and checks the item is the right one; if the screen changed, it searches by
 * position, class and id. Every node handed back must be released with [recycleQuietly].
 */
internal object NodeResolver {

    private const val TAG: String = "NodeResolver"
    private const val MAX_SEARCH_VISITS: Int = 3000
    private const val MAX_SEARCH_DEPTH: Int = 60

    /** The live node for [target] under [root], or null. The caller keeps ownership of [root]. */
    fun resolve(root: AccessibilityNodeInfo, target: NodeTarget): AccessibilityNodeInfo? {
        val path: List<Int>? = target.path
        if (path != null && path.isNotEmpty()) {
            val found: AccessibilityNodeInfo? = byPath(root, path)
            if (found != null) {
                if (matches(found, target)) return found
                recycleQuietly(found)
            }
        }
        return search(root, target, depth = 0, budget = IntArray(1) { MAX_SEARCH_VISITS })
    }

    /** Follows [path] (child positions) down from [root]. An empty path gives null. */
    fun byPath(root: AccessibilityNodeInfo, path: List<Int>): AccessibilityNodeInfo? {
        if (path.isEmpty()) return null
        var current: AccessibilityNodeInfo = root
        var ownsCurrent = false
        for (index in path) {
            val child: AccessibilityNodeInfo? = current.getChild(index)
            if (ownsCurrent) recycleQuietly(current)
            if (child == null) return null
            current = child
            ownsCurrent = true
        }
        return current
    }

    private fun search(
        node: AccessibilityNodeInfo,
        target: NodeTarget,
        depth: Int,
        budget: IntArray
    ): AccessibilityNodeInfo? {
        if (depth > MAX_SEARCH_DEPTH) return null
        for (index in 0 until node.childCount) {
            if (budget[0] <= 0) return null
            budget[0] -= 1
            val child: AccessibilityNodeInfo = node.getChild(index) ?: continue
            if (matches(child, target)) return child
            val deeper: AccessibilityNodeInfo? = search(child, target, depth + 1, budget)
            recycleQuietly(child)
            if (deeper != null) return deeper
        }
        return null
    }

    private fun matches(node: AccessibilityNodeInfo, target: NodeTarget): Boolean {
        val rect = Rect()
        node.getBoundsInScreen(rect)
        val bounds = target.bounds
        if (rect.left != bounds.left || rect.top != bounds.top ||
            rect.right != bounds.right || rect.bottom != bounds.bottom
        ) {
            return false
        }
        if (target.className.isNotEmpty() && node.className?.toString() != target.className) return false
        if (target.viewId.isNotEmpty() && node.viewIdResourceName != target.viewId) return false
        return true
    }

    /** Releases a node. Android 13 and newer do this by themselves. */
    @Suppress("DEPRECATION")
    fun recycleQuietly(node: AccessibilityNodeInfo) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
        try {
            node.recycle()
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Failed to recycle a node", e)
        }
    }
}
