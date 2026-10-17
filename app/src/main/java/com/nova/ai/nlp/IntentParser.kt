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
            ?: ExtraCommandParser.parse(view)
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
        // nova-open-phone-guard: an "open" word without a number means opening the phone app.
        if (v.hasAny(IntentVocabulary.OPEN_VERBS_STRONG) && findPhoneNumber(v) == null) return null

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
