package com.nova.ai.verification

import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot

/**
 * Compares two screen snapshots. Plain logic with no Android classes, so it can be tested
 * without a phone. A node is described by its class, texts, place and checked state; clocks
 * and timers are left out, because they change by themselves and would hide a failed click.
 */
internal object ScreenDiff {

    // Times such as 10:52, 7:05 PM or 01:02:03, in English or Bangla digits.
    private val CLOCK_TEXT: Regex =
        Regex("^\\p{Nd}{1,2}[:.]\\p{Nd}{2}([:.]\\p{Nd}{2})?\\s*([AaPp][Mm])?$")

    /** How many nodes appear in only one of the two snapshots (0 means the screens look the same). */
    fun changedNodeCount(before: ScreenSnapshot, after: ScreenSnapshot): Int {
        val beforeCounts: Map<String, Int> = countsOf(before)
        val afterCounts: Map<String, Int> = countsOf(after)
        var changed = 0
        for (key in beforeCounts.keys + afterCounts.keys) {
            val left: Int = beforeCounts[key] ?: 0
            val right: Int = afterCounts[key] ?: 0
            changed += if (left > right) left - right else right - left
        }
        return changed
    }

    /** True if the app in front is a different one. Unknown packages are never called different. */
    fun packageChanged(before: ScreenSnapshot, after: ScreenSnapshot): Boolean {
        val oldPackage: String = before.packageName ?: return false
        val newPackage: String = after.packageName ?: return false
        return oldPackage != newPackage
    }

    private fun countsOf(snapshot: ScreenSnapshot): Map<String, Int> {
        val counts = HashMap<String, Int>()
        for (node in snapshot.nodes) {
            if (isVolatile(node)) continue
            val key: String = signatureOf(node)
            counts[key] = (counts[key] ?: 0) + 1
        }
        return counts
    }

    private fun signatureOf(node: ScreenNode): String = buildString {
        append(node.className.orEmpty()).append('|')
        append(node.text.orEmpty()).append('|')
        append(node.contentDescription.orEmpty()).append('|')
        append(node.bounds.left).append(',').append(node.bounds.top).append(',')
        append(node.bounds.right).append(',').append(node.bounds.bottom).append('|')
        append(node.isChecked)
    }

    private fun isVolatile(node: ScreenNode): Boolean {
        val label: String = (node.text ?: node.contentDescription).orEmpty().trim()
        return label.isNotEmpty() && CLOCK_TEXT.matches(label)
    }
}
