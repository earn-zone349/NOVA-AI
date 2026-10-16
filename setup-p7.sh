#!/usr/bin/env bash
# NOVA AI - Phase 7 setup script: voice output (text to speech) + voice settings.
# Additive: previous behavior is kept in every rewritten file.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
MANIFEST="app/src/main/AndroidManifest.xml"

if [ ! -f "$BASE/voice/AndroidVoiceEngine.kt" ] || [ ! -f "$BASE/ui/screens/HomeScreen.kt" ]; then
  echo "ERROR: Run from repo root after P1 to P6 are installed." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"

# ---------- A. Manifest: let the app see the text-to-speech service ----------
if ! grep -q "android.intent.action.TTS_SERVICE" "$MANIFEST"; then
  cat > "$TMP_DIR/tts_query.txt" <<'EOF'
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE" />
        </intent>
EOF
  sed -i "/<queries>/r $TMP_DIR/tts_query.txt" "$MANIFEST"
fi
grep -q "android.intent.action.TTS_SERVICE" "$MANIFEST" || { echo "ERROR: manifest TTS edit failed" >&2; exit 1; }

# ---------- B. New strings file ----------
cat > app/src/main/res/values/strings_p7.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="home_voice_ack">ঠিক আছে, শুনেছি: %1$s</string>
    <string name="home_voice_ack_en">Okay, I heard: %1$s</string>

    <string name="brain_voice_title">ভয়েস উত্তর</string>
    <string name="brain_voice_reply_label">অ্যাপ মুখে উত্তর দেবে</string>
    <string name="brain_voice_speed_title">কথা বলার গতি</string>
    <string name="settings_speed_slow">ধীরে</string>
    <string name="settings_speed_normal">স্বাভাবিক</string>
    <string name="settings_speed_fast">দ্রুত</string>
    <string name="brain_voice_test_button">ভয়েস পরীক্ষা করো</string>
    <string name="brain_voice_test_bn">আমি নোভা, তোমার ফোন এজেন্ট। আমি তোমার কথা শুনছি।</string>
    <string name="brain_voice_test_en">I am Nova, your phone agent. I am listening.</string>
    <string name="brain_voice_problem">ভয়েস সমস্যা: %1$s</string>
</resources>
EOF

# ---------- 1. VoiceEngine.kt (all previous methods kept; two optional methods added) ----------
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
}
EOF

# ---------- 2. LanguageMapping.kt ----------
cat > "$BASE/voice/LanguageMapping.kt" <<'EOF'
package com.nova.ai.voice

import com.nova.ai.core.Language
import com.nova.ai.settings.AppLanguage

/** Converts the language chosen in settings into the language used for speech. */
fun AppLanguage.toSpeechLanguage(): Language = when (this) {
    AppLanguage.BANGLA -> Language.BANGLA
    AppLanguage.ENGLISH -> Language.ENGLISH
    AppLanguage.MIXED -> Language.MIXED
}
EOF

# ---------- 3. TtsSpeaker.kt ----------
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
EOF

# ---------- 4. AndroidVoiceEngine.kt (P6 behavior kept; speaking added) ----------
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

# ---------- 5. SettingsRepository.kt (previous settings kept; voice settings added) ----------
cat > "$BASE/settings/SettingsRepository.kt" <<'EOF'
package com.nova.ai.settings

import android.content.Context
import android.content.SharedPreferences
import android.util.Log

/** Theme choice. */
enum class ThemeMode { SYSTEM, LIGHT, DARK }

/** Preferred interaction language. */
enum class AppLanguage { BANGLA, ENGLISH, MIXED }

/** How fast the app speaks. [rate] 1.0 is normal speed. */
enum class SpeechSpeed(val rate: Float) {
    SLOW(0.75f),
    NORMAL(1.0f),
    FAST(1.3f)
}

/**
 * Stores app settings on the device only (SharedPreferences).
 * Every read falls back to a safe default, and every write is guarded,
 * so storage problems never crash the app.
 */
