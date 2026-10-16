#!/usr/bin/env bash
# NOVA AI - Phase 11 setup script: rule-based command understanding (intent parser).
# Additive: new classes + one insight card; HomeScreen gets two new lines only.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
HOME_FILE="$BASE/ui/screens/HomeScreen.kt"

if [ ! -f "$BASE/nlp/CommandNormalizer.kt" ] || [ ! -f "$HOME_FILE" ] || [ ! -f "$BASE/brain/AiBrain.kt" ]; then
  echo "ERROR: Run from repo root after P1 to P9 are installed." >&2
  exit 1
fi

# ---------- A. Strings ----------
cat > app/src/main/res/values/strings_p11.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="intent_title">বোঝা উদ্দেশ্য</string>
    <string name="intent_confidence">নিশ্চিততা: %1$d%%</string>
    <string name="intent_note">বোঝা হয়ে গেছে। কাজটি সত্যি করা শুরু হবে P12 থেকে।</string>
    <string name="intent_unknown_hint">এই কমান্ডটি এখনো বুঝতে পারিনি। অন্যভাবে বলে দেখো।</string>
    <string name="intent_error">বিশ্লেষণে সমস্যা: %1$s</string>

    <string name="intent_type_open_app">উদ্দেশ্য: অ্যাপ খোলা</string>
    <string name="intent_type_send_message">উদ্দেশ্য: মেসেজ পাঠানো</string>
    <string name="intent_type_make_call">উদ্দেশ্য: কল করা</string>
    <string name="intent_type_web_search">উদ্দেশ্য: সার্চ করা</string>
    <string name="intent_type_system_action">উদ্দেশ্য: সিস্টেম কাজ</string>
    <string name="intent_type_set_alarm">উদ্দেশ্য: অ্যালার্ম / টাইমার / রিমাইন্ডার</string>
    <string name="intent_type_media_control">উদ্দেশ্য: গান / মিডিয়া নিয়ন্ত্রণ</string>
    <string name="intent_type_unknown">উদ্দেশ্য: বোঝা যায়নি</string>

    <string name="intent_entity_app">অ্যাপ</string>
    <string name="intent_entity_app_source">অ্যাপের উৎস</string>
    <string name="intent_entity_query">খোঁজার বিষয়</string>
    <string name="intent_entity_contact">ব্যক্তি</string>
    <string name="intent_entity_number">নম্বর</string>
    <string name="intent_entity_body">বার্তা</string>
    <string name="intent_entity_action">কাজ</string>
    <string name="intent_entity_target">লক্ষ্য</string>
    <string name="intent_entity_value">মান</string>
    <string name="intent_entity_mode">ধরন</string>
    <string name="intent_entity_hour">ঘণ্টা</string>
    <string name="intent_entity_minute">মিনিট</string>
    <string name="intent_entity_period">সময়ের ভাগ</string>
    <string name="intent_entity_hour24">২৪ ঘণ্টার হিসাবে ঘণ্টা</string>
    <string name="intent_entity_duration">সময়কাল</string>

    <string name="intent_value_on">চালু</string>
    <string name="intent_value_off">বন্ধ</string>
    <string name="intent_value_up">বাড়ানো</string>
    <string name="intent_value_down">কমানো</string>
    <string name="intent_value_set">নির্দিষ্ট মানে করা</string>
    <string name="intent_value_mute">শব্দ বন্ধ (মিউট)</string>
    <string name="intent_value_open_settings">সেটিংস খোলা</string>
    <string name="intent_value_play">চালানো</string>
    <string name="intent_value_pause">থামানো (পজ)</string>
    <string name="intent_value_next">পরের গান</string>
    <string name="intent_value_previous">আগের গান</string>
    <string name="intent_value_wifi">ওয়াইফাই</string>
    <string name="intent_value_bluetooth">ব্লুটুথ</string>
    <string name="intent_value_flashlight">টর্চ</string>
    <string name="intent_value_volume">ভলিউম</string>
    <string name="intent_value_brightness">ব্রাইটনেস</string>
    <string name="intent_value_alarm">অ্যালার্ম</string>
    <string name="intent_value_timer">টাইমার</string>
    <string name="intent_value_reminder">রিমাইন্ডার</string>
    <string name="intent_value_am">সকাল (AM)</string>
    <string name="intent_value_pm">দুপুর থেকে রাত (PM)</string>
    <string name="intent_value_unknown">জানা নেই</string>
    <string name="intent_value_context">আগের কমান্ড থেকে</string>

    <string name="intent_duration_hours">%1$d ঘণ্টা</string>
    <string name="intent_duration_minutes">%1$d মিনিট</string>
    <string name="intent_duration_seconds">%1$d সেকেন্ড</string>
</resources>
EOF

mkdir -p "$BASE/nlp" "$BASE/brain" "$BASE/ui/components"

