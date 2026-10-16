#!/usr/bin/env bash
# NOVA AI - Phase 9 setup script: mixed-language command normalizer.
# Additive: new nlp package + one insight card; HomeScreen gets two new lines only.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
HOME_FILE="$BASE/ui/screens/HomeScreen.kt"

if [ ! -f "$HOME_FILE" ] || [ ! -f "$BASE/voice/LanguageDetector.kt" ]; then
  echo "ERROR: Run from repo root after P1 to P8 are installed." >&2
  exit 1
fi

mkdir -p "$BASE/nlp"

# ---------- A. New strings file ----------
cat > app/src/main/res/values/strings_p9.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="insight_title">বোঝা কমান্ড</string>
    <string name="insight_normalized">সাজানো রূপ: %1$s</string>
    <string name="insight_apps">চেনা অ্যাপ: %1$s</string>
    <string name="insight_language">ভাষা: %1$s</string>
    <string name="insight_lang_bangla">বাংলা</string>
    <string name="insight_lang_english">English</string>
    <string name="insight_lang_mixed">মিশ্র (বাংলা + English)</string>
    <string name="insight_lang_unknown">অজানা</string>
</resources>
EOF

# ---------- 1. NormalizedCommand.kt ----------
cat > "$BASE/nlp/NormalizedCommand.kt" <<'EOF'
package com.nova.ai.nlp

import com.nova.ai.core.Language

/** A command after cleanup, ready for the intent parser (Phase 11). */
data class NormalizedCommand(
    /** Exactly what the user said or typed. */
    val original: String,
    /** Cleaned text: no filler words, ASCII digits, app names in one standard form. */
    val normalizedText: String,
    /** [normalizedText] split into words. */
    val tokens: List<String>,
    /** Standard names of the apps mentioned (for example "Chrome"), in order. */
    val detectedApps: List<String>,
    val language: Language
)
EOF

# ---------- 2. DigitConverter.kt ----------
cat > "$BASE/nlp/DigitConverter.kt" <<'EOF'
package com.nova.ai.nlp

/** Converts Bangla digits (০ to ৯) into ASCII digits (0 to 9). Pure logic. */
object DigitConverter {

    private const val BANGLA_ZERO_CODE: Int = 0x09E6
    private const val DIGIT_COUNT: Int = 10

    fun toAscii(text: String): String {
        val builder = StringBuilder(text.length)
        for (character in text) {
            val offset: Int = character.code - BANGLA_ZERO_CODE
            if (offset in 0 until DIGIT_COUNT) {
                builder.append('0' + offset)
            } else {
                builder.append(character)
            }
        }
        return builder.toString()
    }
}
EOF

# ---------- 3. AppAliases.kt ----------
cat > "$BASE/nlp/AppAliases.kt" <<'EOF'
package com.nova.ai.nlp

import java.text.Normalizer
import java.util.Locale

/** Result of replacing app-name variants with their standard names. */
data class AliasResult(
    val tokens: List<String>,
    val apps: List<String>
)

/**
 * Maps the many ways people say or spell an app name (Bangla letters, English,
 * short forms) to one standard name. Bangla endings such as "ক্রোমে" are handled.
 * To support a new spelling, add it to [ALIASES]. Pure logic, no Android needed.
 */
object AppAliases {

    private val ALIASES: Map<String, List<String>> = mapOf(
        "Chrome" to listOf(
            "ক্রোম", "ক্রম", "ক্রোম ব্রাউজার", "ক্রম ব্রাউজার", "গুগল ক্রোম", "google chrome"
        ),
        "Google" to listOf("গুগল", "গুগোল"),
        "WhatsApp" to listOf(
            "whats app", "হোয়াটসঅ্যাপ", "হোয়াটস অ্যাপ", "হোয়াটসএপ", "হোয়াটসএপ্প",
            "হোয়াটসআপ", "হোয়াটস আপ", "ওয়াটসঅ্যাপ", "ওয়াটসএপ"
        ),
        "Facebook" to listOf("fb", "ফেসবুক", "ফেইসবুক", "ফেজবুক", "ফেস বুক"),
        "Messenger" to listOf("মেসেঞ্জার", "মেসেনজার", "মেসেঞ্জর"),
        "TikTok" to listOf("tik tok", "টিকটক", "টিক টক", "টিকটোক"),
        "YouTube" to listOf("you tube", "ইউটিউব", "ইউ টিউব", "ইউটিউভ"),
        "Gmail" to listOf("জিমেইল", "জিমেল", "জি মেইল"),
        "Instagram" to listOf(
            "insta", "ইনস্টাগ্রাম", "ইন্সটাগ্রাম", "ইনস্টা", "ইনস্ট্যাগ্রাম"
        ),
        "Telegram" to listOf("টেলিগ্রাম"),
        "Settings" to listOf("setting", "সেটিংস", "সেটিং"),
        "Camera" to listOf("ক্যামেরা"),
        "Gallery" to listOf("গ্যালারি", "গ্যালারী"),
        "Maps" to listOf("map", "google maps", "গুগল ম্যাপ", "গুগল ম্যাপস", "ম্যাপ", "ম্যাপস"),
        "Dialer" to listOf("ডায়ালার"),
        "Play Store" to listOf("playstore", "প্লে স্টোর", "প্লেস্টোর"),
        "Calculator" to listOf("ক্যালকুলেটর"),
        "Clock" to listOf("ঘড়ি", "ক্লক"),
        "Calendar" to listOf("ক্যালেন্ডার", "ক্যালেণ্ডার"),
        "Contacts" to listOf("কন্টাক্ট", "কন্টাক্টস", "কনট্যাক্ট"),
        "Files" to listOf("file manager", "ফাইল ম্যানেজার"),
        "Spotify" to listOf("স্পটিফাই"),
        "X" to listOf("twitter", "টুইটার"),
        "Snapchat" to listOf("স্ন্যাপচ্যাট"),
        "Netflix" to listOf("নেটফ্লিক্স")
    )

