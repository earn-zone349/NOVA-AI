package com.nova.ai.audio

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Which recognizer turns speech into text. Held in memory for the test card;
 * the final conversation settings come in a later phase.
 */
object RecognitionRouting {

    private const val DEFAULT_WHISPER_MODEL: String = "small"

    /** True: use the offline Whisper model. False: use Google's recognizer. */
    var useWhisper: Boolean by mutableStateOf(false)

    /** The id of the Whisper model to use (see ModelCatalog). */
    var whisperModelId: String by mutableStateOf(DEFAULT_WHISPER_MODEL)
}