# ---------- 1. IntentEntity.kt ----------
cat > "$BASE/nlp/IntentEntity.kt" <<'EOF'
package com.nova.ai.nlp

/** Names of the details (entities) found inside a command. */
object IntentEntity {
    const val APP: String = "app"
    const val APP_SOURCE: String = "app_source"
    const val QUERY: String = "query"
    const val CONTACT: String = "contact"
    const val NUMBER: String = "number"
    const val BODY: String = "body"
    const val ACTION: String = "action"
    const val TARGET: String = "target"
    const val VALUE: String = "value"
    const val MODE: String = "mode"
    const val HOUR: String = "hour"
    const val MINUTE: String = "minute"
    const val PERIOD: String = "period"
    const val HOUR24: String = "hour24"
    const val DURATION_SECONDS: String = "duration_seconds"
}

/** Values of the [IntentEntity.ACTION] detail. */
object IntentAction {
    const val ON: String = "on"
    const val OFF: String = "off"
    const val UP: String = "up"
    const val DOWN: String = "down"
    const val SET: String = "set"
    const val MUTE: String = "mute"
    const val OPEN_SETTINGS: String = "open_settings"
    const val PLAY: String = "play"
    const val PAUSE: String = "pause"
    const val NEXT: String = "next"
    const val PREVIOUS: String = "previous"
}

/** Values of the [IntentEntity.TARGET] detail for system actions. */
object SystemTarget {
    const val WIFI: String = "wifi"
    const val BLUETOOTH: String = "bluetooth"
    const val FLASHLIGHT: String = "flashlight"
    const val VOLUME: String = "volume"
    const val BRIGHTNESS: String = "brightness"
}

/** Values of the [IntentEntity.MODE] detail for time based commands. */
object IntentMode {
    const val ALARM: String = "alarm"
    const val TIMER: String = "timer"
    const val REMINDER: String = "reminder"
}

/** Values of the [IntentEntity.PERIOD] detail. */
object IntentPeriod {
    const val AM: String = "am"
    const val PM: String = "pm"
    const val UNKNOWN: String = "unknown"
}

/** Values of the [IntentEntity.APP_SOURCE] detail. */
object IntentSource {
    const val CONTEXT: String = "context"
}
EOF

# ---------- 2. IntentVocabulary.kt ----------
cat > "$BASE/nlp/IntentVocabulary.kt" <<'EOF'
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
EOF

# ---------- 3. CommandView.kt ----------
cat > "$BASE/nlp/CommandView.kt" <<'EOF'
package com.nova.ai.nlp

import java.util.Locale

/** Read-only helper that gives the parser easy questions to ask about one command. */
internal class CommandView(command: NormalizedCommand) {

    /** Cleaned text, lowercase. */
    val text: String = command.normalizedText.lowercase(Locale.ROOT)

    /** Cleaned words, lowercase. App names are in their standard form (also lowercase here). */
    val lowerTokens: List<String> = command.tokens.map { it.lowercase(Locale.ROOT) }

    /** Standard names of the apps found in the command, in order. */
    val apps: List<String> = command.detectedApps

    private val appTokenSet: Set<String> = apps.map { it.lowercase(Locale.ROOT) }.toSet()

    fun hasAny(words: Set<String>): Boolean = lowerTokens.any { it in words }

    fun has(word: String): Boolean = word in lowerTokens

    fun isAppToken(lowerToken: String): Boolean = lowerToken in appTokenSet

    /** True if [keyword] appears as a word (or word start), or inside the text for multi-word keywords. */
    fun mentions(keyword: String): Boolean =
        if (keyword.contains(' ')) text.contains(keyword) else lowerTokens.any { it.startsWith(keyword) }

    /** Words that are not app names and not in any of the [excluded] sets. */
    fun remaining(vararg excluded: Set<String>): List<String> =
        lowerTokens.filter { token ->
            !isAppToken(token) && excluded.none { set -> token in set }
        }

    /** First word that is only ASCII digits, as a number. */
    fun firstNumber(): Int? {
        for (token in lowerTokens) {
            if (token.isNotEmpty() && token.all { it in '0'..'9' }) {
                val value: Int? = token.toIntOrNull()
                if (value != null) return value
            }
        }
        return null
    }
}
EOF

# ---------- 4. IntentParser.kt ----------
cat > "$BASE/nlp/IntentParser.kt" <<'EOF'
package com.nova.ai.nlp

import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent

/**
 * Rule-based command understanding. Turns a [NormalizedCommand] into a [NovaIntent]
 * (what the user wants, plus details such as app, contact, time).
 * Pure logic, no Android needed. Later phases add a local language model on top;
 * this parser stays as the fast, reliable first step.
 */
object IntentParser {

    /** How many earlier commands are used to understand follow-ups like "now search that". */
    const val MAX_CONTEXT: Int = 3

    private const val CONF_HIGH: Float = 0.9f
    private const val CONF_MEDIUM: Float = 0.75f
    private const val CONF_BARE: Float = 0.7f
    private const val CONF_LOW: Float = 0.5f

