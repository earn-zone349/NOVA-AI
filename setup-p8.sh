#!/usr/bin/env bash
# NOVA AI - Phase 8 setup script: continuous conversation.
# Additive: previous behavior is kept in every rewritten file.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"

if [ ! -f "$BASE/voice/TtsSpeaker.kt" ] || [ ! -f "$BASE/settings/SettingsRepository.kt" ]; then
  echo "ERROR: Run from repo root after P1 to P7 are installed." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"

# ---------- A. SettingsRepository: add continuous-conversation setting (additive) ----------
REPO_FILE="$BASE/settings/SettingsRepository.kt"
if ! grep -q "KEY_CONTINUOUS_CONVERSATION" "$REPO_FILE"; then
  cat > "$TMP_DIR/repo_funcs.txt" <<'EOF'

    fun isContinuousConversationEnabled(): Boolean =
        readBoolean(KEY_CONTINUOUS_CONVERSATION, true)

    fun setContinuousConversationEnabled(enabled: Boolean) =
        writeBoolean(KEY_CONTINUOUS_CONVERSATION, enabled)
EOF
  cat > "$TMP_DIR/repo_const.txt" <<'EOF'
        const val KEY_CONTINUOUS_CONVERSATION: String = "continuous_conversation"
EOF
  sed -i "/fun setVoiceReplyEnabled/r $TMP_DIR/repo_funcs.txt" "$REPO_FILE"
  sed -i "/const val KEY_VOICE_REPLY/r $TMP_DIR/repo_const.txt" "$REPO_FILE"
fi
grep -q "fun isContinuousConversationEnabled" "$REPO_FILE" || { echo "ERROR: settings edit failed (functions)" >&2; exit 1; }
grep -q 'const val KEY_CONTINUOUS_CONVERSATION' "$REPO_FILE" || { echo "ERROR: settings edit failed (key)" >&2; exit 1; }

# ---------- B. New strings file ----------
cat > app/src/main/res/values/strings_p8.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="home_status_speaking">বলছি...</string>
    <string name="home_status_next_turn">পরের কথার জন্য প্রস্তুত হচ্ছি...</string>
    <string name="home_status_listening_count">শুনছি... এখন বলো। (এ পর্যন্ত %1$d টি কমান্ড)</string>
    <string name="home_status_ended_user">কথোপকথন বন্ধ করেছো।</string>
    <string name="home_status_ended_phrase">ঠিক আছে, কথোপকথন বন্ধ করলাম।</string>
    <string name="home_status_ended_silence">অনেকক্ষণ কিছু শোনা যায়নি, তাই কথোপকথন বন্ধ হয়েছে। আবার মাইক চাপো।</string>
    <string name="home_voice_stop_ack">ঠিক আছে, বন্ধ করছি।</string>
    <string name="home_voice_stop_ack_en">Okay, stopping.</string>
    <string name="home_continuous_label">ধারাবাহিক কথোপকথন</string>
    <string name="home_continuous_hint">চালু থাকলে প্রতিবার মাইক চাপতে হবে না। থামো বা stop বললে বন্ধ হবে।</string>
    <string name="home_transcript_title">এই কথোপকথনের কমান্ড</string>
</resources>
EOF

# ---------- 1. VoiceEngine.kt (all previous members kept; speakThen added) ----------
cat > "$BASE/voice/VoiceEngine.kt" <<'EOF'
package com.nova.ai.voice

import com.nova.ai.core.Language
import com.nova.ai.core.NovaError
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand

/** Receives events from the [VoiceEngine]. */
interface VoiceListener {
    fun onListeningStarted()
    fun onPartialText(text: String)
    fun onFinalCommand(command: VoiceCommand)
    fun onError(error: NovaError)
}

/** Voice input (speech to text) and output (text to speech). */
interface VoiceEngine {
    /** Starts listening; results arrive through [listener]. */
    fun startListening(listener: VoiceListener): NovaResult<Unit>

    /** Stops listening immediately. */
    fun stopListening()

    /** Speaks [text] aloud in the given [language]. */
    fun speak(text: String, language: Language): NovaResult<Unit>

    /** True while the microphone is active. */
    fun isListening(): Boolean

    /** Releases microphone and speech resources. */
    fun shutdown()

    /** Stops any speech that is currently playing. */
    fun stopSpeaking() {}