class SettingsRepository(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getThemeMode(): ThemeMode = readEnum(KEY_THEME, ThemeMode.SYSTEM)

    fun setThemeMode(mode: ThemeMode) = writeString(KEY_THEME, mode.name)

    fun getLanguage(): AppLanguage = readEnum(KEY_LANGUAGE, AppLanguage.BANGLA)

    fun setLanguage(language: AppLanguage) = writeString(KEY_LANGUAGE, language.name)

    fun getSpeechSpeed(): SpeechSpeed = readEnum(KEY_SPEECH_SPEED, SpeechSpeed.NORMAL)

    fun setSpeechSpeed(speed: SpeechSpeed) = writeString(KEY_SPEECH_SPEED, speed.name)

    fun isVoiceReplyEnabled(): Boolean = readBoolean(KEY_VOICE_REPLY, true)

    fun setVoiceReplyEnabled(enabled: Boolean) = writeBoolean(KEY_VOICE_REPLY, enabled)

    fun isOnboardingDone(): Boolean = readBoolean(KEY_ONBOARDING_DONE, false)

    fun setOnboardingDone(done: Boolean) = writeBoolean(KEY_ONBOARDING_DONE, done)

    private inline fun <reified T : Enum<T>> readEnum(key: String, default: T): T {
        return try {
            val stored: String? = prefs.getString(key, null)
            if (stored == null) default else enumValueOf<T>(stored)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read $key, using default", e)
            default
        }
    }

    private fun readBoolean(key: String, default: Boolean): Boolean = try {
        prefs.getBoolean(key, default)
    } catch (e: Exception) {
        Log.e(TAG, "Failed to read $key, using default", e)
        default
    }

    private fun writeString(key: String, value: String) {
        try {
            prefs.edit().putString(key, value).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save $key", e)
        }
    }

    private fun writeBoolean(key: String, value: Boolean) {
        try {
            prefs.edit().putBoolean(key, value).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save $key", e)
        }
    }

    private companion object {
        const val TAG: String = "SettingsRepository"
        const val PREFS_NAME: String = "nova_settings"
        const val KEY_THEME: String = "theme_mode"
        const val KEY_LANGUAGE: String = "app_language"
        const val KEY_ONBOARDING_DONE: String = "onboarding_done"
        const val KEY_SPEECH_SPEED: String = "speech_speed"
        const val KEY_VOICE_REPLY: String = "voice_reply_enabled"
    }
}
EOF

# ---------- 6. AppSettings.kt (previous fields kept; voice fields added with defaults) ----------
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
    val onVoiceReplyChange: (Boolean) -> Unit = { }
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

# ---------- 7. SpeechLabels.kt ----------
cat > "$BASE/ui/components/SpeechLabels.kt" <<'EOF'
package com.nova.ai.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.settings.SpeechSpeed

/** Display text for a [SpeechSpeed]. */
@Composable
fun speechSpeedLabel(speed: SpeechSpeed): String = stringResource(
    when (speed) {
        SpeechSpeed.SLOW -> R.string.settings_speed_slow
        SpeechSpeed.NORMAL -> R.string.settings_speed_normal
        SpeechSpeed.FAST -> R.string.settings_speed_fast
    }
)
EOF

# ---------- 8. MainActivity.kt (P4 behavior kept; voice settings wired in) ----------
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

# ---------- 9. AiBrainScreen.kt (previous cards kept; voice reply card added) ----------
cat > "$BASE/ui/screens/AiBrainScreen.kt" <<'EOF'
package com.nova.ai.ui.screens

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.core.Language
import com.nova.ai.core.NovaResult
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.SpeechSpeed
import com.nova.ai.settings.ThemeMode
import com.nova.ai.ui.components.NovaChoiceGroup
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout
import com.nova.ai.ui.components.languageLabel
import com.nova.ai.ui.components.speechSpeedLabel
import com.nova.ai.ui.components.themeModeLabel
import com.nova.ai.ui.theme.LocalAppSettings
import com.nova.ai.voice.AndroidVoiceEngine

