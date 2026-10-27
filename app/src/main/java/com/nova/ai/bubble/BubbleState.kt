package com.nova.ai.bubble

import com.nova.ai.voice.ConversationState

/** What the floating bubble shows. */
internal enum class BubbleState {
    /** Waiting for a tap. */
    IDLE,

    /** The microphone is open. */
    LISTENING,

    /** NOVA is speaking. */
    SPEAKING,

    /** A command was heard and is being carried out. */
    THINKING,

    /** The emergency stop is on. */
    STOPPED
}

/** Decides the bubble state from what the rest of the app is doing. */
internal object BubbleStateMapper {

    /** The emergency stop wins over everything; then speaking, listening and working. */
    fun map(emergencyActive: Boolean, conversation: ConversationState, routing: Boolean): BubbleState = when {
        emergencyActive -> BubbleState.STOPPED
        conversation == ConversationState.SPEAKING -> BubbleState.SPEAKING
        conversation == ConversationState.LISTENING || conversation == ConversationState.WAITING ->
            BubbleState.LISTENING
        routing -> BubbleState.THINKING
        else -> BubbleState.IDLE
    }

    /** The red stop badge is shown while NOVA is busy. */
    fun showsStopBadge(state: BubbleState): Boolean = when (state) {
        BubbleState.LISTENING, BubbleState.SPEAKING, BubbleState.THINKING -> true
        BubbleState.IDLE, BubbleState.STOPPED -> false
    }
}
