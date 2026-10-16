#!/usr/bin/env bash
# NOVA AI - Phase 8 fix: retry on temporary voice-service problems.
# Additive: previous behavior is kept; only recovery logic is added.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
CORE_FILE="$BASE/core/NovaResult.kt"

if [ ! -f "$BASE/voice/ConversationController.kt" ] || [ ! -f "$CORE_FILE" ]; then
  echo "ERROR: Run from repo root after P8 is installed." >&2
  exit 1
fi

# ---------- A. ErrorCode: add TEMPORARY_FAILURE (idempotent) ----------
if ! grep -q "TEMPORARY_FAILURE" "$CORE_FILE"; then
  sed -i 's/^    EXECUTION_FAILED$/    EXECUTION_FAILED,\n    TEMPORARY_FAILURE/' "$CORE_FILE"
fi
grep -q "TEMPORARY_FAILURE" "$CORE_FILE" || { echo "ERROR: ErrorCode edit failed" >&2; exit 1; }

# ---------- 1. SpeechErrorMapper.kt (previous messages kept; temporary errors tagged) ----------
cat > "$BASE/voice/SpeechErrorMapper.kt" <<'EOF'
package com.nova.ai.voice

import android.speech.SpeechRecognizer
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaError

/**
 * Converts Android speech-recognizer error numbers into [NovaError] with a Bangla message.
 * Short-lived service problems get [ErrorCode.TEMPORARY_FAILURE] so the conversation
 * can retry instead of giving up.
 */
internal object SpeechErrorMapper {

    fun toNovaError(speechError: Int): NovaError {
        val mapped: Pair<ErrorCode, String> = when (speechError) {
            SpeechRecognizer.ERROR_AUDIO ->
                ErrorCode.NOT_AVAILABLE to "অডিও রেকর্ড করতে সমস্যা হয়েছে।"
            SpeechRecognizer.ERROR_CLIENT ->
                ErrorCode.TEMPORARY_FAILURE to "ভয়েস সিস্টেমে ছোট একটি সমস্যা হয়েছে। আবার চেষ্টা করো।"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                ErrorCode.PERMISSION_DENIED to "মাইক্রোফোনের অনুমতি নেই।"
            SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                ErrorCode.NOT_AVAILABLE to "ইন্টারনেট সমস্যা। এই ভাষার অফলাইন ভয়েস নাও থাকতে পারে।"
            SpeechRecognizer.ERROR_NO_MATCH ->
                ErrorCode.NOT_FOUND to "কথা বোঝা যায়নি। আবার পরিষ্কার করে বলো।"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                ErrorCode.TIMEOUT to "কিছু শোনা যায়নি। আবার চেষ্টা করো।"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY ->
                ErrorCode.TEMPORARY_FAILURE to "ভয়েস সিস্টেম ব্যস্ত আছে। একটু পরে চেষ্টা করো।"
            SpeechRecognizer.ERROR_SERVER, SpeechRecognizer.ERROR_SERVER_DISCONNECTED ->
                ErrorCode.TEMPORARY_FAILURE to "ভয়েস সার্ভিসে সমস্যা হয়েছে। আবার চেষ্টা করো।"
            SpeechRecognizer.ERROR_TOO_MANY_REQUESTS ->
                ErrorCode.TEMPORARY_FAILURE to "অনেকবার চেষ্টা হয়েছে। একটু পরে আবার চেষ্টা করো।"
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

# ---------- 2. ConversationController.kt (P8 behavior kept; retry logic added) ----------
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
 * - Short-lived voice-service problems are retried (up to [MAX_GLITCH_RETRIES]
 *   times in a row) with a growing wait, instead of ending the conversation.
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
    private var glitchCount: Int = 0
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
        glitchCount = 0
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
        // A real command proves the voice service works, so clear both counters.
        missCount = 0
        glitchCount = 0

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
        // Single-turn mode: any problem ends the turn.
        if (!continuousProvider()) {
            finish(ConversationEnd.Failed(error))
            return
        }

        when (error.code) {
            ErrorCode.TIMEOUT, ErrorCode.NOT_FOUND -> {
                missCount += 1
                if (missCount >= MAX_CONSECUTIVE_MISSES) {
                    finish(ConversationEnd.SilenceTimeout)
                } else {
                    scheduleRestart(RESTART_DELAY_MS)
                }
            }
            ErrorCode.TEMPORARY_FAILURE -> {
                glitchCount += 1
                if (glitchCount > MAX_GLITCH_RETRIES) {
                    NovaLogger.w(TAG, "Giving up after $MAX_GLITCH_RETRIES retries")
                    finish(ConversationEnd.Failed(error))
                } else {
                    val waitMs: Long = GLITCH_RETRY_BASE_MS * glitchCount
                    NovaLogger.w(TAG, "Voice service glitch, retry $glitchCount in $waitMs ms")
                    scheduleRestart(waitMs)
                }
            }
            else -> finish(ConversationEnd.Failed(error))
        }
    }

    private fun continueOrFinish() {
        if (!active) return
        if (continuousProvider()) {
            scheduleRestart(RESTART_DELAY_MS)
        } else {
            finish(ConversationEnd.SingleCompleted)
        }
    }

    private fun scheduleRestart(delayMs: Long) {
        if (!active) return
        cancelRestart()
        setState(ConversationState.WAITING)
        val task = Runnable { restartListening() }
        restartTask = task
        handler.postDelayed(task, delayMs)
    }

    private fun restartListening() {
        restartTask = null
        if (!active) return
        val result: NovaResult<Unit> = beginListening()
        if (result is NovaResult.Failure) {
            // Starting can fail for a short moment too (recognizer busy); retry the same way.
            handleError(result.error)
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
        const val MAX_GLITCH_RETRIES: Int = 3
        const val RESTART_DELAY_MS: Long = 800L
        const val GLITCH_RETRY_BASE_MS: Long = 1200L
    }
}
EOF

# ---------- Commit and push ----------
git add -A
git commit -m "P8 fix: retry listening after temporary voice service problems"
git push

echo "P8 fix created and pushed."
