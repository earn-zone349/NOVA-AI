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
 *
 * The optional `onFinished` callback runs on the main thread when the speech
 * ends or fails later. It is dropped if the speech is stopped, replaced by a
 * newer request, or the speaker is shut down.
 */
class TtsSpeaker(context: Context) {

    private enum class SpeakerState { NOT_STARTED, INITIALIZING, READY, FAILED }

    private data class SpeakRequest(
        val text: String,
        val locale: Locale,
        val rate: Float,
        val onFinished: (() -> Unit)?
    )

    private val appContext: Context = context.applicationContext
    private val lock: Any = Any()
    private val mainHandler: Handler = Handler(Looper.getMainLooper())

    private var engine: TextToSpeech? = null
    private var state: SpeakerState = SpeakerState.NOT_STARTED
    private var pendingRequest: SpeakRequest? = null
    private var utteranceCounter: Long = 0L
    private var activeUtteranceId: String? = null
    private var activeFinished: (() -> Unit)? = null

    @Volatile
    private var problemListener: ((NovaError) -> Unit)? = null

    /** Sets (or clears with null) the listener for problems found after [speak] returned. */
    fun setProblemListener(listener: ((NovaError) -> Unit)?) {
        problemListener = listener
    }

    /** Speaks [text] in [language] at [rate] (1.0 is normal speed). */
    fun speak(
        text: String,
        language: Language,
        rate: Float,
        onFinished: (() -> Unit)? = null
    ): NovaResult<Unit> {
        val cleaned: String = text.trim()
        if (cleaned.isEmpty()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, "বলার মতো কোনো লেখা নেই।")
        }
        val request = SpeakRequest(
            text = cleaned.take(MAX_TEXT_LENGTH),
            locale = localeFor(language),
            rate = rate.coerceIn(MIN_RATE, MAX_RATE),
            onFinished = onFinished
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

    /** Stops the current speech and drops any waiting request and callback. */
    fun stop() {
        synchronized(lock) {
            pendingRequest = null
            clearActiveLocked()
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
            clearActiveLocked()
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
    private fun clearActiveLocked() {
        activeUtteranceId = null
        activeFinished = null
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
            val waiting: SpeakRequest? = pendingRequest
            pendingRequest = null

            if (status != TextToSpeech.SUCCESS || created == null) {
                state = SpeakerState.FAILED
                try {
                    created?.shutdown()
                } catch (e: Exception) {
                    NovaLogger.e(TAG, "Failed to clean up after init failure", e)
                }
                engine = null
                NovaLogger.w(TAG, "TextToSpeech init failed (status=$status)")
                reportProblem(NovaError(ErrorCode.NOT_AVAILABLE, MSG_ENGINE_MISSING))
                waiting?.onFinished?.let { postFinished(it) }
                return
            }

            created.setOnUtteranceProgressListener(progressListener)
            state = SpeakerState.READY
            if (waiting != null) {
                val result: NovaResult<Unit> = playLocked(created, waiting)
                if (result is NovaResult.Failure) {
                    reportProblem(result.error)
                    waiting.onFinished?.let { postFinished(it) }
                }
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
            val utteranceId = "$UTTERANCE_PREFIX$utteranceCounter"
            activeUtteranceId = utteranceId
            activeFinished = request.onFinished
            val outcome: Int = readyEngine.speak(
                request.text,
                TextToSpeech.QUEUE_FLUSH,
                null,
                utteranceId
            )
            if (outcome == TextToSpeech.ERROR) {
                clearActiveLocked()
                NovaResult.failure(ErrorCode.EXECUTION_FAILED, "কথা বলতে সমস্যা হয়েছে।")
            } else {
                NovaResult.Success(Unit)
            }
        } catch (e: Exception) {
            clearActiveLocked()
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

    private fun postFinished(callback: () -> Unit) {
        mainHandler.post {
            try {
                callback()
            } catch (e: Exception) {
                NovaLogger.e(TAG, "Finished callback threw an exception", e)
            }
        }
    }

    /** Runs the finished callback if [utteranceId] is the utterance we are waiting for. */
    private fun finishUtterance(utteranceId: String?) {
        var callback: (() -> Unit)? = null
        synchronized(lock) {
            if (utteranceId != null && utteranceId == activeUtteranceId) {
                callback = activeFinished
                clearActiveLocked()
            }
        }
        callback?.let { postFinished(it) }
    }

    /** Forgets the waiting callback without running it (speech was stopped on purpose). */
    private fun dropActive(utteranceId: String?) {
        synchronized(lock) {
            if (utteranceId != null && utteranceId == activeUtteranceId) {
                clearActiveLocked()
            }
        }
    }

    private val progressListener: UtteranceProgressListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) = Unit

        override fun onDone(utteranceId: String?) {
            finishUtterance(utteranceId)
        }

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String?) {
            handleUtteranceError(utteranceId, -1)
        }

        override fun onError(utteranceId: String?, errorCode: Int) {
            handleUtteranceError(utteranceId, errorCode)
        }

        override fun onStop(utteranceId: String?, interrupted: Boolean) {
            dropActive(utteranceId)
        }
    }

    private fun handleUtteranceError(utteranceId: String?, errorCode: Int) {
        NovaLogger.w(TAG, "Utterance error (code=$errorCode)")
        reportProblem(NovaError(ErrorCode.EXECUTION_FAILED, "কথা বলতে সমস্যা হয়েছে।"))
        finishUtterance(utteranceId)
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
