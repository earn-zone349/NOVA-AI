package com.nova.ai.accessibility

import com.nova.ai.apps.PhoneticKey

/**
 * Finds the item on a captured screen that best fits a name the user said or typed.
 * It tries exact names first, then partial matches, then names that sound alike
 * (so Bangla and English spellings of the same word can meet). Pure logic.
 */
object NodeFinder {

    /** Which kind of item may be returned. */
    enum class Filter { ANY, CLICKABLE, EDITABLE }

    private const val SCORE_EXACT: Float = 1.0f
    private const val SCORE_STARTS_WITH: Float = 0.9f
    private const val SCORE_CONTAINS: Float = 0.8f
    private const val SCORE_SAME_SOUND: Float = 0.75f
    private const val SCORE_INSIDE_QUERY: Float = 0.6f
    private const val MIN_SCORE: Float = 0.6f
    private const val MIN_CONTAINED_LENGTH: Int = 3

    /** The best item for [query], or null if nothing fits well enough. */
    fun findBest(capture: ScreenCapture, query: String, filter: Filter): UiNode? {
        val queryKey: String = PhoneticKey.nameKey(query)
        if (queryKey.isEmpty()) return null
        val queryPhonetic: String = PhoneticKey.phonetic(query)

        return capture.nodes
            .asSequence()
            .filter { passes(it, filter) }
            .map { node -> node to scoreOf(node, queryKey, queryPhonetic) }
            .filter { it.second >= MIN_SCORE }
            // Best name first; among equals the smaller item (more specific) wins.
            .sortedWith(compareByDescending<Pair<UiNode, Float>> { it.second }.thenBy { areaOf(it.first) })
            .firstOrNull()
            ?.first
    }

    /** The input field to type into when no name was given: the focused one, else the top-most. */
    fun firstEditable(capture: ScreenCapture): UiNode? {
        val fields: List<UiNode> = capture.nodes.filter { it.isEditable && it.isEnabled && !it.isSensitive }
        return fields.firstOrNull { it.isFocused }
            ?: fields.minWithOrNull(compareBy<UiNode>({ it.bounds.top }, { it.bounds.left }))
    }

    private fun passes(node: UiNode, filter: Filter): Boolean = when (filter) {
        Filter.ANY -> true
        Filter.CLICKABLE -> node.isClickable && node.isEnabled
        Filter.EDITABLE -> node.isEditable && node.isEnabled && !node.isSensitive
    }

    private fun scoreOf(node: UiNode, queryKey: String, queryPhonetic: String): Float {
        val labels: List<String> = listOf(node.text, node.description, node.hint)
            .filter { it.isNotBlank() }
            .ifEmpty { listOf(node.viewId.substringAfterLast('/')).filter { it.isNotBlank() } }

        var best = 0f
        for (label in labels) {
            val key: String = PhoneticKey.nameKey(label)
            if (key.isEmpty()) continue
            val score: Float = when {
                key == queryKey -> SCORE_EXACT
                key.startsWith(queryKey) -> SCORE_STARTS_WITH
                key.contains(queryKey) -> SCORE_CONTAINS
                queryPhonetic.isNotEmpty() && PhoneticKey.phonetic(label) == queryPhonetic -> SCORE_SAME_SOUND
                key.length >= MIN_CONTAINED_LENGTH && queryKey.contains(key) -> SCORE_INSIDE_QUERY
                else -> 0f
            }
            if (score > best) best = score
        }
        return best
    }

    private fun areaOf(node: UiNode): Long {
        val width: Long = (node.bounds.right - node.bounds.left).toLong()
        val height: Long = (node.bounds.bottom - node.bounds.top).toLong()
        return width * height
    }
}