    /** True while the app is speaking. */
    fun isSpeaking(): Boolean = false

    /**
     * Speaks [text] and calls [onFinished] on the main thread when the speech ends
     * (finished, or failed later). If this call returns a failure, [onFinished] is NOT
     * called. If the speech is stopped on purpose, [onFinished] is NOT called either.
     * Default implementation has no completion tracking: it calls [onFinished] at once.
     */
    fun speakThen(text: String, language: Language, onFinished: () -> Unit): NovaResult<Unit> {
        val result: NovaResult<Unit> = speak(text, language)
        if (result is NovaResult.Success) onFinished()
        return result
    }
}
EOF

# ---------- 2. TtsSpeaker.kt (P7 behavior kept; completion callback added) ----------
cat > "$BASE/voice/TtsSpeaker.kt" <<'EOF'
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
EOF

# ---------- 3. AndroidVoiceEngine.kt (P7 behavior kept; speakThen added) ----------
cat > "$BASE/voice/AndroidVoiceEngine.kt" <<'EOF'
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
 * Voice input (Android speech recognizer) and voice output ([TtsSpeaker]).
 *
 * Listening must be used from the main thread (a SpeechRecognizer requirement).
 * [languageProvider] is read each time listening starts, and [speechRateProvider]
 * each time the app speaks, so settings changes apply immediately.
 */
