package com.nova.ai.nlp

/**
 * Word lists used by the rule-based intent parser.
 * Every entry is lowercase. To support a new spelling or word, add it here.
 */
internal object IntentVocabulary {

    // ----- Opening apps -----
    val OPEN_VERBS_STRONG: Set<String> = setOf(
        "খোলো", "খুলো", "খোল", "খুলুন", "খুলে", "খুল", "ওপেন", "ওপেনে", "open", "launch",
        "চালু", "চালাও", "চালান"
    )
    val GO_VERBS: Set<String> = setOf("যাও", "যান", "go")
    val APP_WORDS: Set<String> = setOf(
        "অ্যাপ", "অ্যাপটা", "অ্যাপটি", "এ্যাপ", "এপ", "এপটা", "app", "application"
    )

    // ----- Common helper words that carry no meaning of their own -----
    val HELPER_WORDS: Set<String> = setOf(
        "করো", "কর", "করুন", "করে", "দাও", "দিন", "দেখাও", "দেখান", "একটা", "একটি", "টা", "টি",
        "please", "plz", "the", "a", "an", "to", "for", "on", "in", "at", "my", "me", "now",
        "আমার", "আমাকে", "এটা", "ওটা", "এই", "ওই", "আমি", "তুমি",
        "can", "you", "could", "will", "would"
    )
    val COMMON_STRIP: Set<String> = setOf(
        "করো", "কর", "করুন", "করে", "দাও", "দিন", "দেখাও", "দেখান", "একটা", "একটি", "টা", "টি",
        "লিখে", "লিখো", "এ", "তে", "এবার", "এখন", "তারপর", "এরপর", "চাই",
        "for", "on", "in", "about", "please", "plz", "the", "a", "an", "to", "now"
    )

    // ----- Search -----
    val SEARCH_WORDS: Set<String> = setOf(
        "সার্চ", "সার্চে", "search", "খোঁজো", "খুঁজো", "খোঁজ", "খুঁজে", "খুঁজুন",
        "খোজো", "খুজো", "খোজ", "খুজে", "find"
    )

    // ----- Calls -----
    val CALL_WORDS: Set<String> = setOf("কল", "call", "ডায়াল", "dial", "ফোন")
    val CALL_NOISE: Set<String> = setOf("নম্বরে", "নম্বর", "নাম্বারে", "নাম্বার", "number")

    // ----- Messages -----
    val MESSAGE_STRONG: Set<String> = setOf(
        "মেসেজ", "মেসেজে", "message", "msg", "এসএমএস", "sms", "টেক্সট", "text",
        "পাঠাও", "পাঠান", "পাঠিয়ে", "জানাও", "জানিয়ে", "send", "tell"
    )
    val MESSAGE_WEAK: Set<String> = setOf("লিখো", "লেখো", "লিখুন", "লিখে", "বলো", "বলুন")
    val MESSAGE_GLUE: Set<String> = setOf("যে", "যেন", "that", "saying", "says", "say", "as")
    val MESSAGE_FILLER: Set<String> = setOf(
        "করো", "কর", "করুন", "দাও", "দিন", "please", "plz", "একটা", "একটি"
    )
    val CONTACT_SUFFIXES: List<String> = listOf("কেও", "কে")
    val NOT_NAMES: Set<String> = setOf("আমা", "তোমা", "তা", "কা", "আপনা", "ওকে", "এ")

    // ----- Media -----
    val MEDIA_NOUNS: Set<String> = setOf(
        "গান", "গানটা", "গানগুলো", "গানের", "song", "songs", "music", "মিউজিক",
        "ট্র্যাক", "track", "playlist", "প্লেলিস্ট", "ভিডিও", "ভিডিওটা", "video"
    )
    val MEDIA_VERBS: Set<String> = setOf(
        "play", "প্লে", "বাজাও", "বাজান", "pause", "পজ", "next", "skip", "স্কিপ",
        "previous", "resume", "রিজিউম"
    )
    val NEXT_WORDS: Set<String> = setOf("পরের", "পরেরটা", "next", "skip", "স্কিপ")
    val PREVIOUS_WORDS: Set<String> = setOf("আগের", "আগেরটা", "previous", "পিছনের")
    val PAUSE_WORDS: Set<String> = setOf("পজ", "pause", "থামাও", "থামান", "থামিয়ে", "বন্ধ")

