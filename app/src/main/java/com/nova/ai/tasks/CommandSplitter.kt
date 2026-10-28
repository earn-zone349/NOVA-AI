package com.nova.ai.tasks

import java.util.Locale

/**
 * Cuts one spoken command into its parts at the words that mean "and after that"
 * (তারপর, এরপর, then, and then, after that). Pure logic with no Android classes.
 * Only these clear words split a command, so a normal single command is never cut by mistake.
 */
object CommandSplitter {

    // One-word connectors, written in lower case.
    private val SINGLE: Set<String> = setOf(
        "তারপর", "তারপরে", "এরপর", "এরপরে", "অতঃপর", "then", "afterwards", "afterward"
    )

    // Two-word connectors: first word to the words that may follow it.
    private val DOUBLE: Map<String, Set<String>> = mapOf(
        "তার" to setOf("পর", "পরে"),
        "এর" to setOf("পর", "পরে"),
        "and" to setOf("then"),
        "after" to setOf("that")
    )

    // Little words that are left hanging at the end of a part ("ক্রোম খোলো এবং").
    private val TRAILING: Set<String> = setOf("এবং", "আর", "ও", "and")

    private const val EDGE_MARKS: String = ",.;:!?।\"'“”‘’"

    /** The parts of [text], in order, without the connecting words. Empty if there is nothing to do. */
    fun split(text: String): List<String> {
        val words: List<String> = text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        val parts: MutableList<MutableList<String>> = mutableListOf(mutableListOf())
        var index = 0
        while (index < words.size) {
            val word: String = words[index]
            val key: String = clean(word)
            val nextKey: String? = words.getOrNull(index + 1)?.let { clean(it) }
            when {
                key in SINGLE -> {
                    parts.add(mutableListOf())
                    index += 1
                }
                nextKey != null && DOUBLE[key]?.contains(nextKey) == true -> {
                    parts.add(mutableListOf())
                    index += 2
                }
                else -> {
                    parts.last().add(word)
                    index += 1
                }
            }
        }
        return parts.map { tidy(it) }.filter { it.isNotEmpty() }
    }

    /** True if [text] holds two or more parts. */
    fun isMultiStep(text: String): Boolean = split(text).size >= 2

    private fun clean(word: String): String = word.trim(*EDGE_MARKS.toCharArray()).lowercase(Locale.ROOT)

    // Drops hanging little words and marks at the end of a part, and marks at its edges.
    private fun tidy(words: List<String>): String {
        val kept: MutableList<String> = words.toMutableList()
        while (kept.isNotEmpty() && clean(kept.last()) in TRAILING) kept.removeAt(kept.lastIndex)
        return kept.joinToString(" ").trim().trim(*EDGE_MARKS.toCharArray()).trim()
    }
}