    private const val MAX_APP_NAME_WORDS: Int = 4
    private const val MAX_CONTACT_WORDS: Int = 3
    private const val MIN_PHONE_DIGITS: Int = 5
    private const val MAX_HOUR: Int = 23
    private const val MAX_MINUTE: Int = 59
    private const val SECONDS_PER_MINUTE: Int = 60
    private const val SECONDS_PER_HOUR: Int = 3600

    private data class ContactMatch(val name: String, val tokenIndex: Int)
    private data class HourHit(val hour: Int, val minute: Int, val index: Int)
    private data class ClockTime(val hour: Int, val minute: Int, val period: String, val hour24: Int?)

    /** Understands [command]. [context] holds earlier commands, oldest first. */
    fun parse(
        command: NormalizedCommand,
        context: List<NormalizedCommand> = emptyList()
    ): NovaIntent {
        val view = CommandView(command)
        if (view.lowerTokens.isEmpty()) return unknown()

        val parsed: NovaIntent = parseAlarm(view)
            ?: parseSystem(view)
            ?: parseCall(view)
            ?: parseSearch(view)
            ?: parseMessage(view)
            ?: parseMedia(view)
            ?: parseOpenApp(view)
            ?: unknown()

        return applyContext(parsed, context.takeLast(MAX_CONTEXT))
    }

    private fun unknown(): NovaIntent = NovaIntent(IntentType.UNKNOWN, emptyMap(), 0f)

    // ---------------------------------------------------------------- alarm, timer, reminder

    private fun parseAlarm(v: CommandView): NovaIntent? {
        val mode: String = when {
            v.hasAny(IntentVocabulary.TIMER_WORDS) -> IntentMode.TIMER
            v.hasAny(IntentVocabulary.ALARM_WORDS) -> IntentMode.ALARM
            isReminder(v) -> IntentMode.REMINDER
            else -> return null
        }
        val entities = linkedMapOf(IntentEntity.MODE to mode)

        val allowDuration: Boolean =
            mode == IntentMode.TIMER || v.hasAny(IntentVocabulary.AFTER_WORDS)
        val seconds: Int = if (allowDuration) durationSeconds(v.lowerTokens) else 0

        var confidence: Float = CONF_LOW
        if (seconds > 0) {
            entities[IntentEntity.DURATION_SECONDS] = seconds.toString()
            confidence = CONF_HIGH
        } else {
            val clock: ClockTime? = parseClock(v.lowerTokens)
            if (clock != null) {
                entities[IntentEntity.HOUR] = clock.hour.toString()
                entities[IntentEntity.MINUTE] = clock.minute.toString()
                entities[IntentEntity.PERIOD] = clock.period
                if (clock.hour24 != null) entities[IntentEntity.HOUR24] = clock.hour24.toString()
                confidence = CONF_HIGH
            }
        }

        if (mode == IntentMode.REMINDER) {
            val body: String = reminderBody(v)
            if (body.isNotEmpty()) entities[IntentEntity.BODY] = body
        }
        return NovaIntent(IntentType.SET_ALARM, entities, confidence)
    }

    private fun isReminder(v: CommandView): Boolean =
        v.hasAny(IntentVocabulary.REMINDER_WORDS) ||
            (v.has("মনে") && v.hasAny(IntentVocabulary.REMIND_VERBS))

    private fun reminderBody(v: CommandView): String {
        val words: List<String> = v.remaining(
            IntentVocabulary.REMINDER_WORDS,
            IntentVocabulary.REMIND_VERBS,
            IntentVocabulary.HELPER_WORDS,
            IntentVocabulary.COMMON_STRIP,
            IntentVocabulary.AM_WORDS,
            IntentVocabulary.PM_WORDS,
            IntentVocabulary.QUALIFIER_WORDS,
            IntentVocabulary.MINUTE_UNITS,
            IntentVocabulary.HOUR_UNITS,
            IntentVocabulary.SECOND_UNITS,
            IntentVocabulary.AFTER_WORDS,
            setOf("মনে")
        )
        return words
            .filter { it.isNotEmpty() && it[0] !in '0'..'9' && clockWordNumber(it) == null }
            .joinToString(" ")
    }

    /** Total seconds of phrases like "5 minutes", "1 hour", "আধা ঘণ্টা". 0 if none. */
    private fun durationSeconds(tokens: List<String>): Int {
        var total = 0
        for (index in tokens.indices) {
            val token: String = tokens[index]
            val unitSeconds: Int = when {
                token in IntentVocabulary.MINUTE_UNITS -> SECONDS_PER_MINUTE
                token in IntentVocabulary.HOUR_UNITS -> SECONDS_PER_HOUR
                token in IntentVocabulary.SECOND_UNITS -> 1
                else -> 0
            }
            if (unitSeconds == 0 || index == 0) continue

            val previous: String = tokens[index - 1]
            val amount: Int? = when {
                previous in IntentVocabulary.HALF_WORDS -> unitSeconds / 2
                previous in IntentVocabulary.ONE_AND_HALF_WORDS -> unitSeconds * 3 / 2
                else -> numberOf(previous)?.let { it * unitSeconds }
            }
            if (amount != null) total += amount
        }
        return total
    }

