package com.nova.ai.ui.screens

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.core.Language
import com.nova.ai.core.NovaResult
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.SpeechSpeed
import com.nova.ai.settings.ThemeMode
import com.nova.ai.ui.components.NovaChoiceGroup
import com.nova.ai.ui.components.MicLabCard
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout
import com.nova.ai.ui.components.languageLabel
import com.nova.ai.ui.components.speechSpeedLabel
import com.nova.ai.ui.components.themeModeLabel
import com.nova.ai.ui.theme.LocalAppSettings
import com.nova.ai.voice.AndroidVoiceEngine

/** AI Brain: model status, memory use, offline status, language, appearance and voice reply. */
@Composable
fun AiBrainScreen(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val settings = LocalAppSettings.current
    val currentLanguage: AppLanguage by rememberUpdatedState(settings.language)
    val currentSpeed: SpeechSpeed by rememberUpdatedState(settings.speechSpeed)

    var testMessage: String by remember { mutableStateOf("") }

    // Voice engine used only for the "test voice" button; released when the screen leaves.
    val voiceEngine: AndroidVoiceEngine = remember {
        AndroidVoiceEngine(
            context = context,
            languageProvider = { currentLanguage },
            speechRateProvider = { currentSpeed.rate }
        )
    }
    DisposableEffect(voiceEngine) {
        voiceEngine.setSpeechProblemListener { error ->
            testMessage = context.getString(R.string.brain_voice_problem, error.message)
        }
        onDispose {
            voiceEngine.setSpeechProblemListener(null)
            voiceEngine.shutdown()
        }
    }

    val testSentenceBangla: String = stringResource(R.string.brain_voice_test_bn)
    val testSentenceEnglish: String = stringResource(R.string.brain_voice_test_en)

    NovaScreenLayout(
        title = stringResource(R.string.brain_title),
        subtitle = stringResource(R.string.brain_subtitle),
        modifier = modifier
    ) {
        NovaInfoCard(
            title = stringResource(R.string.brain_model_title),
            body = stringResource(R.string.brain_model_none)
        )
        NovaInfoCard(
            title = stringResource(R.string.brain_ram_title),
            body = stringResource(R.string.brain_ram_none)
        )
        NovaInfoCard(
            title = stringResource(R.string.brain_offline_title),
            body = stringResource(R.string.brain_offline_body)
        )
        NovaInfoCard(
            title = stringResource(R.string.brain_language_title),
            body = stringResource(R.string.brain_language_body)
        )

        MicLabCard()

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                NovaChoiceGroup(
                    title = stringResource(R.string.settings_language_title),
                    options = AppLanguage.values().toList(),
                    selected = settings.language,
                    labelOf = { languageLabel(it) },
                    onSelected = settings.onLanguageChange
                )
                NovaChoiceGroup(
                    title = stringResource(R.string.settings_theme_title),
                    options = ThemeMode.values().toList(),
                    selected = settings.themeMode,
                    labelOf = { themeModeLabel(it) },
                    onSelected = settings.onThemeModeChange
                )
            }
        }

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.brain_voice_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = stringResource(R.string.brain_voice_reply_label),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Switch(
                        checked = settings.voiceReplyEnabled,
                        onCheckedChange = settings.onVoiceReplyChange
                    )
                }
                NovaChoiceGroup(
                    title = stringResource(R.string.brain_voice_speed_title),
                    options = SpeechSpeed.values().toList(),
                    selected = settings.speechSpeed,
                    labelOf = { speechSpeedLabel(it) },
                    onSelected = settings.onSpeechSpeedChange
                )
                Button(
                    onClick = {
                        testMessage = ""
                        val useEnglish: Boolean = settings.language == AppLanguage.ENGLISH
                        val sentence: String =
                            if (useEnglish) testSentenceEnglish else testSentenceBangla
                        val spoken: Language =
                            if (useEnglish) Language.ENGLISH else Language.BANGLA
                        val result: NovaResult<Unit> = voiceEngine.speak(sentence, spoken)
                        if (result is NovaResult.Failure) {
                            testMessage = context.getString(
                                R.string.brain_voice_problem,
                                result.error.message
                            )
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.brain_voice_test_button))
                }
                if (testMessage.isNotEmpty()) {
                    Text(text = testMessage, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
