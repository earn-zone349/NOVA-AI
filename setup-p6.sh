#!/usr/bin/env bash
# NOVA AI - Phase 6 setup script: voice input (speech to text).
# Additive: new voice classes, new manifest lines, and HomeScreen rewritten
# with every previous element kept (the mic button now does real work).
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
MANIFEST="app/src/main/AndroidManifest.xml"

if [ ! -f "$BASE/logging/NovaLogger.kt" ] || [ ! -f "$BASE/voice/VoiceEngine.kt" ]; then
  echo "ERROR: Run from repo root after P1 to P5 are installed." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"

# ---------- A. Manifest: microphone permission + speech service visibility ----------
if ! grep -q "android.permission.RECORD_AUDIO" "$MANIFEST"; then
  cat > "$TMP_DIR/manifest_add.txt" <<'EOF'

    <uses-permission android:name="android.permission.RECORD_AUDIO" />

    <queries>
        <intent>
            <action android:name="android.speech.RecognitionService" />
        </intent>
    </queries>
EOF
  sed -i "/<manifest xmlns:android/r $TMP_DIR/manifest_add.txt" "$MANIFEST"
fi
grep -q "android.permission.RECORD_AUDIO" "$MANIFEST" || { echo "ERROR: manifest edit failed" >&2; exit 1; }
grep -q "android.speech.RecognitionService" "$MANIFEST" || { echo "ERROR: manifest queries edit failed" >&2; exit 1; }

# ---------- B. New strings file ----------
cat > app/src/main/res/values/strings_p6.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="home_status_ready_voice">প্রস্তুত। মাইক বাটন চেপে বলো।</string>
    <string name="home_status_listening">শুনছি... এখন বলো।</string>
    <string name="home_status_processing">প্রক্রিয়া করছি...</string>
    <string name="home_status_heard">শুনেছি: %1$s</string>
    <string name="home_mic_permission_denied">মাইক্রোফোনের অনুমতি ছাড়া ভয়েস কমান্ড চলবে না। অনুমতি দিয়ে আবার চেষ্টা করো।</string>
    <string name="home_voice_error">ভয়েস সমস্যা: %1$s</string>
    <string name="home_voice_stop_desc">শোনা বন্ধ করো</string>
</resources>
EOF

mkdir -p "$BASE/voice"

# ---------- 1. LanguageDetector.kt ----------
cat > "$BASE/voice/LanguageDetector.kt" <<'EOF'
package com.nova.ai.voice

import com.nova.ai.core.Language

/**
 * Detects whether a piece of text is Bangla, English, or a mix of both,
 * by counting Bangla-script and Latin letters. Pure logic, no Android needed.
 */
object LanguageDetector {

    private const val BANGLA_RANGE_START: Int = 0x0980
    private const val BANGLA_RANGE_END: Int = 0x09FF

    /** If neither script reaches this share of letters, the text counts as mixed. */
    private const val MIXED_THRESHOLD: Float = 0.15f

    /** Returns the dominant [Language] of [text], or UNKNOWN if it has no letters. */
    fun detect(text: String): Language {
        var banglaCount = 0
        var latinCount = 0

        for (character in text) {
            val isBangla: Boolean = character.code in BANGLA_RANGE_START..BANGLA_RANGE_END
            val isLatin: Boolean = character in 'a'..'z' || character in 'A'..'Z'
            if (isBangla) banglaCount++ else if (isLatin) latinCount++
        }

        val total: Int = banglaCount + latinCount
        if (total == 0) return Language.UNKNOWN

        val banglaShare: Float = banglaCount.toFloat() / total.toFloat()
        return when {
            banglaShare >= 1f - MIXED_THRESHOLD -> Language.BANGLA
            banglaShare <= MIXED_THRESHOLD -> Language.ENGLISH
            else -> Language.MIXED
        }
    }
}
EOF

# ---------- 2. SpeechErrorMapper.kt ----------
cat > "$BASE/voice/SpeechErrorMapper.kt" <<'EOF'
package com.nova.ai.voice

import android.speech.SpeechRecognizer
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaError

/** Converts Android speech-recognizer error numbers into [NovaError] with a Bangla message. */
internal object SpeechErrorMapper {

    fun toNovaError(speechError: Int): NovaError {
        val mapped: Pair<ErrorCode, String> = when (speechError) {
            SpeechRecognizer.ERROR_AUDIO ->
                ErrorCode.NOT_AVAILABLE to "অডিও রেকর্ড করতে সমস্যা হয়েছে।"
            SpeechRecognizer.ERROR_CLIENT ->
                ErrorCode.EXECUTION_FAILED to "ভয়েস সিস্টেমে ছোট একটি সমস্যা হয়েছে। আবার চেষ্টা করো।"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                ErrorCode.PERMISSION_DENIED to "মাইক্রোফোনের অনুমতি নেই।"
            SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                ErrorCode.NOT_AVAILABLE to "ইন্টারনেট সমস্যা। এই ভাষার অফলাইন ভয়েস নাও থাকতে পারে।"
            SpeechRecognizer.ERROR_NO_MATCH ->
                ErrorCode.NOT_FOUND to "কথা বোঝা যায়নি। আবার পরিষ্কার করে বলো।"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                ErrorCode.TIMEOUT to "কিছু শোনা যায়নি। আবার চেষ্টা করো।"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY ->
                ErrorCode.NOT_AVAILABLE to "ভয়েস সিস্টেম ব্যস্ত আছে। একটু পরে চেষ্টা করো।"
            SpeechRecognizer.ERROR_SERVER, SpeechRecognizer.ERROR_SERVER_DISCONNECTED ->
                ErrorCode.NOT_AVAILABLE to "ভয়েস সার্ভিসে সমস্যা হয়েছে। আবার চেষ্টা করো।"
            SpeechRecognizer.ERROR_TOO_MANY_REQUESTS ->
                ErrorCode.NOT_AVAILABLE to "অনেকবার চেষ্টা হয়েছে। একটু পরে আবার চেষ্টা করো।"
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
            SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
                ErrorCode.NOT_AVAILABLE to "এই ভাষা ফোনে চালু নেই। AI Brain ট্যাব থেকে ভাষা বদলে দেখো।"
            else ->
                ErrorCode.UNKNOWN to "অজানা ভয়েস সমস্যা (কোড $speechError)।"
        }
        return NovaError(code = mapped.first, message = mapped.second)
    }
}
EOF

# ---------- 3. AndroidVoiceEngine.kt ----------
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
EOF

# ---------- C. HomeScreen.kt (all previous elements kept; mic button now works) ----------
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
import com.nova.ai.core.NovaError
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.settings.AppLanguage
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout
import com.nova.ai.ui.theme.LocalAppSettings
import com.nova.ai.voice.AndroidVoiceEngine
import com.nova.ai.voice.VoiceEngine
import com.nova.ai.voice.VoiceListener

private const val TAG: String = "HomeScreen"

/**
 * Home: voice button, command box, current status and running-task progress.
 * The mic button listens in the language chosen in AI Brain settings and
 * writes the recognized text into the command box. Command understanding
 * is connected in Phase 11.
 */
@Composable
fun HomeScreen(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val settings = LocalAppSettings.current
    val currentLanguage: AppLanguage by rememberUpdatedState(settings.language)

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
    val voiceEngine: VoiceEngine = remember { AndroidVoiceEngine(context) { currentLanguage } }
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
git commit -m "P6: voice input (speech to text) with mic permission"
git push

echo "P6 files created and pushed."