    /** Longest app name (in words) that can be matched, for example "গুগল ম্যাপ" has 2. */
    private const val MAX_PHRASE_WORDS: Int = 3

    /** Common Bangla endings, longest first, removed when looking up a word. */
    private val SUFFIXES: List<String> = listOf(
        "গুলোতে", "গুলোর", "গুলো", "টাতে", "টাকে", "টার", "টা",
        "টিতে", "টির", "টি", "তে", "কে", "র", "ে", "এ"
    )

    private val LOOKUP: Map<String, String> = buildMap {
        for ((standardName, variants) in ALIASES) {
            put(keyOf(standardName), standardName)
            for (variant in variants) {
                put(keyOf(variant), standardName)
            }
        }
    }

    /** Returns the standard app name for [phrase], or null if it is not a known app name. */
    fun lookup(phrase: String): String? {
        val key: String = keyOf(phrase)
        LOOKUP[key]?.let { return it }
        for (suffix in SUFFIXES) {
            if (key.length > suffix.length && key.endsWith(suffix)) {
                LOOKUP[key.removeSuffix(suffix)]?.let { return it }
            }
        }
        return null
    }

    /**
     * Replaces app names inside [tokens] with their standard names.
     * Longer names win ("গুগল ম্যাপ" becomes Maps, not Google + ম্যাপ).
     */
    fun canonicalize(tokens: List<String>): AliasResult {
        val output = ArrayList<String>(tokens.size)
        val apps = ArrayList<String>()
        var index = 0

        while (index < tokens.size) {
            var matched = false
            val longest: Int = minOf(MAX_PHRASE_WORDS, tokens.size - index)
            for (wordCount in longest downTo 1) {
                val phrase: String = tokens.subList(index, index + wordCount).joinToString(" ")
                val standardName: String? = lookup(phrase)
                if (standardName != null) {
                    output.add(standardName)
                    if (standardName !in apps) apps.add(standardName)
                    index += wordCount
                    matched = true
                    break
                }
            }
            if (!matched) {
                output.add(tokens[index])
                index += 1
            }
        }
        return AliasResult(tokens = output, apps = apps)
    }

    private fun keyOf(text: String): String =
        Normalizer.normalize(text, Normalizer.Form.NFC).lowercase(Locale.ROOT)
}
EOF

# ---------- 4. CommandNormalizer.kt ----------
cat > "$BASE/nlp/CommandNormalizer.kt" <<'EOF'
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
EOF

# ---------- 5. CommandInsightCard.kt ----------
cat > "$BASE/ui/components/CommandInsightCard.kt" <<'EOF'
package com.nova.ai.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.core.Language
import com.nova.ai.nlp.CommandNormalizer
import com.nova.ai.nlp.NormalizedCommand

/**
 * Shows how the app cleaned up the current command: the standard form,
 * the apps it recognized, and the detected language.
 * Shows nothing when [text] is blank.
 */
@Composable
fun CommandInsightCard(text: String, modifier: Modifier = Modifier) {
    if (text.isBlank()) return

    val insight: NormalizedCommand = remember(text) { CommandNormalizer.normalize(text) }

    val languageName: String = stringResource(
        when (insight.language) {
            Language.BANGLA -> R.string.insight_lang_bangla
            Language.ENGLISH -> R.string.insight_lang_english
            Language.MIXED -> R.string.insight_lang_mixed
            Language.UNKNOWN -> R.string.insight_lang_unknown
        }
    )
    val normalizedLine: String = stringResource(R.string.insight_normalized, insight.normalizedText)
    val languageLine: String = stringResource(R.string.insight_language, languageName)
    val appsLine: String? = if (insight.detectedApps.isEmpty()) {
        null
    } else {
        stringResource(R.string.insight_apps, insight.detectedApps.joinToString(", "))
    }

    val body: String = listOfNotNull(normalizedLine, appsLine, languageLine).joinToString("\n")

    NovaInfoCard(
        title = stringResource(R.string.insight_title),
        body = body,
        modifier = modifier
    )
}
EOF

# ---------- B. HomeScreen.kt: two additive lines (idempotent) ----------
if ! grep -q "CommandInsightCard" "$HOME_FILE"; then
  grep -q '^import com.nova.ai.ui.components.NovaScreenLayout$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen import anchor not found" >&2; exit 1; }
  grep -q '^        if (transcript.isNotEmpty()) {$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen layout anchor not found" >&2; exit 1; }

  sed -i '/^import com.nova.ai.ui.components.NovaScreenLayout$/a import com.nova.ai.ui.components.CommandInsightCard' "$HOME_FILE"
  sed -i '/^        if (transcript.isNotEmpty()) {$/i\        CommandInsightCard(text = commandText)\n' "$HOME_FILE"
fi
grep -q "CommandInsightCard(text = commandText)" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed" >&2; exit 1; }

# ---------- Commit and push ----------
git add -A
git commit -m "P9: mixed-language command normalizer and app name aliases"
git push

echo "P9 files created and pushed."