class AndroidVoiceEngine(
    context: Context,
    private val languageProvider: () -> AppLanguage,
    private val speechRateProvider: () -> Float = { 1.0f }
) : VoiceEngine {

    private val appContext: Context = context.applicationContext
    private var recognizer: SpeechRecognizer? = null
    private var speaker: TtsSpeaker? = null
    private var speechProblemListener: ((NovaError) -> Unit)? = null

    @Volatile
    private var listening: Boolean = false

    /** Receives problems that appear after speaking started (main thread). */
    fun setSpeechProblemListener(listener: ((NovaError) -> Unit)?) {
        speechProblemListener = listener
        speaker?.setProblemListener(listener)
    }

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

        // Stop the app's own voice first, so the microphone does not hear it.
        stopSpeaking()

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

    override fun speak(text: String, language: Language): NovaResult<Unit> {
        return try {
            obtainSpeaker().speak(text, language, speechRateProvider())
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Speak request failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "কথা বলতে সমস্যা হয়েছে।", e)
        }
    }

    override fun speakThen(
        text: String,
        language: Language,
        onFinished: () -> Unit
    ): NovaResult<Unit> {
        return try {
            obtainSpeaker().speak(text, language, speechRateProvider(), onFinished)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Speak request failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "কথা বলতে সমস্যা হয়েছে।", e)
        }
    }

    override fun stopSpeaking() {
        try {
            speaker?.stop()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to stop speaking", e)
        }
    }

    override fun isSpeaking(): Boolean = speaker?.isSpeaking() == true

    override fun isListening(): Boolean = listening

    override fun shutdown() {
        listening = false
        releaseRecognizer()
        try {
            speaker?.shutdown()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to shut down speaker", e)
        } finally {
            speaker = null
        }
    }

    private fun obtainSpeaker(): TtsSpeaker {
        val existing: TtsSpeaker? = speaker
        if (existing != null) return existing
        val created = TtsSpeaker(appContext)
        created.setProblemListener(speechProblemListener)
        speaker = created
        return created
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
                putExtra("android.speech.extra.ADDITIONAL_LANGUAGES", arrayOf(TAG_ENGLISH))
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
EOF

# ---------- 4. ConversationModels.kt ----------
cat > "$BASE/voice/ConversationModels.kt" <<'EOF'
package com.nova.ai.voice

import com.nova.ai.core.Language
import com.nova.ai.core.NovaError
import com.nova.ai.core.VoiceCommand

/** What the conversation is doing right now. */
enum class ConversationState {
    /** No conversation running. */
    IDLE,

    /** Microphone is open and waiting for the user. */
    LISTENING,

    /** The app is speaking its reply. */
    SPEAKING,

    /** Short pause before listening again. */
    WAITING
}

/** Why a conversation ended. */
sealed class ConversationEnd {
    /** The user tapped stop (or the app went to the background). */
    object UserStopped : ConversationEnd()

    /** The user said a stop phrase such as "stop" or "থামো". */
    object StopPhrase : ConversationEnd()

    /** Nothing was heard several times in a row. */
    object SilenceTimeout : ConversationEnd()

    /** Continuous mode is off, so the single turn finished normally. */
    object SingleCompleted : ConversationEnd()

    /** A problem that cannot be recovered from automatically. */
    data class Failed(val error: NovaError) : ConversationEnd()
}

/** Text the app should speak after a command, and the language to use. */
data class SpokenReply(val text: String, val language: Language)

/** Receives conversation events. All calls happen on the main thread. */
interface ConversationListener {
    fun onStateChanged(state: ConversationState)
    fun onPartialText(text: String)
    fun onCommand(command: VoiceCommand)
    fun onEnded(reason: ConversationEnd)
}
EOF

# ---------- 5. StopPhrases.kt ----------
cat > "$BASE/voice/StopPhrases.kt" <<'EOF'
package com.nova.ai.voice

import java.util.Locale

/**
 * Recognizes spoken commands that end the conversation ("stop", "থামো", ...).
 * Only a whole short command counts, so "গান থামো" is NOT treated as a stop phrase.
 * Pure logic, no Android needed.
 */
object StopPhrases {

    // Keeps letters, digits and combining marks (Bangla vowel signs are marks).
    private val SEPARATORS: Regex = Regex("[^\\p{L}\\p{N}\\p{M}]+")

    private val FILLER_WORDS: Set<String> = setOf(
        "ভাই", "নোভা", "নভা", "nova", "hey", "ok", "okay", "please", "প্লিজ"
    )

    private val STOP_COMMANDS: Set<String> = setOf(
        "থামো", "থামুন", "থামাও", "থামিয়ে দাও", "থেমে যাও",
        "বন্ধ করো", "বন্ধ করুন", "বন্ধ কর", "কথোপকথন বন্ধ করো",
        "বাতিল", "বাতিল করো",
        "stop", "stop it", "stop listening", "exit", "cancel", "that is all"
    )

    /** True if [text] is only a stop command (filler words like "ভাই" are ignored). */
    fun isStopCommand(text: String): Boolean {
        val words: List<String> = SEPARATORS
            .split(text.lowercase(Locale.ROOT))
            .filter { it.isNotEmpty() && it !in FILLER_WORDS }
        if (words.isEmpty()) return false
        return words.joinToString(" ") in STOP_COMMANDS
    }
}
EOF

# ---------- 6. ConversationController.kt ----------
cat > "$BASE/voice/ConversationController.kt" <<'EOF'
package com.nova.ai.voice

import android.os.Handler
import android.os.Looper
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaError
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger

/**
 * Runs the listen, reply, listen-again cycle.
 *
 * - After each command the app can speak a reply ([replyProvider]); listening
 *   restarts only after the speech finished, so the app never hears itself.
 * - Ends on: user stop, a stop phrase, repeated silence, or an unrecoverable error.
 * - When [continuousProvider] returns false, it handles a single turn only.
 *
 * Use from the main thread only.
 */
class ConversationController(
    private val engine: VoiceEngine,
    private val listener: ConversationListener,
    private val continuousProvider: () -> Boolean,
    private val replyProvider: (VoiceCommand) -> SpokenReply?
) {

    private val handler: Handler = Handler(Looper.getMainLooper())
    private var active: Boolean = false
    private var state: ConversationState = ConversationState.IDLE
    private var missCount: Int = 0
    private var restartTask: Runnable? = null

    /** True while a conversation is running. */
    fun isActive(): Boolean = active

    /** Starts a conversation. A failure result means it did not start. */
    fun start(): NovaResult<Unit> {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, "কথোপকথন শুরু করতে হবে মূল থ্রেড থেকে।")
        }
        if (active) return NovaResult.Success(Unit)

        active = true
        missCount = 0
        val result: NovaResult<Unit> = beginListening()
        if (result is NovaResult.Failure) {
            active = false
            cancelRestart()
            setState(ConversationState.IDLE)
        }
        return result
    }

    /** Ends the conversation now (user pressed stop). */
    fun stop() {
        if (!active) return
        try {
            engine.stopListening()
            engine.stopSpeaking()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to stop voice engine", e)
        }
        finish(ConversationEnd.UserStopped)
    }

    /** Releases everything silently (no listener events). Call when the screen is gone. */
    fun shutdown() {
        active = false
        cancelRestart()
        state = ConversationState.IDLE
    }

    private val sessionListener: VoiceListener = object : VoiceListener {
        override fun onListeningStarted() {
            if (active) setState(ConversationState.LISTENING)
        }

        override fun onPartialText(text: String) {
            if (active) dispatch { listener.onPartialText(text) }
        }

        override fun onFinalCommand(command: VoiceCommand) {
            if (active) handleCommand(command)
        }

        override fun onError(error: NovaError) {
            if (active) handleError(error)
        }
    }

    private fun beginListening(): NovaResult<Unit> {
        setState(ConversationState.LISTENING)
        return engine.startListening(sessionListener)
    }

    private fun handleCommand(command: VoiceCommand) {
        missCount = 0

        if (StopPhrases.isStopCommand(command.rawText)) {
            finish(ConversationEnd.StopPhrase)
            return
        }

        dispatch { listener.onCommand(command) }
        if (!active) return

        val reply: SpokenReply? = replyProvider(command)
        if (reply == null) {
            continueOrFinish()
            return
        }

        setState(ConversationState.SPEAKING)
        val result: NovaResult<Unit> = engine.speakThen(reply.text, reply.language) {
            continueOrFinish()
        }
        // If speaking could not start, no completion callback will come.
        if (result is NovaResult.Failure) continueOrFinish()
    }

    private fun handleError(error: NovaError) {
        val nothingHeard: Boolean =
            error.code == ErrorCode.TIMEOUT || error.code == ErrorCode.NOT_FOUND

        if (continuousProvider() && nothingHeard) {
            missCount += 1
            if (missCount >= MAX_CONSECUTIVE_MISSES) {
                finish(ConversationEnd.SilenceTimeout)
            } else {
                scheduleRestart()
            }
        } else {
            finish(ConversationEnd.Failed(error))
        }
    }

    private fun continueOrFinish() {
        if (!active) return
        if (continuousProvider()) {
            scheduleRestart()
        } else {
            finish(ConversationEnd.SingleCompleted)
        }
    }

    private fun scheduleRestart() {
        if (!active) return
        cancelRestart()
        setState(ConversationState.WAITING)
        val task = Runnable { restartListening() }
        restartTask = task
        handler.postDelayed(task, RESTART_DELAY_MS)
    }

    private fun restartListening() {
        restartTask = null
        if (!active) return
        val result: NovaResult<Unit> = beginListening()
        if (result is NovaResult.Failure) {
            finish(ConversationEnd.Failed(result.error))
        }
    }

    private fun cancelRestart() {
        restartTask?.let { handler.removeCallbacks(it) }
        restartTask = null
    }

    private fun finish(reason: ConversationEnd) {
        if (!active) return
        active = false
        cancelRestart()
        setState(ConversationState.IDLE)
        NovaLogger.i(TAG, "Conversation ended: ${reason::class.java.simpleName}")
        dispatch { listener.onEnded(reason) }
    }

    private fun setState(newState: ConversationState) {
        if (state == newState) return
        state = newState
        dispatch { listener.onStateChanged(newState) }
    }

    /** A failing listener must never break the conversation loop. */
    private fun dispatch(block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Conversation listener threw an exception", e)
        }
    }

    private companion object {
        const val TAG: String = "ConversationController"
        const val MAX_CONSECUTIVE_MISSES: Int = 2
        const val RESTART_DELAY_MS: Long = 500L
    }
}
EOF

