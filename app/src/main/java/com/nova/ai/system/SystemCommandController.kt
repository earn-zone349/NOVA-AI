package com.nova.ai.system

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.voice.LanguageDetector

/**
 * Screen-side holder for system commands. Home gives it every command;
 * it acts only on commands that ask for a system action and keeps the
 * last [state] for the screen to show. Use from the main thread.
 */
class SystemCommandController(context: Context) {

    private val executor = SystemActionExecutor(context)
    private val brain = RuleBasedBrain()

    /** The last system action result, or null when there is nothing to show. */
    var state: SystemActionOutcome? by mutableStateOf<SystemActionOutcome?>(null)
        private set

    /** Looks at [text]; if it asks for a system action, carries it out. */
    fun handleCommand(text: String) {
        val intent: NovaIntent? = analyze(text)
        if (intent == null || intent.type != IntentType.SYSTEM_ACTION) {
            state = null
            return
        }
        state = executor.execute(intent)
    }

    /** Opens the screen where the user allows brightness changes. */
    fun openBrightnessPermission() {
        state = executor.openBrightnessPermission()
    }

    /** Hides the result card. */
    fun dismiss() {
        state = null
    }

    /** Releases listeners. Call when the screen is gone. */
    fun release() {
        executor.release()
    }

    private fun analyze(text: String): NovaIntent? {
        if (text.isBlank()) return null
        val command = VoiceCommand(
            rawText = text,
            language = LanguageDetector.detect(text),
            timestampMs = System.currentTimeMillis()
        )
        return (brain.analyze(command, emptyList()) as? NovaResult.Success)?.value
    }
}
