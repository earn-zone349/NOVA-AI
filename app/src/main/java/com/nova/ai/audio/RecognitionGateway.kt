package com.nova.ai.audio

import android.content.Context
import android.os.SystemClock
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaError
import com.nova.ai.core.NovaResult
import com.nova.ai.models.FileModelManager
import com.nova.ai.models.ModelCatalog
import com.nova.ai.models.WhisperModelSpec
import com.nova.ai.settings.AppLanguage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * One place that turns speech into text. It sends the sound to Google's recognizer,
 * or to the offline Whisper model when [RecognitionRouting.useWhisper] is on.
 * Same calls and result type as [GoogleRecognizerBridge]. One request at a time.
 * Use from the main thread.
 */
class RecognitionGateway(
    context: Context,
    private val scope: CoroutineScope
) {

    private val appContext: Context = context.applicationContext
    private val google = GoogleRecognizerBridge(appContext, scope)
    private val models = FileModelManager(appContext)
    private var whisperJob: Job? = null

    /** True if this Android version can feed our own sound to Google's recognizer. */
    fun isFeedSupported(): Boolean = google.isFeedSupported()

    /** True if the phone has Google's offline recognizer. */
    fun isOnDeviceAvailable(): Boolean = google.isOnDeviceAvailable()

    /** Converts [samples] to text and reports the result to [onResult] on the main thread. */
    fun recognize(
        samples: ShortArray,
        service: GoogleRecognizerBridge.Service,
        language: AppLanguage,
        onResult: (GoogleRecognizerBridge.Outcome) -> Unit
    ) {
        cancel()
        if (RecognitionRouting.useWhisper) {
            recognizeWithWhisper(samples, language, onResult)
        } else {
            google.recognize(samples, service, language, onResult)
        }
    }

    /** Stops the request in progress without reporting a result. */
    fun cancel() {
        google.cancel()
        whisperJob?.cancel()
        whisperJob = null
    }

    private fun recognizeWithWhisper(
        samples: ShortArray,
        language: AppLanguage,
        onResult: (GoogleRecognizerBridge.Outcome) -> Unit
    ) {
        val spec: WhisperModelSpec? = ModelCatalog.find(RecognitionRouting.whisperModelId)
        if (spec == null || !models.isInstalled(spec)) {
            onResult(failure(ErrorCode.NOT_AVAILABLE, MSG_MODEL_MISSING))
            return
        }

        val startedAtMs: Long = SystemClock.elapsedRealtime()
        val languageCode: String = languageCodeOf(language)
        whisperJob = scope.launch {
            val result: NovaResult<String> = withContext(Dispatchers.Default) {
                WhisperEngine.transcribe(models.modelDir(spec), spec, samples, languageCode)
            }
            val latency: Long = SystemClock.elapsedRealtime() - startedAtMs
            whisperJob = null
            onResult(
                when (result) {
                    is NovaResult.Success ->
                        GoogleRecognizerBridge.Outcome(result.value.takeIf { it.isNotBlank() }, null, latency)
                    is NovaResult.Failure ->
                        GoogleRecognizerBridge.Outcome(null, result.error, latency)
                }
            )
        }
    }

    // "" lets Whisper detect the language itself (used for mixed Bangla and English).
    private fun languageCodeOf(language: AppLanguage): String = when (language) {
        AppLanguage.BANGLA -> "bn"
        AppLanguage.ENGLISH -> "en"
        AppLanguage.MIXED -> ""
    }

    private fun failure(code: ErrorCode, message: String): GoogleRecognizerBridge.Outcome =
        GoogleRecognizerBridge.Outcome(text = null, error = NovaError(code, message), latencyMs = 0L)

    private companion object {
        const val MSG_MODEL_MISSING: String =
            "Whisper মডেল ফোনে নেই। \"অফলাইন মডেল\" কার্ড থেকে নামাও।"
    }
}