# ---------- 7. AppSettings.kt (previous fields kept; continuous setting added) ----------
cat > "$BASE/ui/theme/AppSettings.kt" <<'EOF'
package com.nova.ai.ui.theme

import androidx.compose.runtime.compositionLocalOf
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.SpeechSpeed
import com.nova.ai.settings.ThemeMode

/** Current settings plus the callbacks screens use to change them. */
data class AppSettingsState(
    val themeMode: ThemeMode,
    val language: AppLanguage,
    val onThemeModeChange: (ThemeMode) -> Unit,
    val onLanguageChange: (AppLanguage) -> Unit,
    val speechSpeed: SpeechSpeed = SpeechSpeed.NORMAL,
    val voiceReplyEnabled: Boolean = true,
    val onSpeechSpeedChange: (SpeechSpeed) -> Unit = { },
    val onVoiceReplyChange: (Boolean) -> Unit = { },
    val continuousConversation: Boolean = true,
    val onContinuousChange: (Boolean) -> Unit = { }
)

/** Gives every screen access to [AppSettingsState] without passing it manually. */
val LocalAppSettings = compositionLocalOf {
    AppSettingsState(
        themeMode = ThemeMode.SYSTEM,
        language = AppLanguage.BANGLA,
        onThemeModeChange = { },
        onLanguageChange = { }
    )
}
EOF

