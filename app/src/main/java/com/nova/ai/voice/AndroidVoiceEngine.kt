package com.nova.ai.voice

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.content.ContextCompat
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.Language
import com.nova.ai.core.NovaError
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.settings.AppLanguage

/**
 * Voice input using Android's built-in speech recognizer.
 * Voice output (speaking) is added in Phase 7.
 *
 * Must be used from the main thread (a SpeechRecognizer requirement).
 * [languageProvider] is read each time listening starts, so a language
 * change in settings takes effect immediately.
 */
class AndroidVoiceEngine(
    context: Context,
    private val languageProvider: () -> AppLanguage
) : VoiceEngine {

    private val appContext: Context = context.applicationContext
    private var recognizer: SpeechRecognizer? = null

    @Volatile
    private var listening: Boolean = false

    override fun startListening(listener: VoiceListener): NovaResult<Unit> {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, "ভয়েস শুরু করতে হবে মূল থ্রেড থেকে।")
        }
        if (!SpeechRecognizer.isRecognitionAvailable(appContext)) {
            return NovaResult.failure(
                ErrorCode.NOT_AVAILABLE,
                "ফোনে ভয়েস চেনার সার্ভিস (Google) পাওয়া যায়নি।"
            )
        }
        val micGranted: Boolean = ContextCompat.checkSelfPermission(
            appContext, Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        if (!micGranted) {
            return NovaResult.failure(ErrorCode.PERMISSION_DENIED, "মাইক্রোফোনের অনুমতি নেই।")
        }

        return try {
            releaseRecognizer()
            val language: AppLanguage = languageProvider()
            val created: SpeechRecognizer = SpeechRecognizer.createSpeechRecognizer(appContext)
            created.setRecognitionListener(RecognitionHandler(listener))
            created.startListening(buildRecognizerIntent(language))
            recognizer = created
            listening = true
            NovaLogger.i(TAG, "Listening started (language=$language)")
            NovaResult.Success(Unit)
        } catch (e: Exception) {
            listening = false
            releaseRecognizer()
            NovaLogger.e(TAG, "Failed to start listening", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "ভয়েস চালু করা যায়নি।", e)
        }
    }

    override fun stopListening() {
        try {
            recognizer?.stopListening()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to stop listening", e)
            listening = false
        }
    }

    override fun speak(text: String, language: Language): NovaResult<Unit> =
        NovaResult.failure(ErrorCode.NOT_AVAILABLE, "ভয়েস আউটপুট P7-এ যোগ হবে।")

    override fun isListening(): Boolean = listening

    override fun shutdown() {
        listening = false
        releaseRecognizer()
    }

    private fun releaseRecognizer() {
        try {
            recognizer?.destroy()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to release recognizer", e)
        } finally {
            recognizer = null
        }
    }

    private fun buildRecognizerIntent(language: AppLanguage): Intent {
        val languageTag: String = when (language) {
            AppLanguage.ENGLISH -> TAG_ENGLISH
            AppLanguage.BANGLA, AppLanguage.MIXED -> TAG_BANGLA
        }
        return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, appContext.packageName)
            if (language == AppLanguage.MIXED) {
                putExtra(RecognizerIntent.EXTRA_ADDITIONAL_LANGUAGES, arrayOf(TAG_ENGLISH))
            }
        }
    }

    /** Receives recognizer callbacks and forwards them to the app's [VoiceListener]. */
    private inner class RecognitionHandler(
        private val listener: VoiceListener
    ) : RecognitionListener {

        override fun onReadyForSpeech(params: Bundle?) {
            safely { listener.onListeningStarted() }
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val text: String? = firstResult(partialResults)
            if (!text.isNullOrBlank()) {
                safely { listener.onPartialText(text) }
            }
        }

        override fun onResults(results: Bundle?) {
            listening = false
            val text: String? = firstResult(results)
            if (text.isNullOrBlank()) {
                safely {
                    listener.onError(
                        SpeechErrorMapper.toNovaError(SpeechRecognizer.ERROR_NO_MATCH)
                    )
                }
                return
            }
            val command = VoiceCommand(
                rawText = text,
                language = LanguageDetector.detect(text),
                timestampMs = System.currentTimeMillis()
            )
            NovaLogger.i(TAG, "Command received (${command.language}, ${text.length} chars)")
            safely { listener.onFinalCommand(command) }
        }

        override fun onError(error: Int) {
            listening = false
            val novaError: NovaError = SpeechErrorMapper.toNovaError(error)
            NovaLogger.w(TAG, "Recognizer error $error: ${novaError.message}")
            safely { listener.onError(novaError) }
        }

        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit

        private fun firstResult(bundle: Bundle?): String? =
            bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?.trim()

        /** A failing listener must never crash the recognizer callback. */
        private fun safely(block: () -> Unit) {
            try {
                block()
            } catch (e: Exception) {
                NovaLogger.e(TAG, "Voice listener threw an exception", e)
            }
        }
    }

    private companion object {
        const val TAG: String = "AndroidVoiceEngine"
        const val TAG_BANGLA: String = "bn-BD"
        const val TAG_ENGLISH: String = "en-US"
    }
}
