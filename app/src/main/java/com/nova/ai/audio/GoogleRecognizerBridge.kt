package com.nova.ai.audio

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaError
import com.nova.ai.logging.NovaLogger
import com.nova.ai.settings.AppLanguage
import com.nova.ai.voice.SpeechErrorMapper
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Sends our own recorded sound to Android's speech recognizer (Google's service)
 * instead of letting it open the microphone. The sound travels through a private
 * pipe; the recognizer reads it and returns the text. This needs Android 13 or newer,
 * and the recognizer service must support it (the test shows whether it does).
 *
 * One request at a time. Use from the main thread. Sound and text are never logged.
 */
class GoogleRecognizerBridge(
    context: Context,
    private val scope: CoroutineScope
) {

    /** Which recognizer service gets the sound. */
    enum class Service {
        /** Google's online service: the most accurate. The sound goes to Google's servers. */
        ONLINE,

        /** The recognizer inside the phone: works without internet if the language is installed. */
        ON_DEVICE
    }

    /** The result of one request: text, or an error, and how long it took. */
    data class Outcome(val text: String?, val error: NovaError?, val latencyMs: Long)

    private val appContext: Context = context.applicationContext
    private val handler: Handler = Handler(Looper.getMainLooper())
    private var activeSession: Session? = null

    /** True if this Android version can feed our own sound to the recognizer. */
    fun isFeedSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    /** True if the phone has an offline recognizer. */
    fun isOnDeviceAvailable(): Boolean = try {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(appContext)
    } catch (e: Exception) {
        NovaLogger.e(TAG, "Failed to check the offline recognizer", e)
        false
    }

    /** Sends [samples] (16 kHz, mono) to the chosen [service] and reports the result to [onResult]. */
    fun recognize(
        samples: ShortArray,
        service: Service,
        language: AppLanguage,
        onResult: (Outcome) -> Unit
    ) {
        cancel()

        if (!isFeedSupported()) {
            onResult(failure(ErrorCode.NOT_AVAILABLE, MSG_UNSUPPORTED_OS))
            return
        }
        if (samples.isEmpty()) {
            onResult(failure(ErrorCode.INVALID_INPUT, MSG_AUDIO_ERROR))
            return
        }

        val recognizer: SpeechRecognizer = createRecognizer(service) ?: run {
            onResult(failure(ErrorCode.NOT_AVAILABLE, MSG_NO_SERVICE))
            return
        }

        val pipe = try {
            ParcelFileDescriptor.createPipe()
        } catch (e: IOException) {
            NovaLogger.e(TAG, "Failed to create the audio pipe", e)
            destroyQuietly(recognizer)
            onResult(failure(ErrorCode.EXECUTION_FAILED, MSG_AUDIO_ERROR))
            return
        }

        val session = Session(recognizer, pipe[0], pipe[1], samples, onResult)
        activeSession = session
        session.begin(languageTagOf(language))
    }

    /** Stops the request in progress without reporting a result. */
    fun cancel() {
        activeSession?.abort()
        activeSession = null
    }

    private fun createRecognizer(service: Service): SpeechRecognizer? = try {
        when (service) {
            Service.ONLINE ->
                if (SpeechRecognizer.isRecognitionAvailable(appContext)) {
                    SpeechRecognizer.createSpeechRecognizer(appContext)
                } else {
                    null
                }
            Service.ON_DEVICE ->
                if (isOnDeviceAvailable()) {
                    SpeechRecognizer.createOnDeviceSpeechRecognizer(appContext)
                } else {
                    null
                }
        }
    } catch (e: Exception) {
        NovaLogger.e(TAG, "Failed to create the recognizer", e)
        null
    }

    private fun languageTagOf(language: AppLanguage): String = when (language) {
        AppLanguage.ENGLISH -> TAG_ENGLISH
        AppLanguage.BANGLA, AppLanguage.MIXED -> TAG_BANGLA
    }

    private fun failure(code: ErrorCode, message: String): Outcome =
        Outcome(text = null, error = NovaError(code, message), latencyMs = 0L)

    private fun destroyQuietly(recognizer: SpeechRecognizer) {
        try {
            recognizer.destroy()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to release the recognizer", e)
        }
    }

    private fun closeQuietly(descriptor: ParcelFileDescriptor) {
        try {
            descriptor.close()
        } catch (e: IOException) {
            NovaLogger.w(TAG, "Failed to close a pipe end", e)
        }
    }

    /** One request: the recognizer, the pipe, and the writer that feeds the sound. */
    private inner class Session(
        private val recognizer: SpeechRecognizer,
        private val readSide: ParcelFileDescriptor,
        private val writeSide: ParcelFileDescriptor,
        private val samples: ShortArray,
        private val onResult: (Outcome) -> Unit
    ) : RecognitionListener {

        private val startedAtMs: Long = SystemClock.elapsedRealtime()
        private var finished: Boolean = false
        private var writerJob: Job? = null
        private val timeoutTask = Runnable {
            complete(
                text = null,
                error = NovaError(ErrorCode.TIMEOUT, MSG_TIMEOUT),
                notify = true
            )
        }

        fun begin(languageTag: String) {
            recognizer.setRecognitionListener(this)
            val sendMs: Long = samples.size * 1000L / AudioConfig.SAMPLE_RATE_HZ
            handler.postDelayed(timeoutTask, TIMEOUT_BASE_MS + sendMs)

            try {
                recognizer.startListening(buildIntent(languageTag))
            } catch (e: Exception) {
                NovaLogger.e(TAG, "Failed to start the recognizer", e)
                complete(null, NovaError(ErrorCode.EXECUTION_FAILED, MSG_AUDIO_ERROR), notify = true)
                return
            }
            writerJob = scope.launch(Dispatchers.IO) { writeSound() }
        }

        /** Ends this request without reporting anything. */
        fun abort() {
            complete(text = null, error = null, notify = false)
        }

        private fun buildIntent(languageTag: String): Intent =
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, appContext.packageName)
                // These keys tell the recognizer to read our sound instead of the microphone.
                putExtra(KEY_AUDIO_SOURCE, readSide)
                putExtra(KEY_AUDIO_SAMPLING_RATE, AudioConfig.SAMPLE_RATE_HZ)
                putExtra(KEY_AUDIO_CHANNEL_COUNT, 1)
                putExtra(KEY_AUDIO_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            }

        // Runs on a background thread. Closing the stream tells the recognizer the sound is over.
        private fun writeSound() {
            try {
                ParcelFileDescriptor.AutoCloseOutputStream(writeSide).use { stream ->
                    stream.write(toBytes(samples))
                }
            } catch (e: IOException) {
                // Normal when the request ends early and the pipe is closed.
                NovaLogger.w(TAG, "Sound feed ended early", e)
            }
        }

        private fun toBytes(source: ShortArray): ByteArray {
            val padSamples: Int = AudioConfig.SAMPLE_RATE_HZ * SILENCE_PAD_MS / 1000
            val buffer: ByteBuffer = ByteBuffer
                .allocate((source.size + padSamples) * AudioConfig.BYTES_PER_SAMPLE)
                .order(ByteOrder.LITTLE_ENDIAN)
            buffer.asShortBuffer().put(source)
            // The bytes after the sound stay zero: a short quiet end helps the recognizer finish.
            return buffer.array()
        }

        private fun complete(text: String?, error: NovaError?, notify: Boolean) {
            if (finished) return
            finished = true

            handler.removeCallbacks(timeoutTask)
            writerJob?.cancel()
            closeQuietly(writeSide)
            closeQuietly(readSide)
            destroyQuietly(recognizer)
            if (activeSession === this) activeSession = null

            if (notify) {
                val latency: Long = SystemClock.elapsedRealtime() - startedAtMs
                onResult(Outcome(text, error, latency))
            }
        }

        override fun onResults(results: Bundle?) {
            val text: String? = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?.trim()
            complete(text = text, error = null, notify = true)
        }

        override fun onError(error: Int) {
            NovaLogger.w(TAG, "Recognizer error $error")
            complete(null, SpeechErrorMapper.toNovaError(error), notify = true)
        }

        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onPartialResults(partialResults: Bundle?) = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    private companion object {
        const val TAG: String = "GoogleRecognizerBridge"
        const val TAG_BANGLA: String = "bn-BD"
        const val TAG_ENGLISH: String = "en-US"

        // Keys of the Android 13 feature that feeds our own sound to the recognizer.
        const val KEY_AUDIO_SOURCE: String = "android.speech.extra.AUDIO_SOURCE"
        const val KEY_AUDIO_SAMPLING_RATE: String = "android.speech.extra.AUDIO_SOURCE_SAMPLING_RATE"
        const val KEY_AUDIO_CHANNEL_COUNT: String = "android.speech.extra.AUDIO_SOURCE_CHANNEL_COUNT"
        const val KEY_AUDIO_ENCODING: String = "android.speech.extra.AUDIO_SOURCE_ENCODING"

        const val SILENCE_PAD_MS: Int = 300
        const val TIMEOUT_BASE_MS: Long = 15_000L

        const val MSG_UNSUPPORTED_OS: String = "নিজের অডিও পাঠানোর জন্য Android 13 বা তার বেশি লাগে।"
        const val MSG_NO_SERVICE: String = "ফোনে এই ভয়েস চেনার সার্ভিস পাওয়া যায়নি।"
        const val MSG_AUDIO_ERROR: String = "অডিও পাঠাতে সমস্যা হয়েছে।"
        const val MSG_TIMEOUT: String =
            "সময় শেষ: Google সাড়া দেয়নি। হয়তো এই ফোনে নিজের অডিও সমর্থিত নয়।"
    }
}
