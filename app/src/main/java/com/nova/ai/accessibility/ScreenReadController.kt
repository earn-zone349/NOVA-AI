package com.nova.ai.accessibility

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.R
import com.nova.ai.core.Language
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.logging.NovaLogger
import com.nova.ai.voice.LanguageDetector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What the screen-reading card shows. */
sealed interface ScreenReadState {
    /** Nothing happening. */
    object Idle : ScreenReadState

    /** Counting down so the user can switch to the app to be read. */
    data class Waiting(val secondsLeft: Int) : ScreenReadState

    /** The screen was read. [speakError] is set if speaking it aloud failed. */
    data class Done(
        val report: ScreenReport,
        val truncated: Boolean,
        val speakError: String?
    ) : ScreenReadState

    /** Reading failed for the reason in [message]. */
    data class Failed(val message: String) : ScreenReadState
}

/**
 * Reads the screen in front and speaks it. Use from the main thread; the heavy
 * work runs on a background dispatcher. Screen content is only held in [state]
 * while the card is open and is never logged or stored.
 *
 * [speak] and [stopSpeaking] are given by the screen (its voice engine), so this
 * class has no dependency on how speech is produced.
 */
class ScreenReadController(
    context: Context,
    private val scope: CoroutineScope,
    private val defaultLanguage: () -> Language,
    private val speak: (String, Language) -> NovaResult<Unit>,
    private val stopSpeaking: () -> Unit
) {

    private val appContext: Context = context.applicationContext
    private var job: Job? = null

    /** What the card should show right now. */
    var state: ScreenReadState by mutableStateOf<ScreenReadState>(ScreenReadState.Idle)
        private set

    /** Waits a few seconds (so the user can open another app), then reads the screen. */
    fun readAfterDelay() {
        job?.cancel()
        job = scope.launch {
            for (secondsLeft in DELAY_SECONDS downTo 1) {
                state = ScreenReadState.Waiting(secondsLeft)
                delay(ONE_SECOND_MS)
            }
            captureAndSpeak()
        }
    }

    /** Reads the screen that is in front at this moment. */
    fun readNow() {
        job?.cancel()
        job = scope.launch { captureAndSpeak() }
    }

    /** Cancels a countdown, stops speaking and clears the card. */
    fun stop() {
        job?.cancel()
        job = null
        stopSpeaking()
        state = ScreenReadState.Idle
    }

    private suspend fun captureAndSpeak() {
        val result: NovaResult<ScreenSnapshot> = withContext(Dispatchers.Default) {
            ScreenReader.capture()
        }
        when (result) {
            is NovaResult.Failure -> state = ScreenReadState.Failed(result.error.message)
            is NovaResult.Success -> present(ScreenSummarizer.summarize(result.value))
        }
    }

    private fun present(report: ScreenReport) {
        if (report.isEmpty) {
            state = ScreenReadState.Failed(appContext.getString(R.string.scr_empty))
            return
        }
        // Only counts are logged, never the content.
        NovaLogger.i(
            TAG,
            "Screen read: texts=${report.texts.size} buttons=${report.buttons.size} " +
                "fields=${report.fields.size + report.unnamedFields}"
        )

        // Speak the texts; if the screen has none, speak its buttons instead.
        val readTexts: Boolean = report.texts.isNotEmpty()
        val parts: List<String> = if (readTexts) report.texts else report.buttons
        if (parts.isEmpty()) {
            state = ScreenReadState.Done(report, truncated = false, speakError = null)
            return
        }

        val detected: Language = LanguageDetector.detect(parts.joinToString(" "))
        val language: Language = if (detected == Language.UNKNOWN) defaultLanguage() else detected
        val speech: SpeechText = ScreenSummarizer.toSpeech(parts)
        val spoken: String = introFor(language, readTexts) + " " + speech.text

        val spoke: NovaResult<Unit> = speak(spoken, language)
        val speakError: String? = (spoke as? NovaResult.Failure)?.error?.message
        state = ScreenReadState.Done(report, speech.truncated, speakError)
    }

    private fun introFor(language: Language, readTexts: Boolean): String {
        val english: Boolean = language == Language.ENGLISH
        val resId: Int = when {
            readTexts && english -> R.string.scr_intro_texts_en
            readTexts -> R.string.scr_intro_texts_bn
            english -> R.string.scr_intro_buttons_en
            else -> R.string.scr_intro_buttons_bn
        }
        return appContext.getString(resId)
    }

    private companion object {
        const val TAG: String = "ScreenReadController"
        const val DELAY_SECONDS: Int = 5
        const val ONE_SECOND_MS: Long = 1_000L
    }
}
