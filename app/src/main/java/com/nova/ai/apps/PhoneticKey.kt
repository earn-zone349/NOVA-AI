package com.nova.ai.apps

import com.nova.ai.nlp.DigitConverter
import java.text.Normalizer
import java.util.Locale

/**
 * Turns app names (Bangla or English) into comparable sound-alike keys, so that
 * "ফ্রী ফায়ার" and "Free Fire" can be matched. Pure logic, no Android needed.
 */
internal object PhoneticKey {

    private const val HASANTA: Char = '\u09CD'
    private const val NUKTA: Char = '\u09BC'
    private const val YA: Char = '\u09AF'

    private val NON_NAME_CHARS: Regex = Regex("[^\\p{L}\\p{N}\\p{M}]+")
    private val SOFT_C: Regex = Regex("c(?!h)")
    private val VOWEL_LIKE: Set<Char> = setOf('a', 'e', 'i', 'o', 'u', 'y', 'w')

    private val SOUND_RULES: List<Pair<String, String>> = listOf(
        "ph" to "f", "ck" to "k", "qu" to "kw", "x" to "ks",
        "q" to "k", "z" to "j", "v" to "b", "ee" to "i", "oo" to "u"
    )

    private val BANGLA_TO_LATIN: Map<Char, String> = mapOf(
        'অ' to "o", 'আ' to "a", 'ই' to "i", 'ঈ' to "i", 'উ' to "u", 'ঊ' to "u", 'ঋ' to "ri",
        'এ' to "e", 'ঐ' to "oi", 'ও' to "o", 'ঔ' to "ou",
        'া' to "a", 'ি' to "i", 'ী' to "i", 'ু' to "u", 'ূ' to "u", 'ৃ' to "ri",
        'ে' to "e", 'ৈ' to "oi", 'ো' to "o", 'ৌ' to "ou",
        'ং' to "ng", 'ঃ' to "", 'ঁ' to "",
        'ক' to "k", 'খ' to "kh", 'গ' to "g", 'ঘ' to "gh", 'ঙ' to "ng",
        'চ' to "ch", 'ছ' to "ch", 'জ' to "j", 'ঝ' to "jh", 'ঞ' to "n",
        'ট' to "t", 'ঠ' to "th", 'ড' to "d", 'ঢ' to "dh", 'ণ' to "n",
        'ত' to "t", 'থ' to "th", 'দ' to "d", 'ধ' to "dh", 'ন' to "n",
        'প' to "p", 'ফ' to "f", 'ব' to "b", 'ভ' to "v", 'ম' to "m",
        'য' to "j", 'র' to "r", 'ল' to "l", 'শ' to "sh", 'ষ' to "sh", 'স' to "s", 'হ' to "h",
        '\u09DC' to "r", '\u09DD' to "r", '\u09DF' to "y", 'ৎ' to "t"
    )

    /** Letters and digits only, lowercase. Used for exact comparison. */
    fun nameKey(text: String): String =
        NON_NAME_CHARS.replace(
            Normalizer.normalize(text, Normalizer.Form.NFC).lowercase(Locale.ROOT),
            ""
        )

    /** Bangla letters written in Latin letters; Latin and digits are kept. */
    fun toLatin(text: String): String {
        val input: String = Normalizer.normalize(DigitConverter.toAscii(text), Normalizer.Form.NFC)
        val out = StringBuilder(input.length + 8)
        var afterHasanta = false

        for (character in input) {
            if (character == HASANTA) {
                afterHasanta = true
                continue
            }
            when {
                character == NUKTA -> applyNukta(out)
                character == YA && afterHasanta -> out.append("y")
                character in BANGLA_TO_LATIN -> out.append(BANGLA_TO_LATIN.getValue(character))
                character in 'a'..'z' || character in 'A'..'Z' || character in '0'..'9' ->
                    out.append(character.lowercaseChar())
                else -> Unit
            }
            afterHasanta = false
        }
        return out.toString()
    }

    /** Sound-alike key: same sound gives the same key, in Bangla or English. */
    fun phonetic(text: String): String {
        var sound: String = toLatin(text)
        for ((from, to) in SOUND_RULES) {
            sound = sound.replace(from, to)
        }
        sound = SOFT_C.replace(sound, "k")
        return collapseRepeats(sound)
    }

    /** Consonants of the sound-alike key. Ignores vowel differences ("fire" and "fayar"). */
    fun skeleton(text: String): String =
        collapseRepeats(phonetic(text).filter { it !in VOWEL_LIKE })

    /** 1.0 for equal text, 0.0 for completely different. */
    fun similarity(first: String, second: String): Float {
        if (first.isEmpty() && second.isEmpty()) return 0f
        val longest: Int = maxOf(first.length, second.length)
        return 1f - distance(first, second).toFloat() / longest.toFloat()
    }

    private fun applyNukta(out: StringBuilder) {
        when {
            out.endsWith("dh") -> replaceTail(out, 2, "r")
            out.endsWith("d") -> replaceTail(out, 1, "r")
            out.endsWith("j") -> replaceTail(out, 1, "y")
            else -> Unit
        }
    }

    private fun replaceTail(out: StringBuilder, length: Int, replacement: String) {
        out.setLength(out.length - length)
        out.append(replacement)
    }

    private fun collapseRepeats(text: String): String {
        val out = StringBuilder(text.length)
        for (character in text) {
            if (out.isEmpty() || out[out.length - 1] != character) out.append(character)
        }
        return out.toString()
    }

    /** Number of single-letter edits needed to turn [first] into [second]. */
    private fun distance(first: String, second: String): Int {
        if (first == second) return 0
        var previous = IntArray(second.length + 1) { it }
        var current = IntArray(second.length + 1)

        for (row in 1..first.length) {
            current[0] = row
            for (column in 1..second.length) {
                val cost: Int = if (first[row - 1] == second[column - 1]) 0 else 1
                current[column] = minOf(
                    previous[column] + 1,
                    current[column - 1] + 1,
                    previous[column - 1] + cost
                )
            }
            val swap: IntArray = previous
            previous = current
            current = swap
        }
        return previous[second.length]
    }
}
