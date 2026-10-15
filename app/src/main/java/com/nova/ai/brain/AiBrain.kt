package com.nova.ai.brain

import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand

/** Understands user commands and turns them into structured intents. */
interface AiBrain {
    /**
     * Analyzes [command] using [recentContext] (previous commands, oldest first)
     * so follow-up commands like "now search that" can be understood.
     */
    fun analyze(
        command: VoiceCommand,
        recentContext: List<VoiceCommand>
    ): NovaResult<NovaIntent>
}
