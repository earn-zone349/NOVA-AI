package com.nova.ai.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.settings.SpeechSpeed

/** Display text for a [SpeechSpeed]. */
@Composable
fun speechSpeedLabel(speed: SpeechSpeed): String = stringResource(
    when (speed) {
        SpeechSpeed.SLOW -> R.string.settings_speed_slow
        SpeechSpeed.NORMAL -> R.string.settings_speed_normal
        SpeechSpeed.FAST -> R.string.settings_speed_fast
    }
)
