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
    IntentType.NAVIGATE -> R.string.intent_type_navigate
    IntentType.CAPTURE_MEDIA -> R.string.intent_type_capture
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
            SystemTarget.MOBILE_DATA -> R.string.intent_value_mobile_data
            else -> null
        }
        IntentEntity.MODE -> when (value) {
            IntentMode.ALARM -> R.string.intent_value_alarm
            IntentMode.TIMER -> R.string.intent_value_timer
            IntentMode.REMINDER -> R.string.intent_value_reminder
            IntentMode.PHOTO -> R.string.intent_value_photo
            IntentMode.VIDEO -> R.string.intent_value_video
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
