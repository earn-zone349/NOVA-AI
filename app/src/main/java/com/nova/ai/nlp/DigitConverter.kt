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
