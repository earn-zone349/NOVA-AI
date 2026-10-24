package com.nova.ai.accessibility

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.R
import com.nova.ai.core.Language
import com.nova.ai.core.NovaResult
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
        val appPackage: String?,
        val nodeCount: Int,
        val durationMs: Long,
        val screenTruncated: Boolean,
        val hiddenSensitive: Int,
        val summary: ScreenSummary,
        val speechTruncated: Boolean,
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
        val result: NovaResult<ScreenCapture> = withContext(Dispatchers.Default) {
            ScreenReader.capture()
        }
        if (result is NovaResult.Success) {
            present(result.value)
        } else if (result is NovaResult.Failure) {
            state = ScreenReadState.Failed(
                result.error.message ?: appContext.getString(R.string.scr_failed)
            )
        }
    }

    private fun present(capture: ScreenCapture) {
        val summary: ScreenSummary = ScreenSummarizer.summarize(capture)
        if (summary.isEmpty) {
            state = ScreenReadState.Failed(appContext.getString(R.string.scr_empty))
            return
        }
        // Only counts are logged, never the content.
        NovaLogger.i(
            TAG,
            "Screen read: texts=${summary.texts.size} buttons=${summary.actions.size} " +
                "fields=${summary.fields.size + summary.unnamedFields} hidden=${capture.hiddenSensitiveCount}"
        )

        // Speak the texts; if the screen has none, speak its buttons instead.
        val readTexts: Boolean = summary.texts.isNotEmpty()
        val rawParts: List<String> = if (readTexts) summary.texts else summary.actions

        fun done(speechTruncated: Boolean, speakError: String?): ScreenReadState.Done =
            ScreenReadState.Done(
                appPackage = capture.packageName,
                nodeCount = capture.nodes.size,
                durationMs = capture.durationMs,
                screenTruncated = capture.truncated,
                hiddenSensitive = capture.hiddenSensitiveCount,
                summary = summary,
                speechTruncated = speechTruncated,
                speakError = speakError
            )

        if (rawParts.isEmpty()) {
            state = done(speechTruncated = false, speakError = null)
            return
        }

        val detected: Language = LanguageDetector.detect(rawParts.joinToString(" "))
        val language: Language = if (detected == Language.UNKNOWN) defaultLanguage() else detected
        val english: Boolean = language == Language.ENGLISH

        // A hidden code is spoken as a word instead of the mask symbols.
        val hiddenWord: String = appContext.getString(
            if (english) R.string.scr_speech_hidden_en else R.string.scr_speech_hidden_bn
        )
        val parts: List<String> = rawParts.map { it.replace(SensitiveNodePolicy.MASK, hiddenWord) }

        val speech: SpeechText = ScreenSummarizer.toSpeech(parts)
        val spoken: String = introFor(english, readTexts) + " " + speech.text

        val spoke: NovaResult<Unit> = speak(spoken, language)
        val speakError: String? = if (spoke is NovaResult.Failure) spoke.error.message else null
        state = done(speech.truncated, speakError)
    }

    private fun introFor(english: Boolean, readTexts: Boolean): String {
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
