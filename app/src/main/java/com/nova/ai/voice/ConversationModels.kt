package com.nova.ai.voice

import com.nova.ai.core.Language
import com.nova.ai.core.NovaError
import com.nova.ai.core.VoiceCommand

/** What the conversation is doing right now. */
enum class ConversationState {
    /** No conversation running. */
    IDLE,

    /** Microphone is open and waiting for the user. */
    LISTENING,

    /** The app is speaking its reply. */
    SPEAKING,

    /** Short pause before listening again. */
    WAITING
}

/** Why a conversation ended. */
sealed class ConversationEnd {
    /** The user tapped stop (or the app went to the background). */
    object UserStopped : ConversationEnd()

    /** The user said a stop phrase such as "stop" or "থামো". */
    object StopPhrase : ConversationEnd()

    /** Nothing was heard several times in a row. */
    object SilenceTimeout : ConversationEnd()

    /** Continuous mode is off, so the single turn finished normally. */
    object SingleCompleted : ConversationEnd()

    /** A problem that cannot be recovered from automatically. */
    data class Failed(val error: NovaError) : ConversationEnd()
}

/** Text the app should speak after a command, and the language to use. */
data class SpokenReply(val text: String, val language: Language)

/** Receives conversation events. All calls happen on the main thread. */
interface ConversationListener {
    fun onStateChanged(state: ConversationState)
    fun onPartialText(text: String)
    fun onCommand(command: VoiceCommand)
    fun onEnded(reason: ConversationEnd)
}