# ---------- 8. MainActivity.kt (P7 behavior kept; continuous setting wired in) ----------
cat > "$BASE/MainActivity.kt" <<'EOF'
package com.nova.ai

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.SettingsRepository
import com.nova.ai.settings.SpeechSpeed
import com.nova.ai.settings.ThemeMode
import com.nova.ai.ui.navigation.NovaMainScaffold
import com.nova.ai.ui.screens.OnboardingScreen
import com.nova.ai.ui.theme.AppSettingsState
import com.nova.ai.ui.theme.LocalAppSettings
import com.nova.ai.ui.theme.NovaTheme

/**
 * Single-activity host. Applies the theme, shows onboarding on first launch,
 * then the navigation graph (Home, Brain, Tasks, Access, Memory, Privacy).
 */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val repository = SettingsRepository(applicationContext)
            setContent { NovaRoot(repository) }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set content", e)
        }
    }

    companion object {
        private const val TAG: String = "MainActivity"
    }
}

/** Root composable: settings state, theme, onboarding gate and main scaffold. */
@Composable
private fun NovaRoot(repository: SettingsRepository) {
    var themeMode: ThemeMode by remember { mutableStateOf(repository.getThemeMode()) }
    var language: AppLanguage by remember { mutableStateOf(repository.getLanguage()) }
    var speechSpeed: SpeechSpeed by remember { mutableStateOf(repository.getSpeechSpeed()) }
    var voiceReplyEnabled: Boolean by remember { mutableStateOf(repository.isVoiceReplyEnabled()) }
    var continuousConversation: Boolean by remember {
        mutableStateOf(repository.isContinuousConversationEnabled())
    }
    var onboardingDone: Boolean by remember { mutableStateOf(repository.isOnboardingDone()) }

    val settingsState = AppSettingsState(
        themeMode = themeMode,
        language = language,
        onThemeModeChange = { newMode ->
            themeMode = newMode
            repository.setThemeMode(newMode)
        },
        onLanguageChange = { newLanguage ->
            language = newLanguage
            repository.setLanguage(newLanguage)
        },
        speechSpeed = speechSpeed,
        voiceReplyEnabled = voiceReplyEnabled,
        onSpeechSpeedChange = { newSpeed ->
            speechSpeed = newSpeed
            repository.setSpeechSpeed(newSpeed)
        },
        onVoiceReplyChange = { enabled ->
            voiceReplyEnabled = enabled
            repository.setVoiceReplyEnabled(enabled)
        },
        continuousConversation = continuousConversation,
        onContinuousChange = { enabled ->
            continuousConversation = enabled
            repository.setContinuousConversationEnabled(enabled)
        }
    )

    NovaTheme(themeMode = themeMode) {
        CompositionLocalProvider(LocalAppSettings provides settingsState) {
            Surface(modifier = Modifier.fillMaxSize()) {
                if (onboardingDone) {
                    NovaMainScaffold()
                } else {
                    OnboardingScreen(
                        onFinished = { chosenLanguage, chosenTheme ->
                            language = chosenLanguage
                            themeMode = chosenTheme
                            repository.setLanguage(chosenLanguage)
                            repository.setThemeMode(chosenTheme)
                            repository.setOnboardingDone(true)
                            onboardingDone = true
                        }
                    )
                }
            }
        }
    }
}
EOF

# ---------- 9. HomeScreen.kt (P7 behavior kept; continuous conversation added) ----------
cat > "$BASE/ui/screens/HomeScreen.kt" <<'EOF'
package com.nova.ai.ui.screens

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.nova.ai.R
import com.nova.ai.core.Language
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.SpeechSpeed
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout
import com.nova.ai.ui.theme.LocalAppSettings
import com.nova.ai.voice.AndroidVoiceEngine
import com.nova.ai.voice.ConversationController
import com.nova.ai.voice.ConversationEnd
import com.nova.ai.voice.ConversationListener
import com.nova.ai.voice.ConversationState
import com.nova.ai.voice.SpokenReply
import com.nova.ai.voice.toSpeechLanguage

