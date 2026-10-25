package com.nova.ai.accessibility

import java.util.Locale

/**
 * Rules that keep secrets out of what NOVA reads: password fields, PIN and OTP
 * fields, and code numbers inside messages. These are best-effort rules based on
 * field names and nearby words; they are tightened in the security phase.
 */
object SensitiveNodePolicy {

    private const val MASK: String = "••••"

    // Whole words only, so "spinner" or "pinterest" do not count as "pin".
    private val FIELD_KEYWORDS: Set<String> = setOf(
        "password", "passcode", "passwd", "pwd", "pin", "otp", "cvv", "cvc", "secret",
        "পাসওয়ার্ড", "পিন", "ওটিপি", "পাসকোড"
    )

    private val WORD_SPLIT: Regex = Regex("[^\\p{L}\\p{N}\\p{M}]+")
    private val CODE_WORDS: Regex = Regex("(?i)(otp|pin|passcode|verification|code|ওটিপি|পিন|কোড|পাসকোড)")
    private val DIGIT_RUN: Regex = Regex("[0-9০-৯]{4,8}")

    /** True if an input field should never be read: password fields and PIN, OTP, CVV style fields. */
    fun isSensitiveField(
        isPassword: Boolean,
        isEditable: Boolean,
        viewId: String,
        hint: String,
        description: String
    ): Boolean {
        if (isPassword) return true
        if (!isEditable) return false
        return listOf(viewId, hint, description).any { source ->
            WORD_SPLIT.split(source.lowercase(Locale.ROOT)).any { word -> word in FIELD_KEYWORDS }
        }
    }

    /** Hides number groups of 4 to 8 digits when the text talks about a code, OTP or PIN. */
    fun maskCodes(text: String): String {
        if (text.isEmpty() || !CODE_WORDS.containsMatchIn(text)) return text
        return DIGIT_RUN.replace(text, MASK)
    }
}
