package com.nova.ai.voice

import com.nova.ai.core.Language
import com.nova.ai.core.NovaError
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand

/** Receives events from the [VoiceEngine]. */
interface VoiceListener {
    fun onListeningStarted()
    fun onPartialText(text: String)
    fun onFinalCommand(command: VoiceCommand)
    fun onError(error: NovaError)
}

/** Voice input (speech to text) and output (text to speech). */
interface VoiceEngine {
    /** Starts listening; results arrive through [listener]. */
    fun startListening(listener: VoiceListener): NovaResult<Unit>

    /** Stops listening immediately. */
    fun stopListening()

    /** Speaks [text] aloud in the given [language]. */
    fun speak(text: String, language: Language): NovaResult<Unit>

    /** True while the microphone is active. */
    fun isListening(): Boolean

    /** Releases microphone and speech resources. */
    fun shutdown()
}
