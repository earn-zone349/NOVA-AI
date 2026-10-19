package com.nova.ai.audio

import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineWhisperModelConfig
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import com.nova.ai.models.WhisperModelSpec
import java.io.File

/**
 * Turns recorded speech into text with a Whisper model that runs inside the phone
 * (through the sherpa-onnx library). The model stays loaded between requests;
 * the first request is slower because of the loading. Sound and text are never logged.
 */
object WhisperEngine {

    private const val TAG: String = "WhisperEngine"
    private const val PCM_SCALE: Float = 32768f
    private const val MIN_THREADS: Int = 2
    private const val MAX_THREADS: Int = 4

    private var recognizer: OfflineRecognizer? = null
    private var loadedKey: String? = null

    /**
     * Converts [samples] (16 kHz, mono) to text. [languageCode] is "bn" for Bangla,
     * "en" for English, or "" to let the model detect the language.
     * Blocking and heavy: call from a background thread.
     */
    @Synchronized
    fun transcribe(
        modelDir: File,
        spec: WhisperModelSpec,
        samples: ShortArray,
        languageCode: String
    ): NovaResult<String> {
        if (samples.isEmpty()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, "শোনার মতো অডিও নেই।")
        }
        return try {
            val engine: OfflineRecognizer = obtain(modelDir, spec, languageCode)
            val floats = FloatArray(samples.size) { index -> samples[index] / PCM_SCALE }
            val stream = engine.createStream()
            try {
                stream.acceptWaveform(floats, AudioConfig.SAMPLE_RATE_HZ)
                engine.decode(stream)
                NovaResult.Success(engine.getResult(stream).text.trim())
            } finally {
                stream.release()
            }
        } catch (e: OutOfMemoryError) {
            NovaLogger.e(TAG, "Out of memory while running Whisper", e)
            releaseInternal()
            NovaResult.failure(
                ErrorCode.EXECUTION_FAILED,
                "ফোনের RAM কম পড়েছে। ছোট মডেল বেছে দেখো।",
                e
            )
        } catch (e: Throwable) {
            NovaLogger.e(TAG, "Whisper failed", e)
            releaseInternal()
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "Whisper চালাতে সমস্যা হয়েছে।", e)
        }
    }

    /** Frees the model from memory. It is loaded again when needed. */
    @Synchronized
    fun release() {
        releaseInternal()
    }

    private fun obtain(modelDir: File, spec: WhisperModelSpec, languageCode: String): OfflineRecognizer {
        val key = "${spec.id}|$languageCode"
        val existing: OfflineRecognizer? = recognizer
        if (existing != null && loadedKey == key) return existing

        releaseInternal()
        val whisper = OfflineWhisperModelConfig(
            encoder = File(modelDir, spec.encoderFile).absolutePath,
            decoder = File(modelDir, spec.decoderFile).absolutePath,
            language = languageCode,
            task = "transcribe"
        )
        val modelConfig = OfflineModelConfig(
            whisper = whisper,
            tokens = File(modelDir, spec.tokensFile).absolutePath,
            numThreads = threadCount(),
            debug = false
        )
        val created = OfflineRecognizer(config = OfflineRecognizerConfig(modelConfig = modelConfig))
        recognizer = created
        loadedKey = key
        return created
    }

    private fun releaseInternal() {
        try {
            recognizer?.release()
        } catch (e: Throwable) {
            NovaLogger.e(TAG, "Failed to release the model", e)
        } finally {
            recognizer = null
            loadedKey = null
        }
    }

    private fun threadCount(): Int =
        Runtime.getRuntime().availableProcessors().coerceIn(MIN_THREADS, MAX_THREADS)
}
