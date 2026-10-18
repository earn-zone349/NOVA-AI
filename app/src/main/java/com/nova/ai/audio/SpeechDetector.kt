package com.nova.ai.audio

import android.os.Handler
import android.os.Looper
import com.nova.ai.logging.NovaLogger

/**
 * Connects the speech segmenter to the live microphone: it listens to every frame
 * of an [AudioCaptureEngine] and tells a [Listener] when speech starts and ends.
 * Events reach the listener on the main thread. Sound is never saved or logged.
 */
class SpeechDetector(
    private val engine: AudioCaptureEngine,
    config: VadConfig = VadConfig()
) {

    /** Receives speech events on the main thread. */
    interface Listener {
        fun onSpeechStarted()
        fun onSpeechEnded(segment: SpeechSegment)
        fun onSpeechDiscarded(durationMs: Long)
    }

    private val segmenter = SpeechSegmenter(config)
    private val mainHandler: Handler = Handler(Looper.getMainLooper())

    @Volatile
    private var listener: Listener? = null

    /** Starts watching the microphone. Call after the engine has started. */
    fun attach(newListener: Listener) {
        segmenter.reset()
        listener = newListener
        engine.setFrameConsumer { frame, count -> onFrame(frame, count) }
    }

    /**
     * Stops watching. Call after the engine has stopped. Speech that was still in
     * progress is delivered as a last piece.
     */
    fun detach() {
        engine.setFrameConsumer(null)
        val lastEvent: SpeechEvent? = segmenter.flush()
        val current: Listener? = listener
        listener = null
        segmenter.reset()
        if (lastEvent != null && current != null) deliver(lastEvent, current)
    }

    /** Applies new settings from the next frame on. */
    fun updateConfig(newConfig: VadConfig) {
        segmenter.config = newConfig
    }

    /** The room noise level now, in dBFS. */
    fun noiseFloorDb(): Float = segmenter.noiseFloorDb

    /** True while speech is being collected. */
    fun isSpeaking(): Boolean = segmenter.isSpeaking

    // Runs on the capture thread for every frame.
    private fun onFrame(frame: ShortArray, count: Int) {
        val current: Listener = listener ?: return
        val event: SpeechEvent = try {
            segmenter.process(frame, count)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Speech detection failed on a frame", e)
            null
        } ?: return
        deliver(event, current)
    }

    private fun deliver(event: SpeechEvent, target: Listener) {
        mainHandler.post {
            try {
                when (event) {
                    is SpeechEvent.Started -> target.onSpeechStarted()
                    is SpeechEvent.Ended -> target.onSpeechEnded(event.segment)
                    is SpeechEvent.Discarded -> target.onSpeechDiscarded(event.durationMs)
                }
            } catch (e: Exception) {
                NovaLogger.e(TAG, "Speech listener failed", e)
            }
        }
    }

    private companion object {
        const val TAG: String = "SpeechDetector"
    }
}
