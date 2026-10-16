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