    private fun parseClock(tokens: List<String>): ClockTime? {
        val hit: HourHit = findHour(tokens) ?: return null
        var hour: Int = hit.hour
        var minute: Int = hit.minute

        if (minute == 0) {
            when {
                tokens.contains("সাড়ে") -> minute = 30
                tokens.contains("সোয়া") -> minute = 15
                tokens.contains("পৌনে") -> {
                    minute = 45
                    hour = if (hour <= 1) 12 else hour - 1
                }
                else -> {
                    val next: String? = tokens.getOrNull(hit.index + 1)
                    if (next != null && next.isNotEmpty() && next.all { it in '0'..'9' }) {
                        val parsed: Int? = next.toIntOrNull()
                        if (parsed != null && parsed in 0..MAX_MINUTE) minute = parsed
                    }
                }
            }
        }
        if (hour > MAX_HOUR || minute > MAX_MINUTE) return null

        val isPm: Boolean = tokens.any { it in IntentVocabulary.PM_WORDS }
        val isAm: Boolean = tokens.any { it in IntentVocabulary.AM_WORDS }
        val isNight: Boolean = tokens.any { it in IntentVocabulary.NIGHT_WORDS }

        val hour24: Int? = when {
            isPm && isNight && hour in 1..5 -> hour
            isPm && isNight && hour == 12 -> 0
            isPm -> if (hour < 12) hour + 12 else hour
            isAm -> if (hour == 12) 0 else hour
            hour >= 13 || hour == 0 -> hour
            else -> null
        }
        val period: String = when {
            hour24 == null -> IntentPeriod.UNKNOWN
            hour24 >= 12 -> IntentPeriod.PM
            else -> IntentPeriod.AM
        }
        return ClockTime(hour = hour, minute = minute, period = period, hour24 = hour24)
    }

    /** Finds the hour: digits first ("7টায়", "7"), then number words with a time ending ("সাতটায়"). */
    private fun findHour(tokens: List<String>): HourHit? {
        for (index in tokens.indices) {
            val token: String = tokens[index]
            if (token.startsWith("দেড়")) return HourHit(1, 30, index)
            if (token.startsWith("আড়াই")) return HourHit(2, 30, index)
            if (token.isNotEmpty() && token[0] in '0'..'9') {
                val value: Int = token.takeWhile { it in '0'..'9' }.toIntOrNull() ?: continue
                return HourHit(value, 0, index)
            }
        }
        for (index in tokens.indices) {
            val value: Int? = clockWordNumber(tokens[index])
            if (value != null) return HourHit(value, 0, index)
        }
        return null
    }

    /** "সাতটায়" gives 7. The plain word "একটা" means "a", so it is skipped. */
    private fun clockWordNumber(token: String): Int? {
        if (token == "একটা" || token == "একটি") return null
        val suffix: String = IntentVocabulary.TIME_SUFFIXES.firstOrNull { token.endsWith(it) }
            ?: return null
        return IntentVocabulary.WORD_NUMBERS[token.removeSuffix(suffix)]
    }

    /** A number written with digits ("5", "5টা") or as a word ("পাঁচ"). */
    private fun numberOf(token: String): Int? {
        if (token.isEmpty()) return null
        if (token[0] in '0'..'9') return token.takeWhile { it in '0'..'9' }.toIntOrNull()
        return IntentVocabulary.WORD_NUMBERS[token]
    }

    // ---------------------------------------------------------------- system actions

    private fun parseSystem(v: CommandView): NovaIntent? {
        var target: String? = null
        for ((name, keywords) in IntentVocabulary.SYSTEM_TARGETS) {
            if (keywords.any { keyword -> v.mentions(keyword) }) {
                target = name
                break
            }
        }
        val foundTarget: String = target ?: return null

        val value: Int? = v.firstNumber()
        val adjustable: Boolean =
            foundTarget == SystemTarget.VOLUME || foundTarget == SystemTarget.BRIGHTNESS
        val action: String? = when {
            v.hasAny(IntentVocabulary.MUTE_WORDS) -> IntentAction.MUTE
            v.hasAny(IntentVocabulary.UP_WORDS) -> IntentAction.UP
            v.hasAny(IntentVocabulary.DOWN_WORDS) -> IntentAction.DOWN
            v.hasAny(IntentVocabulary.OFF_WORDS) -> IntentAction.OFF
            v.hasAny(IntentVocabulary.ON_WORDS) -> IntentAction.ON
            value != null && adjustable -> IntentAction.SET
            v.hasAny(IntentVocabulary.OPEN_VERBS_STRONG) ||
                v.hasAny(IntentVocabulary.SETTINGS_WORDS) -> IntentAction.OPEN_SETTINGS
            else -> null
        }

        val entities = linkedMapOf(IntentEntity.TARGET to foundTarget)
        if (action != null) entities[IntentEntity.ACTION] = action
        if (action == IntentAction.SET && value != null) {
            entities[IntentEntity.VALUE] = value.toString()
        }
        return NovaIntent(
            IntentType.SYSTEM_ACTION,
            entities,
            if (action != null) CONF_HIGH else CONF_LOW
        )
    }

