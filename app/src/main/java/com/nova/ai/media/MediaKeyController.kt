package com.nova.ai.media

import android.content.Context
import android.media.AudioManager
import android.view.KeyEvent
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * Sends play, pause, next and previous to whatever app is playing now
 * (Spotify, YouTube Music, the phone's music player). No permission needed.
 */
class MediaKeyController(context: Context) {

    /** The media buttons NOVA can press. */
    enum class Key(val code: Int) {
        PLAY(KeyEvent.KEYCODE_MEDIA_PLAY),
        PAUSE(KeyEvent.KEYCODE_MEDIA_PAUSE),
        NEXT(KeyEvent.KEYCODE_MEDIA_NEXT),
        PREVIOUS(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
    }

    private val audioManager: AudioManager? =
        context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    /** True while some app is playing music or video sound. */
    fun isMediaPlaying(): Boolean = try {
        audioManager?.isMusicActive == true
    } catch (e: Exception) {
        NovaLogger.e(TAG, "Failed to check playback", e)
        false
    }

    /** Presses [key] (down and up) for the active media app. */
    fun send(key: Key): NovaResult<Unit> {
        val manager: AudioManager = audioManager
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, "ফোনের অডিও সিস্টেম পাওয়া যায়নি।")
        return try {
            manager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, key.code))
            manager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, key.code))
            NovaResult.Success(Unit)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to send media key", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "গানের নির্দেশ পাঠাতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "MediaKeyController"
    }
}
