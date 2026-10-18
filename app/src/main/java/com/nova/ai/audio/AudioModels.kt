package com.nova.ai.audio

import android.media.MediaRecorder

/** How the microphone is opened. */
enum class CaptureProfile(val audioSource: Int) {
    /** Plain voice with no extra processing: best for speech recognition. */
    CLEAN(MediaRecorder.AudioSource.VOICE_RECOGNITION),

    /** Echo and noise reduction switched on: for talking while NOVA is speaking. */
    ECHO_SAFE(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
}

/** State of one sound-improving feature of the phone. */
enum class EffectState {
    /** This phone does not have the feature. */
    UNAVAILABLE,

    /** The phone has it, but it is not switched on. */
    AVAILABLE_OFF,

    /** Switched on. */
    ON
}

/** Which sound-improving features of the phone are available and on. */
data class AudioEffectsStatus(
    val echoCancel: EffectState,
    val noiseSuppress: EffectState,
    val autoGain: EffectState
) {
    companion object {
        val UNKNOWN: AudioEffectsStatus = AudioEffectsStatus(
            EffectState.UNAVAILABLE,
            EffectState.UNAVAILABLE,
            EffectState.UNAVAILABLE
        )
    }
}