    // ---------------------------------------------------------------- calls

    private fun parseCall(v: CommandView): NovaIntent? {
        if (!v.hasAny(IntentVocabulary.CALL_WORDS)) return null

        val entities = linkedMapOf<String, String>()
        val number: String? = findPhoneNumber(v)
        if (number != null) {
            entities[IntentEntity.NUMBER] = number
        } else {
            val name: String? = findContact(v)?.name ?: guessName(
                v,
                IntentVocabulary.CALL_WORDS,
                IntentVocabulary.CALL_NOISE
            )
            if (name != null) entities[IntentEntity.CONTACT] = name
        }
        val app: String? = v.apps.firstOrNull()
        if (app != null) entities[IntentEntity.APP] = app

        val hasTarget: Boolean =
            IntentEntity.NUMBER in entities || IntentEntity.CONTACT in entities
        return NovaIntent(
            IntentType.MAKE_CALL,
            entities,
            if (hasTarget) CONF_HIGH else CONF_LOW
        )
    }

    /** Longest run of digit words with at least [MIN_PHONE_DIGITS] digits ("017 1234 5678"). */
    private fun findPhoneNumber(v: CommandView): String? {
        var best = ""
        val current = StringBuilder()
        for (token in v.lowerTokens) {
            if (token.isNotEmpty() && token.all { it in '0'..'9' }) {
                current.append(token)
            } else {
                if (current.length > best.length) best = current.toString()
                current.setLength(0)
            }
        }
        if (current.length > best.length) best = current.toString()
        return if (best.length >= MIN_PHONE_DIGITS) best else null
    }

    /** Finds a person: a word ending in "কে" ("সুমনকে") or the word after "to". */
    private fun findContact(v: CommandView): ContactMatch? {
        val tokens: List<String> = v.lowerTokens
        for (index in tokens.indices) {
            val token: String = tokens[index]
            if (token in IntentVocabulary.HELPER_WORDS || v.isAppToken(token)) continue
            for (suffix in IntentVocabulary.CONTACT_SUFFIXES) {
                if (token.length > suffix.length && token.endsWith(suffix)) {
                    val name: String = token.removeSuffix(suffix)
                    if (name !in IntentVocabulary.NOT_NAMES) return ContactMatch(name, index)
                }
            }
        }
        val toIndex: Int = tokens.indexOf("to")
        if (toIndex >= 0 && toIndex + 1 < tokens.size) {
            val candidate: String = tokens[toIndex + 1]
            val usable: Boolean = candidate !in IntentVocabulary.HELPER_WORDS &&
                !v.isAppToken(candidate) &&
                candidate[0] !in '0'..'9'
            if (usable) return ContactMatch(candidate, toIndex + 1)
        }
        return null
    }

    /** Last resort: the few words left over after removing known words are taken as a name. */
    private fun guessName(v: CommandView, vararg extraExcluded: Set<String>): String? {
        val leftover: List<String> = v.remaining(IntentVocabulary.HELPER_WORDS, *extraExcluded)
            .filter { it.isNotEmpty() && it[0] !in '0'..'9' }
        if (leftover.isEmpty() || leftover.size > MAX_CONTACT_WORDS) return null
        return leftover.joinToString(" ")
    }

    // ---------------------------------------------------------------- search

    private fun parseSearch(v: CommandView): NovaIntent? {
        if (!v.hasAny(IntentVocabulary.SEARCH_WORDS)) return null

        val queryWords: List<String> = v.remaining(
            IntentVocabulary.SEARCH_WORDS,
            IntentVocabulary.COMMON_STRIP,
            IntentVocabulary.OPEN_VERBS_STRONG
        )
        val entities = linkedMapOf<String, String>()
        val app: String? = v.apps.firstOrNull()
        if (app != null) entities[IntentEntity.APP] = app
        if (queryWords.isNotEmpty()) entities[IntentEntity.QUERY] = queryWords.joinToString(" ")

        return NovaIntent(
            IntentType.WEB_SEARCH,
            entities,
            if (queryWords.isNotEmpty()) CONF_HIGH else CONF_LOW
        )
    }

    // ---------------------------------------------------------------- messages

