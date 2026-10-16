package com.nova.ai.voice

import com.nova.ai.core.Language

/**
 * Detects whether a piece of text is Bangla, English, or a mix of both,
 * by counting Bangla-script and Latin letters. Pure logic, no Android needed.
 */
object LanguageDetector {

    private const val BANGLA_RANGE_START: Int = 0x0980
    private const val BANGLA_RANGE_END: Int = 0x09FF

    /** If neither script reaches this share of letters, the text counts as mixed. */
    private const val MIXED_THRESHOLD: Float = 0.15f

    /** Returns the dominant [Language] of [text], or UNKNOWN if it has no letters. */
    fun detect(text: String): Language {
        var banglaCount = 0
        var latinCount = 0

        for (character in text) {
            val isBangla: Boolean = character.code in BANGLA_RANGE_START..BANGLA_RANGE_END
            val isLatin: Boolean = character in 'a'..'z' || character in 'A'..'Z'
            if (isBangla) banglaCount++ else if (isLatin) latinCount++
        }

        val total: Int = banglaCount + latinCount
        if (total == 0) return Language.UNKNOWN

        val banglaShare: Float = banglaCount.toFloat() / total.toFloat()
        return when {
            banglaShare >= 1f - MIXED_THRESHOLD -> Language.BANGLA
            banglaShare <= MIXED_THRESHOLD -> Language.ENGLISH
            else -> Language.MIXED
        }
    }
}
