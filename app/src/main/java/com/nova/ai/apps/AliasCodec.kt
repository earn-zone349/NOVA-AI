package com.nova.ai.apps

/** Saves and cleans nicknames. Nicknames are stored one per line. */
object AliasCodec {

    private const val SEPARATOR: String = "\n"
    private const val MAX_ALIASES: Int = 10
    private const val MAX_ALIAS_LENGTH: Int = 40
    private val WHITESPACE: Regex = Regex("\\s+")

    fun encode(aliases: List<String>): String = aliases.joinToString(SEPARATOR)

    fun decode(stored: String): List<String> =
        stored.split(SEPARATOR).map { it.trim() }.filter { it.isNotEmpty() }

    /** Splits what the user typed (commas or new lines) into separate nicknames. */
    fun parseInput(text: String): List<String> =
        text.split(',', ';', '\n').map { it.trim() }.filter { it.isNotEmpty() }

    /**
     * Cleans a nickname list: trims, limits length and count, removes empty and
     * repeated names, and drops nicknames equal to the app's real [label].
     */
    fun sanitize(raw: List<String>, label: String): List<String> {
        val seen = HashSet<String>()
        seen.add(PhoneticKey.nameKey(label))

        val result = ArrayList<String>()
        for (item in raw) {
            val clean: String = item.replace(WHITESPACE, " ").trim().take(MAX_ALIAS_LENGTH)
            if (clean.isEmpty()) continue
            val key: String = PhoneticKey.nameKey(clean)
            if (key.isEmpty() || !seen.add(key)) continue
            result.add(clean)
            if (result.size >= MAX_ALIASES) break
        }
        return result
    }
}
