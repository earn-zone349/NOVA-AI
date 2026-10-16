package com.nova.ai.voice

import java.util.Locale

/**
 * Recognizes spoken commands that end the conversation ("stop", "থামো", ...).
 * Only a whole short command counts, so "গান থামো" is NOT treated as a stop phrase.
 * Pure logic, no Android needed.
 */
object StopPhrases {

    // Keeps letters, digits and combining marks (Bangla vowel signs are marks).
    private val SEPARATORS: Regex = Regex("[^\\p{L}\\p{N}\\p{M}]+")

    private val FILLER_WORDS: Set<String> = setOf(
        "ভাই", "নোভা", "নভা", "nova", "hey", "ok", "okay", "please", "প্লিজ"
    )

    private val STOP_COMMANDS: Set<String> = setOf(
        "থামো", "থামুন", "থামাও", "থামিয়ে দাও", "থেমে যাও",
        "বন্ধ করো", "বন্ধ করুন", "বন্ধ কর", "কথোপকথন বন্ধ করো",
        "বাতিল", "বাতিল করো",
        "stop", "stop it", "stop listening", "exit", "cancel", "that is all"
    )

    /** True if [text] is only a stop command (filler words like "ভাই" are ignored). */
    fun isStopCommand(text: String): Boolean {
        val words: List<String> = SEPARATORS
            .split(text.lowercase(Locale.ROOT))
            .filter { it.isNotEmpty() && it !in FILLER_WORDS }
        if (words.isEmpty()) return false
        return words.joinToString(" ") in STOP_COMMANDS
    }
}