private const val TAG: String = "HomeScreen"
private const val TRANSCRIPT_LIMIT: Int = 5

/**
 * Home: voice button, command box, current status and running-task progress.
 * The mic button starts a conversation: the app listens, confirms by voice,
 * and (when continuous mode is on) listens again by itself until the user says
 * stop, stays silent, or leaves the screen. Command understanding comes in Phase 11.
 */
@Composable
fun HomeScreen(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val settings = LocalAppSettings.current
    val currentLanguage: AppLanguage by rememberUpdatedState(settings.language)
    val currentSpeed: SpeechSpeed by rememberUpdatedState(settings.speechSpeed)
    val replyEnabled: Boolean by rememberUpdatedState(settings.voiceReplyEnabled)
    val continuousEnabled: Boolean by rememberUpdatedState(settings.continuousConversation)

    var commandText: String by rememberSaveable { mutableStateOf("") }
    var statusOverride: String by rememberSaveable { mutableStateOf("") }
    var conversationState: ConversationState by remember {
        mutableStateOf(ConversationState.IDLE)
    }
    var commandCount: Int by remember { mutableStateOf(0) }
    val transcript = remember { mutableStateListOf<String>() }

    val readyText: String = stringResource(R.string.home_status_ready)
    val idleText: String = stringResource(R.string.home_status_ready_voice)
    val receivedText: String = stringResource(R.string.home_status_command_received)
    val emptyText: String = stringResource(R.string.home_status_empty_command)
    val voiceDescription: String = stringResource(R.string.home_voice_button_desc)
    val stopDescription: String = stringResource(R.string.home_voice_stop_desc)

    // One voice engine per Home screen; released when the screen leaves.
    val voiceEngine: AndroidVoiceEngine = remember {
        AndroidVoiceEngine(
            context = context,
            languageProvider = { currentLanguage },
            speechRateProvider = { currentSpeed.rate }
        )
    }

    // Conversation events arrive on the main thread, so updating UI state here is safe.
    val conversation: ConversationController = remember {
        ConversationController(
            engine = voiceEngine,
            listener = object : ConversationListener {
                override fun onStateChanged(state: ConversationState) {
                    conversationState = state
                    when (state) {
                        ConversationState.LISTENING ->
                            statusOverride = listeningStatus(context, commandCount)
                        ConversationState.SPEAKING ->
                            statusOverride = context.getString(R.string.home_status_speaking)
                        ConversationState.WAITING ->
                            statusOverride = context.getString(R.string.home_status_next_turn)
                        ConversationState.IDLE -> Unit
                    }
                }

                override fun onPartialText(text: String) {
                    commandText = text
                }

                override fun onCommand(command: VoiceCommand) {
                    commandCount += 1
                    commandText = command.rawText
                    statusOverride = context.getString(R.string.home_status_heard, command.rawText)
                    transcript.add("$commandCount. ${command.rawText}")
                    while (transcript.size > TRANSCRIPT_LIMIT) transcript.removeAt(0)
                }

                override fun onEnded(reason: ConversationEnd) {
                    when (reason) {
                        is ConversationEnd.UserStopped ->
                            statusOverride = context.getString(R.string.home_status_ended_user)
                        is ConversationEnd.StopPhrase -> {
                            statusOverride = context.getString(R.string.home_status_ended_phrase)
                            if (replyEnabled) {
                                val english: Boolean = currentLanguage == AppLanguage.ENGLISH
                                val ackRes: Int = if (english) {
                                    R.string.home_voice_stop_ack_en
                                } else {
                                    R.string.home_voice_stop_ack
                                }
                                voiceEngine.speak(
                                    context.getString(ackRes),
                                    currentLanguage.toSpeechLanguage()
                                )
                            }
                        }
                        is ConversationEnd.SilenceTimeout ->
                            statusOverride = context.getString(R.string.home_status_ended_silence)
                        is ConversationEnd.SingleCompleted ->
                            statusOverride =
                                context.getString(R.string.home_status_heard, commandText)
                        is ConversationEnd.Failed ->
                            statusOverride = context.getString(
                                R.string.home_voice_error,
                                reason.error.message
                            )
                    }
                }
            },
            continuousProvider = { continuousEnabled },
            replyProvider = { command ->
                if (replyEnabled) buildReply(context, command, currentLanguage) else null
            }
        )
    }

    // Release everything when the screen leaves, and close the microphone
    // whenever the app goes to the background.
    val lifecycleOwner: LifecycleOwner? = context as? LifecycleOwner
    DisposableEffect(lifecycleOwner, conversation) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) conversation.stop()
        }
        lifecycleOwner?.lifecycle?.addObserver(observer)
        onDispose {
            lifecycleOwner?.lifecycle?.removeObserver(observer)
            conversation.shutdown()
            voiceEngine.shutdown()
        }
    }

    fun startConversation() {
        commandCount = 0
        transcript.clear()
        when (val result: NovaResult<Unit> = conversation.start()) {
            is NovaResult.Success -> Unit
            is NovaResult.Failure -> {
                statusOverride = context.getString(R.string.home_voice_error, result.error.message)
                NovaLogger.w(TAG, "Conversation start failed: ${result.error.message}")
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted: Boolean ->
        if (granted) {
            startConversation()
        } else {
            statusOverride = context.getString(R.string.home_mic_permission_denied)
        }
    }

    val sessionActive: Boolean = conversationState != ConversationState.IDLE
    val currentStatus: String =
        if (statusOverride.isEmpty()) "$readyText\n$idleText" else statusOverride

    NovaScreenLayout(
        title = stringResource(R.string.home_title),
        subtitle = stringResource(R.string.home_subtitle),
        modifier = modifier
    ) {
        Box(
            modifier = Modifier.fillMaxWidth(),
            contentAlignment = Alignment.Center
        ) {
            val buttonDescription: String = if (sessionActive) stopDescription else voiceDescription
            Button(
                onClick = {
                    if (sessionActive) {
                        conversation.stop()
                    } else {
                        val micGranted: Boolean = ContextCompat.checkSelfPermission(
                            context, Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                        if (micGranted) {
                            startConversation()
                        } else {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    }
                },
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (sessionActive) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.primary
                    }
                ),
                modifier = Modifier
                    .size(120.dp)
                    .semantics { contentDescription = buttonDescription }
            ) {
                Text(text = if (sessionActive) "⏹️" else "🎙️", fontSize = 40.sp)
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = stringResource(R.string.home_continuous_label),
                style = MaterialTheme.typography.titleMedium
            )
            Switch(
                checked = settings.continuousConversation,
                onCheckedChange = settings.onContinuousChange
            )
        }
        Text(
            text = stringResource(R.string.home_continuous_hint),
            style = MaterialTheme.typography.bodySmall
        )

        NovaInfoCard(
            title = stringResource(R.string.home_status_label),
            body = currentStatus
        )

        OutlinedTextField(
            value = commandText,
            onValueChange = { commandText = it },
            label = { Text(stringResource(R.string.home_command_hint)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )

        Button(
            onClick = {
                statusOverride = if (commandText.isBlank()) emptyText else receivedText
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(stringResource(R.string.home_send))
        }

        if (transcript.isNotEmpty()) {
            NovaInfoCard(
                title = stringResource(R.string.home_transcript_title),
                body = transcript.joinToString("\n")
            )
        }

        NovaInfoCard(
            title = stringResource(R.string.home_progress_title),
            body = stringResource(R.string.home_progress_none)
        )
    }
}

/** Status line while listening; shows how many commands this conversation has had. */
private fun listeningStatus(context: Context, count: Int): String =
    if (count == 0) {
        context.getString(R.string.home_status_listening)
    } else {
        context.getString(R.string.home_status_listening_count, count)
    }

/** Builds the spoken confirmation for [command] in the language it was spoken in. */
private fun buildReply(context: Context, command: VoiceCommand, fallback: AppLanguage): SpokenReply {
    val english: Boolean = command.language == Language.ENGLISH
    val replyRes: Int = if (english) R.string.home_voice_ack_en else R.string.home_voice_ack
    val spoken: Language = if (command.language == Language.UNKNOWN) {
        fallback.toSpeechLanguage()
    } else {
        command.language
    }
    return SpokenReply(context.getString(replyRes, command.rawText), spoken)
}
EOF

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "P8: continuous conversation with stop phrases and silence timeout"
git push

echo "P8 files created and pushed."
