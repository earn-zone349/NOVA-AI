package com.nova.ai.time

/** Writes times and durations in Bangla, with Bangla digits. Pure logic. */
object TimeText {

    private val BANGLA_DIGITS: CharArray =
        charArrayOf('০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯')

    private const val SECONDS_PER_MINUTE: Int = 60
    private const val SECONDS_PER_HOUR: Int = 3600

    /** Turns digits 0 to 9 in [text] into Bangla digits. */
    fun digits(text: String): String =
        text.map { character ->
            if (character in '0'..'9') BANGLA_DIGITS[character - '0'] else character
        }.joinToString("")

    /** For example 7 and 0 give "সকাল ৭:০০"; 17 and 30 give "বিকাল ৫:৩০". */
    fun clock(hour24: Int, minute: Int): String {
        val hour12: Int = if (hour24 % 12 == 0) 12 else hour24 % 12
        val minuteText: String = minute.toString().padStart(2, '0')
        return "${periodWord(hour24)} ${digits("$hour12:$minuteText")}"
    }

    /** For example 300 gives "৫ মিনিট"; 5400 gives "১ ঘণ্টা ৩০ মিনিট". */
    fun duration(totalSeconds: Int): String {
        val hours: Int = totalSeconds / SECONDS_PER_HOUR
        val minutes: Int = (totalSeconds % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE
        val seconds: Int = totalSeconds % SECONDS_PER_MINUTE

        val parts = ArrayList<String>()
        if (hours > 0) parts.add("${digits(hours.toString())} ঘণ্টা")
        if (minutes > 0) parts.add("${digits(minutes.toString())} মিনিট")
        if (seconds > 0) parts.add("${digits(seconds.toString())} সেকেন্ড")
        return parts.joinToString(" ")
    }

    private fun periodWord(hour24: Int): String = when (hour24) {
        in 4..5 -> "ভোর"
        in 6..11 -> "সকাল"
        in 12..14 -> "দুপুর"
        in 15..17 -> "বিকাল"
        in 18..19 -> "সন্ধ্যা"
        else -> "রাত"
    }
}
