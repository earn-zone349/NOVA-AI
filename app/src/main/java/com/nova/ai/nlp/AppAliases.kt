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
