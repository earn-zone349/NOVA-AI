package com.nova.ai.voice

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.Language
import com.nova.ai.core.NovaError
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import java.util.Locale

/**
 * Speaks text aloud with Android's built-in text-to-speech.
 * The engine starts on the first [speak] call. A request made while the engine
 * is still starting is kept and played as soon as it is ready.
 * Problems that happen later (after [speak] already returned) are sent to
 * the problem listener on the main thread.
 */
class TtsSpeaker(context: Context) {

    private enum class SpeakerState { NOT_STARTED, INITIALIZING, READY, FAILED }

    private data class SpeakRequest(val text: String, val locale: Locale, val rate: Float)

    private val appContext: Context = context.applicationContext
    private val lock: Any = Any()
    private val mainHandler: Handler = Handler(Looper.getMainLooper())

    private var engine: TextToSpeech? = null
    private var state: SpeakerState = SpeakerState.NOT_STARTED
    private var pendingRequest: SpeakRequest? = null
    private var utteranceCounter: Long = 0L

    @Volatile
    private var problemListener: ((NovaError) -> Unit)? = null

    /** Sets (or clears with null) the listener for problems found after [speak] returned. */
    fun setProblemListener(listener: ((NovaError) -> Unit)?) {
        problemListener = listener
    }

    /** Speaks [text] in [language] at [rate] (1.0 is normal speed). */
    fun speak(text: String, language: Language, rate: Float): NovaResult<Unit> {
        val cleaned: String = text.trim()
        if (cleaned.isEmpty()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, "বলার মতো কোনো লেখা নেই।")
        }
        val request = SpeakRequest(
            text = cleaned.take(MAX_TEXT_LENGTH),
            locale = localeFor(language),
            rate = rate.coerceIn(MIN_RATE, MAX_RATE)
        )

