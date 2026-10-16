package com.nova.ai.nlp

import com.nova.ai.core.Language
import com.nova.ai.core.VoiceCommand
import com.nova.ai.voice.LanguageDetector
import java.text.Normalizer
import java.util.Locale

/**
 * Cleans a spoken or typed command so the intent parser (Phase 11) gets a
 * consistent input: standard Unicode, ASCII digits, no punctuation, no filler
 * words at the edges, and app names in their standard form.
 * Pure logic, no Android needed.
 */
object CommandNormalizer {

    // Keeps letters, digits and combining marks (Bangla vowel signs are marks).
    private val SEPARATORS: Regex = Regex("[^\\p{L}\\p{N}\\p{M}]+")

    // Invisible joiners inside Bangla conjuncts must not split a word.
    private val INVISIBLE_JOINERS: Regex = Regex("[\\u200C\\u200D]")

    private val LEADING_FILLERS: Set<String> = setOf(
        "ভাই", "নোভা", "নভা", "nova", "hey", "ok", "okay",
        "আচ্ছা", "শোন", "শোনো", "শুনো", "ওই"
    )

    private val TRAILING_FILLERS: Set<String> = setOf(
        "ভাই", "প্লিজ", "please", "plz", "তো"
    )

    /** Cleans [text]. The original text is kept inside the result. */
    fun normalize(text: String): NormalizedCommand {
        val unicodeClean: String = Normalizer.normalize(text, Normalizer.Form.NFC)
        val withoutJoiners: String = INVISIBLE_JOINERS.replace(unicodeClean, "")
        val asciiDigits: String = DigitConverter.toAscii(withoutJoiners)

        val words: List<String> = SEPARATORS
            .split(asciiDigits.lowercase(Locale.ROOT))
            .filter { it.isNotEmpty() }

        val coreWords: List<String> = stripFillers(words)
        val aliasResult: AliasResult = AppAliases.canonicalize(coreWords)

        return NormalizedCommand(
            original = text,
            normalizedText = aliasResult.tokens.joinToString(" "),
            tokens = aliasResult.tokens,
            detectedApps = aliasResult.apps,
            language = LanguageDetector.detect(text)
        )
    }

    /** Cleans a [VoiceCommand], keeping the language the voice engine already detected. */
    fun normalize(command: VoiceCommand): NormalizedCommand {
        val result: NormalizedCommand = normalize(command.rawText)
        return if (command.language == Language.UNKNOWN) {
            result
        } else {
            result.copy(language = command.language)
        }
    }

    /** Removes filler words at the start and end, but always keeps at least one word. */
    private fun stripFillers(words: List<String>): List<String> {
        var start = 0
        var end: Int = words.size
        while (end - start > 1 && words[start] in LEADING_FILLERS) start += 1
        while (end - start > 1 && words[end - 1] in TRAILING_FILLERS) end -= 1
        return words.subList(start, end)
    }
}
