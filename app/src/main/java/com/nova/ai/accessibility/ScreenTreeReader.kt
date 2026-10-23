package com.nova.ai.accessibility

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo
import com.nova.ai.core.ScreenBounds
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot

/**
 * Walks the Accessibility tree of one window and turns it into plain [ScreenNode] data.
 *
 * Privacy rules (kept on purpose, later phases rely on them):
 *  - Password fields never give out any text.
 *  - Input fields never give out what the user typed. Only their label (hint or
 *    description) is kept, so NOVA can find the field without reading its content.
 *  - Nothing read here is logged or stored.
 *
 * The walk is limited in depth and node count, so a huge or broken screen cannot
 * freeze the app.
 */
object ScreenTreeReader {

    /** Most nodes kept from one screen. */
    const val MAX_NODES: Int = 400

    private const val MAX_DEPTH: Int = 40
    private const val MAX_LABEL_LENGTH: Int = 300
    private val WHITESPACE: Regex = Regex("\\s+")

    /** Reads the tree below [root]. The caller owns [root] and must recycle it. */
    fun read(root: AccessibilityNodeInfo, capturedAtMs: Long): ScreenSnapshot {
        val nodes: MutableList<ScreenNode> = ArrayList()
        walk(root, 0, nodes)
        return ScreenSnapshot(
            packageName = root.packageName?.toString(),
            nodes = nodes,
            capturedAtMs = capturedAtMs
        )
    }

    private fun walk(node: AccessibilityNodeInfo, depth: Int, out: MutableList<ScreenNode>) {
        if (out.size >= MAX_NODES || depth > MAX_DEPTH) return
        // Parts of the screen the user cannot see are not read.
        if (!node.isVisibleToUser) return

        toScreenNode(node)?.let { out.add(it) }

        for (index in 0 until node.childCount) {
            if (out.size >= MAX_NODES) break
            val child: AccessibilityNodeInfo = node.getChild(index) ?: continue
            try {
                walk(child, depth + 1, out)
            } finally {
                recycleQuietly(child)
            }
        }
    }

    /** Returns null for nodes that carry nothing useful (empty layout containers). */
    private fun toScreenNode(node: AccessibilityNodeInfo): ScreenNode? {
        val isSecret: Boolean = node.isPassword
        val isField: Boolean = node.isEditable

        val label: String? = when {
            isSecret -> null
            isField -> clean(node.hintText) ?: clean(node.contentDescription)
            else -> clean(node.text)
        }
        val description: String? = when {
            isSecret || isField -> null
            else -> clean(node.contentDescription)
        }

        val isUseful: Boolean = label != null || description != null ||
            node.isClickable || isField || node.isScrollable
        if (!isUseful) return null

        val rect = Rect()
        node.getBoundsInScreen(rect)
        if (rect.isEmpty) return null

        return ScreenNode(
            // For input fields the label travels in the description slot (never the typed text).
            text = if (isField) null else label,
            contentDescription = if (isField) label else description,
            className = node.className?.toString(),
            packageName = node.packageName?.toString(),
            isClickable = node.isClickable,
            isEditable = isField,
            isScrollable = node.isScrollable,
            bounds = ScreenBounds(rect.left, rect.top, rect.right, rect.bottom)
        )
    }

    private fun clean(value: CharSequence?): String? {
        val trimmed: String = value?.toString()?.replace(WHITESPACE, " ")?.trim() ?: return null
        return if (trimmed.isEmpty()) null else trimmed.take(MAX_LABEL_LENGTH)
    }

    @Suppress("DEPRECATION")
    private fun recycleQuietly(node: AccessibilityNodeInfo) {
        try {
            node.recycle()
        } catch (e: Exception) {
            // Recycling is only a memory courtesy; a failure here is harmless.
        }
    }
}