        synchronized(lock) {
            return when (state) {
                SpeakerState.READY -> {
                    val readyEngine: TextToSpeech? = engine
                    if (readyEngine == null) {
                        NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_ENGINE_MISSING)
                    } else {
                        playLocked(readyEngine, request)
                    }
                }
                SpeakerState.INITIALIZING -> {
                    pendingRequest = request
                    NovaResult.Success(Unit)
                }
                SpeakerState.NOT_STARTED, SpeakerState.FAILED -> {
                    pendingRequest = request
                    startEngineLocked()
                }
            }
        }
    }

    /** Stops the current speech and drops any waiting request. */
    fun stop() {
        synchronized(lock) {
            pendingRequest = null
            try {
                engine?.stop()
            } catch (e: Exception) {
                NovaLogger.e(TAG, "Failed to stop speech", e)
            }
        }
    }

    /** True while speech is playing. */
    fun isSpeaking(): Boolean = synchronized(lock) {
        try {
            engine?.isSpeaking == true
        } catch (e: Exception) {
            false
        }
    }

    /** Releases the speech engine. A later [speak] starts it again. */
    fun shutdown() {
        synchronized(lock) {
            pendingRequest = null
            try {
                engine?.stop()
                engine?.shutdown()
            } catch (e: Exception) {
                NovaLogger.e(TAG, "Failed to shut down speech engine", e)
            } finally {
                engine = null
                state = SpeakerState.NOT_STARTED
            }
        }
    }

    // Must be called while holding [lock].
    private fun startEngineLocked(): NovaResult<Unit> {
        state = SpeakerState.INITIALIZING
        return try {
            engine = TextToSpeech(appContext) { status: Int -> handleInit(status) }
            NovaResult.Success(Unit)
        } catch (e: Exception) {
            state = SpeakerState.FAILED
            engine = null
            pendingRequest = null
            NovaLogger.e(TAG, "Failed to create TextToSpeech", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "ভয়েস আউটপুট চালু করা যায়নি।", e)
        }
    }

    private fun handleInit(status: Int) {
        synchronized(lock) {
            val created: TextToSpeech? = engine
            if (status != TextToSpeech.SUCCESS || created == null) {
                state = SpeakerState.FAILED
                pendingRequest = null
                try {
                    created?.shutdown()
                } catch (e: Exception) {
                    NovaLogger.e(TAG, "Failed to clean up after init failure", e)
                }
                engine = null
                val error = NovaError(ErrorCode.NOT_AVAILABLE, MSG_ENGINE_MISSING)
                NovaLogger.w(TAG, "TextToSpeech init failed (status=$status)")
                reportProblem(error)
                return
            }

            created.setOnUtteranceProgressListener(progressListener)
            state = SpeakerState.READY
            val request: SpeakRequest? = pendingRequest
            pendingRequest = null
            if (request != null) {
                val result: NovaResult<Unit> = playLocked(created, request)
                if (result is NovaResult.Failure) reportProblem(result.error)
            }
        }
    }

    // Must be called while holding [lock].
    private fun playLocked(readyEngine: TextToSpeech, request: SpeakRequest): NovaResult<Unit> {
        return try {
            val availability: Int = readyEngine.setLanguage(request.locale)
            if (availability == TextToSpeech.LANG_MISSING_DATA ||
                availability == TextToSpeech.LANG_NOT_SUPPORTED
            ) {
                NovaLogger.w(TAG, "Voice language unavailable: ${request.locale}")
                return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_LANGUAGE_MISSING)
            }
            readyEngine.setSpeechRate(request.rate)
            utteranceCounter += 1L
            val outcome: Int = readyEngine.speak(
                request.text,
                TextToSpeech.QUEUE_FLUSH,
                null,
                "$UTTERANCE_PREFIX$utteranceCounter"
            )
            if (outcome == TextToSpeech.ERROR) {
                NovaResult.failure(ErrorCode.EXECUTION_FAILED, "কথা বলতে সমস্যা হয়েছে।")
            } else {
                NovaResult.Success(Unit)
            }
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Speak failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "কথা বলতে সমস্যা হয়েছে।", e)
        }
    }

    private fun reportProblem(error: NovaError) {
        val listener: ((NovaError) -> Unit)? = problemListener
        if (listener == null) return
        mainHandler.post {
            try {
                listener(error)
            } catch (e: Exception) {
                NovaLogger.e(TAG, "Problem listener threw an exception", e)
            }
        }
    }

    private val progressListener: UtteranceProgressListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) = Unit

        override fun onDone(utteranceId: String?) = Unit

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String?) {
            handleUtteranceError(-1)
        }

        override fun onError(utteranceId: String?, errorCode: Int) {
            handleUtteranceError(errorCode)
        }
    }

    private fun handleUtteranceError(errorCode: Int) {
        NovaLogger.w(TAG, "Utterance error (code=$errorCode)")
        reportProblem(NovaError(ErrorCode.EXECUTION_FAILED, "কথা বলতে সমস্যা হয়েছে।"))
    }

    private fun localeFor(language: Language): Locale = when (language) {
        Language.ENGLISH -> Locale.US
        Language.BANGLA, Language.MIXED, Language.UNKNOWN ->
            Locale.Builder().setLanguage("bn").setRegion("BD").build()
    }

    private companion object {
        const val TAG: String = "TtsSpeaker"
        const val UTTERANCE_PREFIX: String = "nova-"
        const val MAX_TEXT_LENGTH: Int = 1500
        const val MIN_RATE: Float = 0.5f
        const val MAX_RATE: Float = 2.0f
        const val MSG_ENGINE_MISSING: String =
            "ফোনে Text-to-speech সার্ভিস চালু নেই। Settings থেকে Google Text-to-speech চালু করো।"
        const val MSG_LANGUAGE_MISSING: String =
            "এই ভাষার ভয়েস ফোনে নেই। Settings > Text-to-speech থেকে ভাষা ইনস্টল করো।"
    }
}
