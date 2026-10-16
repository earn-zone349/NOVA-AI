package com.nova.ai.nlp

import java.util.Locale

/** Read-only helper that gives the parser easy questions to ask about one command. */
internal class CommandView(command: NormalizedCommand) {

    /** Cleaned text, lowercase. */
    val text: String = command.normalizedText.lowercase(Locale.ROOT)

    /** Cleaned words, lowercase. App names are in their standard form (also lowercase here). */
    val lowerTokens: List<String> = command.tokens.map { it.lowercase(Locale.ROOT) }

    /** Standard names of the apps found in the command, in order. */
    val apps: List<String> = command.detectedApps

    private val appTokenSet: Set<String> = apps.map { it.lowercase(Locale.ROOT) }.toSet()

    fun hasAny(words: Set<String>): Boolean = lowerTokens.any { it in words }

    fun has(word: String): Boolean = word in lowerTokens

    fun isAppToken(lowerToken: String): Boolean = lowerToken in appTokenSet

    /** True if [keyword] appears as a word (or word start), or inside the text for multi-word keywords. */
    fun mentions(keyword: String): Boolean =
        if (keyword.contains(' ')) text.contains(keyword) else lowerTokens.any { it.startsWith(keyword) }

    /** Words that are not app names and not in any of the [excluded] sets. */
    fun remaining(vararg excluded: Set<String>): List<String> =
        lowerTokens.filter { token ->
            !isAppToken(token) && excluded.none { set -> token in set }
        }

    /** First word that is only ASCII digits, as a number. */
    fun firstNumber(): Int? {
        for (token in lowerTokens) {
            if (token.isNotEmpty() && token.all { it in '0'..'9' }) {
                val value: Int? = token.toIntOrNull()
                if (value != null) return value
            }
        }
        return null
    }
}