/** AI Brain: model status, memory use, offline status, language, appearance and voice reply. */
@Composable
fun AiBrainScreen(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val settings = LocalAppSettings.current
    val currentLanguage: AppLanguage by rememberUpdatedState(settings.language)
    val currentSpeed: SpeechSpeed by rememberUpdatedState(settings.speechSpeed)

    var testMessage: String by remember { mutableStateOf("") }

    // Voice engine used only for the "test voice" button; released when the screen leaves.
    val voiceEngine: AndroidVoiceEngine = remember {
        AndroidVoiceEngine(
            context = context,
            languageProvider = { currentLanguage },
            speechRateProvider = { currentSpeed.rate }
        )
    }
    DisposableEffect(voiceEngine) {
        voiceEngine.setSpeechProblemListener { error ->
            testMessage = context.getString(R.string.brain_voice_problem, error.message)
        }
        onDispose {
            voiceEngine.setSpeechProblemListener(null)
            voiceEngine.shutdown()
        }
    }

    val testSentenceBangla: String = stringResource(R.string.brain_voice_test_bn)
    val testSentenceEnglish: String = stringResource(R.string.brain_voice_test_en)

    NovaScreenLayout(
        title = stringResource(R.string.brain_title),
        subtitle = stringResource(R.string.brain_subtitle),
        modifier = modifier
    ) {
        NovaInfoCard(
            title = stringResource(R.string.brain_model_title),
            body = stringResource(R.string.brain_model_none)
        )
        NovaInfoCard(
            title = stringResource(R.string.brain_ram_title),
            body = stringResource(R.string.brain_ram_none)
        )
        NovaInfoCard(
            title = stringResource(R.string.brain_offline_title),
            body = stringResource(R.string.brain_offline_body)
        )
        NovaInfoCard(
            title = stringResource(R.string.brain_language_title),
            body = stringResource(R.string.brain_language_body)
        )

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                NovaChoiceGroup(
                    title = stringResource(R.string.settings_language_title),
                    options = AppLanguage.values().toList(),
                    selected = settings.language,
                    labelOf = { languageLabel(it) },
                    onSelected = settings.onLanguageChange
                )
                NovaChoiceGroup(
                    title = stringResource(R.string.settings_theme_title),
                    options = ThemeMode.values().toList(),
                    selected = settings.themeMode,
                    labelOf = { themeModeLabel(it) },
                    onSelected = settings.onThemeModeChange
                )
            }
        }

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.brain_voice_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = stringResource(R.string.brain_voice_reply_label),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Switch(
                        checked = settings.voiceReplyEnabled,
                        onCheckedChange = settings.onVoiceReplyChange
                    )
                }
                NovaChoiceGroup(
                    title = stringResource(R.string.brain_voice_speed_title),
                    options = SpeechSpeed.values().toList(),
                    selected = settings.speechSpeed,
                    labelOf = { speechSpeedLabel(it) },
                    onSelected = settings.onSpeechSpeedChange
                )
                Button(
                    onClick = {
                        testMessage = ""
                        val useEnglish: Boolean = settings.language == AppLanguage.ENGLISH
                        val sentence: String =
                            if (useEnglish) testSentenceEnglish else testSentenceBangla
                        val spoken: Language =
                            if (useEnglish) Language.ENGLISH else Language.BANGLA
                        val result: NovaResult<Unit> = voiceEngine.speak(sentence, spoken)
                        if (result is NovaResult.Failure) {
                            testMessage = context.getString(
                                R.string.brain_voice_problem,
                                result.error.message
                            )
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.brain_voice_test_button))
                }
                if (testMessage.isNotEmpty()) {
                    Text(text = testMessage, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
EOF

# ---------- 10. HomeScreen.kt (P6 behavior kept; spoken reply added) ----------
cat > "$BASE/ui/screens/HomeScreen.kt" <<'EOF'
package com.nova.ai.ui.screens

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
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
import com.nova.ai.R
import com.nova.ai.core.Language
import com.nova.ai.core.NovaError
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.SpeechSpeed
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout
import com.nova.ai.ui.theme.LocalAppSettings
import com.nova.ai.voice.AndroidVoiceEngine
import com.nova.ai.voice.VoiceEngine
import com.nova.ai.voice.VoiceListener
import com.nova.ai.voice.toSpeechLanguage

private const val TAG: String = "HomeScreen"

/**
 * Home: voice button, command box, current status and running-task progress.
 * The mic button listens in the language chosen in AI Brain settings and
 * writes the recognized text into the command box. When voice reply is on,
 * the app also confirms by voice. Command understanding comes in Phase 11.
 */
@Composable
fun HomeScreen(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val settings = LocalAppSettings.current
    val currentLanguage: AppLanguage by rememberUpdatedState(settings.language)
    val currentSpeed: SpeechSpeed by rememberUpdatedState(settings.speechSpeed)
    val replyEnabled: Boolean by rememberUpdatedState(settings.voiceReplyEnabled)

    var commandText: String by rememberSaveable { mutableStateOf("") }
    var statusOverride: String by rememberSaveable { mutableStateOf("") }
    var isListening: Boolean by remember { mutableStateOf(false) }

    val readyText: String = stringResource(R.string.home_status_ready)
    val idleText: String = stringResource(R.string.home_status_ready_voice)
    val receivedText: String = stringResource(R.string.home_status_command_received)
    val emptyText: String = stringResource(R.string.home_status_empty_command)
    val processingText: String = stringResource(R.string.home_status_processing)
    val voiceDescription: String = stringResource(R.string.home_voice_button_desc)
    val stopDescription: String = stringResource(R.string.home_voice_stop_desc)

    // One voice engine per Home screen; released when the screen leaves.
    val voiceEngine: VoiceEngine = remember {
        AndroidVoiceEngine(
            context = context,
            languageProvider = { currentLanguage },
            speechRateProvider = { currentSpeed.rate }
        )
    }
    DisposableEffect(voiceEngine) {
        onDispose { voiceEngine.shutdown() }
    }

    // Callbacks arrive on the main thread, so updating UI state here is safe.
    val voiceListener: VoiceListener = remember {
        object : VoiceListener {
            override fun onListeningStarted() {
                isListening = true
                statusOverride = context.getString(R.string.home_status_listening)
            }

            override fun onPartialText(text: String) {
                commandText = text
            }

            override fun onFinalCommand(command: VoiceCommand) {
                isListening = false
                commandText = command.rawText
                statusOverride = context.getString(R.string.home_status_heard, command.rawText)

                if (replyEnabled) {
                    val isEnglish: Boolean = command.language == Language.ENGLISH
                    val replyRes: Int =
                        if (isEnglish) R.string.home_voice_ack_en else R.string.home_voice_ack
                    val spokenLanguage: Language =
                        if (command.language == Language.UNKNOWN) {
                            currentLanguage.toSpeechLanguage()
                        } else {
                            command.language
                        }
                    voiceEngine.speak(context.getString(replyRes, command.rawText), spokenLanguage)
                }
            }

            override fun onError(error: NovaError) {
                isListening = false
                statusOverride = context.getString(R.string.home_voice_error, error.message)
            }
        }
    }

    fun startVoice() {
        when (val result: NovaResult<Unit> = voiceEngine.startListening(voiceListener)) {
            is NovaResult.Success -> {
                isListening = true
                statusOverride = context.getString(R.string.home_status_listening)
            }
            is NovaResult.Failure -> {
                isListening = false
                statusOverride = context.getString(R.string.home_voice_error, result.error.message)
                NovaLogger.w(TAG, "Voice start failed: ${result.error.message}")
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted: Boolean ->
        if (granted) {
            startVoice()
        } else {
            statusOverride = context.getString(R.string.home_mic_permission_denied)
        }
    }

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
            val buttonDescription: String = if (isListening) stopDescription else voiceDescription
            Button(
                onClick = {
                    if (isListening) {
                        voiceEngine.stopListening()
                        isListening = false
                        statusOverride = processingText
                    } else {
                        val micGranted: Boolean = ContextCompat.checkSelfPermission(
                            context, Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                        if (micGranted) {
                            startVoice()
                        } else {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    }
                },
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isListening) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.primary
                    }
                ),
                modifier = Modifier
                    .size(120.dp)
                    .semantics { contentDescription = buttonDescription }
            ) {
                Text(text = if (isListening) "⏹️" else "🎙️", fontSize = 40.sp)
            }
        }

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

        NovaInfoCard(
            title = stringResource(R.string.home_progress_title),
            body = stringResource(R.string.home_progress_none)
        )
    }
}
EOF

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "P7: voice output (text to speech) and voice settings"
git push

echo "P7 files created and pushed."
