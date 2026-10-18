package com.nova.ai.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/** Plays a short recorded clip (16 kHz, mono) so the user can hear what the microphone caught. */
class ClipPlayer {

    private var track: AudioTrack? = null

    /** Starts playing [samples]. Returns the length of the clip in milliseconds. */
    @Synchronized
    fun play(samples: ShortArray): NovaResult<Long> {
        if (samples.isEmpty()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, "শোনানোর মতো রেকর্ড নেই।")
        }
        stop()

        return try {
            val sizeBytes: Int = samples.size * AudioConfig.BYTES_PER_SAMPLE
            val created: AudioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(AudioConfig.SAMPLE_RATE_HZ)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(sizeBytes)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()

            val written: Int = created.write(samples, 0, samples.size)
            if (written != samples.size) {
                created.release()
                return NovaResult.failure(ErrorCode.EXECUTION_FAILED, "রেকর্ড বাজাতে সমস্যা হয়েছে।")
            }
            created.play()
            track = created
            NovaResult.Success(samples.size * MILLIS_PER_SECOND / AudioConfig.SAMPLE_RATE_HZ)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to play the clip", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "রেকর্ড বাজাতে সমস্যা হয়েছে।", e)
        }
    }

    /** Stops playing and frees the player. Safe to call at any time. */
    @Synchronized
    fun stop() {
        val current: AudioTrack = track ?: return
        track = null
        try {
            current.stop()
        } catch (e: IllegalStateException) {
            NovaLogger.w(TAG, "Player was already stopped", e)
        }
        try {
            current.release()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to release the player", e)
        }
    }

    private companion object {
        const val TAG: String = "ClipPlayer"
        const val MILLIS_PER_SECOND: Long = 1000L
    }
}