    // ----- System actions -----
    /** Keywords per target. A keyword with a space is matched inside the whole text. */
    val SYSTEM_TARGETS: Map<String, List<String>> = linkedMapOf(
        SystemTarget.WIFI to listOf("wifi", "wi fi", "ওয়াইফাই", "ওয়াই ফাই"),
        SystemTarget.BLUETOOTH to listOf("bluetooth", "ব্লুটুথ", "ব্লু টুথ"),
        SystemTarget.FLASHLIGHT to listOf(
            "flashlight", "torch", "ফ্ল্যাশলাইট", "ফ্ল্যাশ লাইট", "ফ্ল্যাশ", "টর্চ"
        ),
        SystemTarget.VOLUME to listOf(
            "volume", "ভলিউম", "আওয়াজ", "mute", "মিউট", "সাইলেন্ট"
        ),
        SystemTarget.BRIGHTNESS to listOf("brightness", "ব্রাইটনেস", "উজ্জ্বলতা")
    )
    val ON_WORDS: Set<String> = setOf(
        "চালু", "অন", "on", "enable", "জ্বালাও", "জ্বালো", "জ্বেলে", "জ্বালান"
    )
    val OFF_WORDS: Set<String> = setOf(
        "বন্ধ", "অফ", "off", "disable", "নিভাও", "নেভাও", "নিভিয়ে", "নেভান", "নিভান"
    )
    val UP_WORDS: Set<String> = setOf(
        "বাড়াও", "বাড়িয়ে", "বাড়ান", "বেশি", "increase", "up", "louder", "max", "ফুল"
    )
    val DOWN_WORDS: Set<String> = setOf(
        "কমাও", "কমিয়ে", "কমান", "কম", "decrease", "down", "lower", "min"
    )
    val MUTE_WORDS: Set<String> = setOf("mute", "মিউট", "সাইলেন্ট", "silent")
    val SETTINGS_WORDS: Set<String> = setOf("settings", "setting", "সেটিংস", "সেটিং", "সেটিংসে")

    // ----- Alarm, timer, reminder -----
    val TIMER_WORDS: Set<String> = setOf("টাইমার", "টাইমারটা", "timer")
    val ALARM_WORDS: Set<String> = setOf(
        "অ্যালার্ম", "অ্যালার্মটা", "অ্যালার্মের", "এ্যালার্ম", "এলার্ম", "আলার্ম", "alarm",
        "জাগিয়ে", "জাগাও", "উঠিয়ে"
    )
    val REMINDER_WORDS: Set<String> = setOf("রিমাইন্ডার", "রিমাইন্ড", "reminder", "remind")
    val REMIND_VERBS: Set<String> = setOf("করিয়ে", "করাও", "করিও")
    val AFTER_WORDS: Set<String> = setOf("পরে", "পর", "later", "after", "মধ্যে", "within", "in")
    val MINUTE_UNITS: Set<String> = setOf(
        "মিনিট", "মিনিটে", "মিনিটের", "minute", "minutes", "min", "mins"
    )
    val HOUR_UNITS: Set<String> = setOf(
        "ঘণ্টা", "ঘন্টা", "ঘণ্টায়", "ঘন্টায়", "ঘণ্টার", "ঘন্টার", "hour", "hours", "hr"
    )
    val SECOND_UNITS: Set<String> = setOf("সেকেন্ড", "সেকেন্ডে", "second", "seconds", "sec")
    val HALF_WORDS: Set<String> = setOf("আধা", "আধ", "half")
    val ONE_AND_HALF_WORDS: Set<String> = setOf("দেড়", "দেড")
    val AM_WORDS: Set<String> = setOf("সকাল", "সকালে", "ভোর", "ভোরে", "am", "morning")
    val PM_WORDS: Set<String> = setOf(
        "দুপুর", "দুপুরে", "বিকাল", "বিকেল", "বিকালে", "বিকেলে", "সন্ধ্যা", "সন্ধ্যায়",
        "রাত", "রাতে", "pm", "evening", "afternoon", "night"
    )
    val NIGHT_WORDS: Set<String> = setOf("রাত", "রাতে", "night")
    val QUALIFIER_WORDS: Set<String> = setOf("সাড়ে", "সোয়া", "পৌনে")
    val TIME_SUFFIXES: List<String> = listOf("টায়", "টার", "টা")

    val WORD_NUMBERS: Map<String, Int> = mapOf(
        "এক" to 1, "দুই" to 2, "দু" to 2, "তিন" to 3, "চার" to 4, "পাঁচ" to 5, "পাচ" to 5,
        "ছয়" to 6, "সাত" to 7, "আট" to 8, "নয়" to 9, "দশ" to 10, "এগারো" to 11, "এগার" to 11,
        "বারো" to 12, "পনেরো" to 15, "পনের" to 15, "বিশ" to 20, "পঁচিশ" to 25, "ত্রিশ" to 30,
        "চল্লিশ" to 40, "পঞ্চাশ" to 50,
        "one" to 1, "two" to 2, "three" to 3, "four" to 4, "five" to 5, "six" to 6,
        "seven" to 7, "eight" to 8, "nine" to 9, "ten" to 10, "eleven" to 11, "twelve" to 12
    )
}
