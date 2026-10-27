package com.nova.ai.media

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.R
import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.security.EmergencyStop
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.nlp.IntentAction
import com.nova.ai.nlp.IntentEntity
import com.nova.ai.nlp.IntentMode
import com.nova.ai.system.OutcomeKind
import com.nova.ai.system.SystemActionOutcome
import com.nova.ai.voice.LanguageDetector

/**
 * Carries out music control, searches, navigation and camera commands.
 * Home gives it every command; it acts only on the ones it understands and
 * keeps the last [state] for the screen to show. Use from the main thread.
 */
class MediaCommandController(context: Context) {

    private val appContext: Context = context.applicationContext
    private val keys = MediaKeyController(appContext)
    private val quick = QuickActions(appContext)
    private val brain = RuleBasedBrain()

    /** The last result, or null when there is nothing to show. */
    var state: SystemActionOutcome? by mutableStateOf<SystemActionOutcome?>(null)
        private set

    /** Looks at [text]; if it is a music, search, navigation or camera command, carries it out. */
    fun handleCommand(text: String) {
        if (EmergencyStop.isActive) return
        val intent: NovaIntent? = analyze(text)
        if (intent == null) {
            state = null
            return
        }
        state = when (intent.type) {
            IntentType.MEDIA_CONTROL -> media(intent)
            IntentType.WEB_SEARCH -> search(intent)
            IntentType.NAVIGATE -> navigate(intent)
            IntentType.CAPTURE_MEDIA -> capture(intent)
            else -> null
        }
    }

    /** Hides the result card. */
    fun dismiss() {
        state = null
    }

    // ---------------------------------------------------------------- music

    private fun media(intent: NovaIntent): SystemActionOutcome {
        val query: String? = cleanQuery(intent.entities[IntentEntity.QUERY])
        val app: String? = intent.entities[IntentEntity.APP]
        return when (intent.entities[IntentEntity.ACTION]) {
            IntentAction.PAUSE -> pressKey(MediaKeyController.Key.PAUSE, R.string.media_paused)
            IntentAction.NEXT -> pressKey(MediaKeyController.Key.NEXT, R.string.media_next)
            IntentAction.PREVIOUS -> pressKey(MediaKeyController.Key.PREVIOUS, R.string.media_previous)
            IntentAction.PLAY -> play(query, app)
            else -> hint(text(R.string.media_unknown))
        }
    }

    private fun pressKey(key: MediaKeyController.Key, @StringRes doneMessage: Int): SystemActionOutcome {
        if (!keys.isMediaPlaying()) return hint(text(R.string.media_nothing_playing))
        return when (val result: NovaResult<Unit> = keys.send(key)) {
            is NovaResult.Success -> done(text(doneMessage))
            is NovaResult.Failure -> failed(result.error.message)
        }
    }

    private fun play(query: String?, app: String?): SystemActionOutcome {
        if (query == null) {
            return when (val result: NovaResult<Unit> = keys.send(MediaKeyController.Key.PLAY)) {
                is NovaResult.Success -> done(text(R.string.media_resume))
                is NovaResult.Failure -> failed(result.error.message)
            }
        }
        val onYoutube: Boolean = app == APP_YOUTUBE
        val result: NovaResult<Unit> =
            if (onYoutube) quick.youtubeSearch(query) else quick.playFromSearch(query)
        return outcomeOf(
            result,
            if (onYoutube) text(R.string.media_youtube_search, query) else text(R.string.media_play_query, query)
        )
    }

    // ---------------------------------------------------------------- search

    private fun search(intent: NovaIntent): SystemActionOutcome {
        val query: String = cleanQuery(intent.entities[IntentEntity.QUERY])
            ?: return hint(text(R.string.media_need_query))
        val app: String? = intent.entities[IntentEntity.APP]

        return when (app) {
            null, APP_CHROME, APP_GOOGLE ->
                outcomeOf(
                    quick.webSearch(query, preferChrome = app == APP_CHROME),
                    text(R.string.media_web_search, query)
                )
            APP_YOUTUBE ->
                outcomeOf(quick.youtubeSearch(query), text(R.string.media_youtube_search, query))
            APP_MAPS ->
                outcomeOf(quick.mapsSearch(query), text(R.string.media_maps_search, query))
            APP_PLAY_STORE ->
                outcomeOf(quick.playStoreSearch(query), text(R.string.media_play_store_search, query))
            else -> hint(text(R.string.media_app_search_later))
        }
    }

    // ---------------------------------------------------------------- navigation and camera

    private fun navigate(intent: NovaIntent): SystemActionOutcome {
        val destination: String = cleanQuery(intent.entities[IntentEntity.QUERY])
            ?: return hint(text(R.string.media_need_destination))
        return outcomeOf(quick.navigate(destination), text(R.string.media_navigate, destination))
    }

    private fun capture(intent: NovaIntent): SystemActionOutcome {
        val video: Boolean = intent.entities[IntentEntity.MODE] == IntentMode.VIDEO
        return when (val result: NovaResult<Unit> = quick.openCamera(video)) {
            is NovaResult.Success -> SystemActionOutcome(
                OutcomeKind.GUIDED,
                text(if (video) R.string.media_camera_video else R.string.media_camera_photo)
            )
            is NovaResult.Failure -> failed(result.error.message)
        }
    }

    // ---------------------------------------------------------------- helpers

    private fun outcomeOf(result: NovaResult<Unit>, successMessage: String): SystemActionOutcome =
        when (result) {
            is NovaResult.Success -> done(successMessage)
            is NovaResult.Failure -> failed(result.error.message)
        }

    private fun cleanQuery(raw: String?): String? = raw?.trim()?.takeIf { it.isNotEmpty() }

    private fun analyze(text: String): NovaIntent? {
        if (text.isBlank()) return null
        val command = VoiceCommand(
            rawText = text,
            language = LanguageDetector.detect(text),
            timestampMs = System.currentTimeMillis()
        )
        return (brain.analyze(command, emptyList()) as? NovaResult.Success)?.value
    }

    private fun text(@StringRes id: Int, vararg args: Any): String = appContext.getString(id, *args)

    private fun done(message: String) = SystemActionOutcome(OutcomeKind.DONE, message)
    private fun hint(message: String) = SystemActionOutcome(OutcomeKind.HINT, message)
    private fun failed(message: String) = SystemActionOutcome(OutcomeKind.FAILED, message)

    private companion object {
        const val APP_CHROME: String = "Chrome"
        const val APP_GOOGLE: String = "Google"
        const val APP_YOUTUBE: String = "YouTube"
        const val APP_MAPS: String = "Maps"
        const val APP_PLAY_STORE: String = "Play Store"
    }
}