    private fun parseMessage(v: CommandView): NovaIntent? {
        val strong: Boolean = v.hasAny(IntentVocabulary.MESSAGE_STRONG)
        val weak: Boolean = v.hasAny(IntentVocabulary.MESSAGE_WEAK)
        val contact: ContactMatch? = findContact(v)
        if (!strong && !(weak && contact != null)) return null

        val entities = linkedMapOf<String, String>()
        val app: String? = v.apps.firstOrNull()
            ?: if (v.has("sms") || v.has("এসএমএস")) "SMS" else null
        if (app != null) entities[IntentEntity.APP] = app
        if (contact != null) entities[IntentEntity.CONTACT] = contact.name

        val bodyWords: List<String> = v.lowerTokens.filterIndexed { index, token ->
            val isContactWord: Boolean = contact != null && index == contact.tokenIndex
            val isToBeforeContact: Boolean =
                token == "to" && contact != null && index == contact.tokenIndex - 1
            !isContactWord &&
                !isToBeforeContact &&
                !v.isAppToken(token) &&
                token !in IntentVocabulary.MESSAGE_STRONG &&
                token !in IntentVocabulary.MESSAGE_WEAK &&
                token !in IntentVocabulary.MESSAGE_GLUE &&
                token !in IntentVocabulary.MESSAGE_FILLER
        }
        if (bodyWords.isNotEmpty()) entities[IntentEntity.BODY] = bodyWords.joinToString(" ")

        val confidence: Float = when {
            contact != null && bodyWords.isNotEmpty() -> CONF_HIGH
            contact != null -> CONF_MEDIUM
            else -> CONF_LOW
        }
        return NovaIntent(IntentType.SEND_MESSAGE, entities, confidence)
    }

    // ---------------------------------------------------------------- media

    private fun parseMedia(v: CommandView): NovaIntent? {
        if (!v.hasAny(IntentVocabulary.MEDIA_NOUNS) && !v.hasAny(IntentVocabulary.MEDIA_VERBS)) {
            return null
        }
        val action: String = when {
            v.hasAny(IntentVocabulary.NEXT_WORDS) -> IntentAction.NEXT
            v.hasAny(IntentVocabulary.PREVIOUS_WORDS) -> IntentAction.PREVIOUS
            v.hasAny(IntentVocabulary.PAUSE_WORDS) -> IntentAction.PAUSE
            else -> IntentAction.PLAY
        }
        val entities = linkedMapOf(IntentEntity.ACTION to action)
        val app: String? = v.apps.firstOrNull()
        if (app != null) entities[IntentEntity.APP] = app

        if (action == IntentAction.PLAY) {
            val queryWords: List<String> = v.remaining(
                IntentVocabulary.MEDIA_NOUNS,
                IntentVocabulary.MEDIA_VERBS,
                IntentVocabulary.HELPER_WORDS,
                IntentVocabulary.COMMON_STRIP,
                IntentVocabulary.OPEN_VERBS_STRONG
            )
            if (queryWords.isNotEmpty()) entities[IntentEntity.QUERY] = queryWords.joinToString(" ")
        }
        return NovaIntent(IntentType.MEDIA_CONTROL, entities, CONF_HIGH)
    }

    // ---------------------------------------------------------------- open app

    private fun parseOpenApp(v: CommandView): NovaIntent? {
        val hasOpenVerb: Boolean = v.hasAny(IntentVocabulary.OPEN_VERBS_STRONG)
        val hasGoVerb: Boolean = v.hasAny(IntentVocabulary.GO_VERBS)
        val knownApp: String? = v.apps.firstOrNull()

        if (knownApp != null) {
            val confidence: Float = when {
                hasOpenVerb || hasGoVerb -> CONF_HIGH
                v.lowerTokens.size <= 2 -> CONF_BARE
                else -> return null
            }
            return NovaIntent(IntentType.OPEN_APP, mapOf(IntentEntity.APP to knownApp), confidence)
        }

        // Any other app: the words left after the opening verb are taken as the app name.
        if (!hasOpenVerb) return null
        val nameWords: List<String> = v.remaining(
            IntentVocabulary.OPEN_VERBS_STRONG,
            IntentVocabulary.APP_WORDS,
            IntentVocabulary.HELPER_WORDS,
            IntentVocabulary.COMMON_STRIP
        )
        if (nameWords.isEmpty() || nameWords.size > MAX_APP_NAME_WORDS) return null
        return NovaIntent(
            IntentType.OPEN_APP,
            mapOf(IntentEntity.APP to nameWords.joinToString(" ")),
            CONF_MEDIUM
        )
    }

    // ---------------------------------------------------------------- context

    /** Fills a missing app from the most recent earlier command that named one. */
    private fun applyContext(intent: NovaIntent, context: List<NormalizedCommand>): NovaIntent {
        val needsApp: Boolean =
            intent.type == IntentType.WEB_SEARCH || intent.type == IntentType.MEDIA_CONTROL
        if (!needsApp || IntentEntity.APP in intent.entities) return intent

        val appFromContext: String = context.asReversed()
            .firstNotNullOfOrNull { it.detectedApps.firstOrNull() }
            ?: return intent

        val updated = LinkedHashMap(intent.entities)
        updated[IntentEntity.APP] = appFromContext
        updated[IntentEntity.APP_SOURCE] = IntentSource.CONTEXT
        return intent.copy(entities = updated)
    }
}
EOF

# ---------- 5. RuleBasedBrain.kt ----------
cat > "$BASE/brain/RuleBasedBrain.kt" <<'EOF'
package com.nova.ai.brain

import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.nlp.CommandNormalizer
import com.nova.ai.nlp.IntentParser
import com.nova.ai.nlp.NormalizedCommand

/**
 * The first "brain": understands commands with clear rules. Fast, works offline,
 * and never crashes on odd input. A local language model joins later (Phase 39+).
 */
class RuleBasedBrain : AiBrain {

    override fun analyze(
        command: VoiceCommand,
        recentContext: List<VoiceCommand>
    ): NovaResult<NovaIntent> {
        if (command.rawText.isBlank()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, "খালি কমান্ড বোঝা যায় না।")
        }
        return try {
            val normalized: NormalizedCommand = CommandNormalizer.normalize(command)
            val context: List<NormalizedCommand> = recentContext
                .takeLast(IntentParser.MAX_CONTEXT)
                .map { CommandNormalizer.normalize(it) }
            NovaResult.Success(IntentParser.parse(normalized, context))
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Intent analysis failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "কমান্ড বিশ্লেষণে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "RuleBasedBrain"
    }
}
EOF

# ---------- 6. IntentInsightCard.kt ----------
cat > "$BASE/ui/components/IntentInsightCard.kt" <<'EOF'
package com.nova.ai.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.IntentType
import com.nova.ai.core.Language
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.nlp.IntentAction
import com.nova.ai.nlp.IntentEntity
import com.nova.ai.nlp.IntentMode
import com.nova.ai.nlp.IntentPeriod
import com.nova.ai.nlp.IntentSource
import com.nova.ai.nlp.SystemTarget
import com.nova.ai.voice.LanguageDetector

private val NUMBER_PREFIX: Regex = Regex("^\\d+\\.\\s*")

/**
 * Shows what the app understood from the current command: the goal and its details.
 * [history] holds earlier commands of this conversation, oldest first (entries may
 * start with "1. " numbering). Shows nothing when [text] is blank.
 */
@Composable
fun IntentInsightCard(
    text: String,
    history: List<String>,
    modifier: Modifier = Modifier
) {
    if (text.isBlank()) return

    val brain: RuleBasedBrain = remember { RuleBasedBrain() }
    val result: NovaResult<NovaIntent> = remember(text, history) {
        val cleanedHistory: List<String> = history.map { it.replace(NUMBER_PREFIX, "") }
        // The newest history entry can be this very command; do not use it as context.
        val earlier: List<String> =
            if (cleanedHistory.lastOrNull() == text.trim()) cleanedHistory.dropLast(1) else cleanedHistory
        val context: List<VoiceCommand> = earlier.map {
            VoiceCommand(rawText = it, language = Language.UNKNOWN, timestampMs = 0L)
        }
        val current = VoiceCommand(
            rawText = text,
            language = LanguageDetector.detect(text),
            timestampMs = 0L
        )
        brain.analyze(current, context)
    }

    val body: String = when (result) {
        is NovaResult.Failure -> stringResource(R.string.intent_error, result.error.message)
        is NovaResult.Success -> intentLines(result.value).joinToString("\n")
    }

    NovaInfoCard(
        title = stringResource(R.string.intent_title),
        body = body,
        modifier = modifier
    )
}

@Composable
private fun intentLines(intent: NovaIntent): List<String> {
    val lines = ArrayList<String>()
    lines.add(stringResource(typeLabelRes(intent.type)))

    if (intent.type == IntentType.UNKNOWN) {
        lines.add(stringResource(R.string.intent_unknown_hint))
        return lines
    }

    for ((key, value) in intent.entities) {
        lines.add("${entityLabel(key)}: ${valueLabel(key, value)}")
    }
    lines.add(stringResource(R.string.intent_confidence, (intent.confidence * 100).toInt()))
    lines.add(stringResource(R.string.intent_note))
    return lines
}

private fun typeLabelRes(type: IntentType): Int = when (type) {
    IntentType.OPEN_APP -> R.string.intent_type_open_app
    IntentType.SEND_MESSAGE -> R.string.intent_type_send_message
    IntentType.MAKE_CALL -> R.string.intent_type_make_call
    IntentType.WEB_SEARCH -> R.string.intent_type_web_search
    IntentType.SYSTEM_ACTION -> R.string.intent_type_system_action
    IntentType.SET_ALARM -> R.string.intent_type_set_alarm
    IntentType.MEDIA_CONTROL -> R.string.intent_type_media_control
    IntentType.UNKNOWN -> R.string.intent_type_unknown
}

@Composable
private fun entityLabel(key: String): String {
    val res: Int? = when (key) {
        IntentEntity.APP -> R.string.intent_entity_app
        IntentEntity.APP_SOURCE -> R.string.intent_entity_app_source
        IntentEntity.QUERY -> R.string.intent_entity_query
        IntentEntity.CONTACT -> R.string.intent_entity_contact
        IntentEntity.NUMBER -> R.string.intent_entity_number
        IntentEntity.BODY -> R.string.intent_entity_body
        IntentEntity.ACTION -> R.string.intent_entity_action
        IntentEntity.TARGET -> R.string.intent_entity_target
        IntentEntity.VALUE -> R.string.intent_entity_value
        IntentEntity.MODE -> R.string.intent_entity_mode
        IntentEntity.HOUR -> R.string.intent_entity_hour
        IntentEntity.MINUTE -> R.string.intent_entity_minute
        IntentEntity.PERIOD -> R.string.intent_entity_period
        IntentEntity.HOUR24 -> R.string.intent_entity_hour24
        IntentEntity.DURATION_SECONDS -> R.string.intent_entity_duration
        else -> null
    }
    return if (res != null) stringResource(res) else key
}

@Composable
private fun valueLabel(key: String, value: String): String {
    if (key == IntentEntity.DURATION_SECONDS) {
        val seconds: Int? = value.toIntOrNull()
        if (seconds != null) return durationText(seconds)
    }
    val res: Int? = when (key) {
        IntentEntity.ACTION -> when (value) {
            IntentAction.ON -> R.string.intent_value_on
            IntentAction.OFF -> R.string.intent_value_off
            IntentAction.UP -> R.string.intent_value_up
            IntentAction.DOWN -> R.string.intent_value_down
            IntentAction.SET -> R.string.intent_value_set
            IntentAction.MUTE -> R.string.intent_value_mute
            IntentAction.OPEN_SETTINGS -> R.string.intent_value_open_settings
            IntentAction.PLAY -> R.string.intent_value_play
            IntentAction.PAUSE -> R.string.intent_value_pause
            IntentAction.NEXT -> R.string.intent_value_next
            IntentAction.PREVIOUS -> R.string.intent_value_previous
            else -> null
        }
        IntentEntity.TARGET -> when (value) {
            SystemTarget.WIFI -> R.string.intent_value_wifi
            SystemTarget.BLUETOOTH -> R.string.intent_value_bluetooth
            SystemTarget.FLASHLIGHT -> R.string.intent_value_flashlight
            SystemTarget.VOLUME -> R.string.intent_value_volume
            SystemTarget.BRIGHTNESS -> R.string.intent_value_brightness
            else -> null
        }
        IntentEntity.MODE -> when (value) {
            IntentMode.ALARM -> R.string.intent_value_alarm
            IntentMode.TIMER -> R.string.intent_value_timer
            IntentMode.REMINDER -> R.string.intent_value_reminder
            else -> null
        }
        IntentEntity.PERIOD -> when (value) {
            IntentPeriod.AM -> R.string.intent_value_am
            IntentPeriod.PM -> R.string.intent_value_pm
            IntentPeriod.UNKNOWN -> R.string.intent_value_unknown
            else -> null
        }
        IntentEntity.APP_SOURCE -> when (value) {
            IntentSource.CONTEXT -> R.string.intent_value_context
            else -> null
        }
        else -> null
    }
    return if (res != null) stringResource(res) else value
}

@Composable
private fun durationText(seconds: Int): String = when {
    seconds % 3600 == 0 -> stringResource(R.string.intent_duration_hours, seconds / 3600)
    seconds % 60 == 0 -> stringResource(R.string.intent_duration_minutes, seconds / 60)
    else -> stringResource(R.string.intent_duration_seconds, seconds)
}
EOF

# ---------- B. HomeScreen.kt: two additive lines (idempotent) ----------
if ! grep -q "IntentInsightCard" "$HOME_FILE"; then
  grep -q '^import com.nova.ai.ui.components.CommandInsightCard$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen import anchor not found" >&2; exit 1; }
  grep -q '^        CommandInsightCard(text = commandText)$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen layout anchor not found" >&2; exit 1; }

  sed -i '/^import com.nova.ai.ui.components.CommandInsightCard$/a import com.nova.ai.ui.components.IntentInsightCard' "$HOME_FILE"
  sed -i '/^        CommandInsightCard(text = commandText)$/a\        IntentInsightCard(text = commandText, history = transcript.toList())' "$HOME_FILE"
fi
grep -q "IntentInsightCard(text = commandText" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed" >&2; exit 1; }

# ---------- Commit and push ----------
git add -A
git commit -m "P11: rule-based command understanding (intent parser)"
git push

echo "P11 files created and pushed."
