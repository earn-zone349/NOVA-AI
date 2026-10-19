package com.nova.ai.ui.components

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.nova.ai.R
import com.nova.ai.audio.AudioEffectsStatus
import com.nova.ai.audio.CaptureProfile
import com.nova.ai.audio.EffectState
import com.nova.ai.audio.GoogleRecognizerBridge
import com.nova.ai.audio.LabPhase
import com.nova.ai.audio.MicLabController
import com.nova.ai.audio.PauseTolerance
import com.nova.ai.audio.RecognitionStatus
import com.nova.ai.audio.SegmentEnd
import com.nova.ai.audio.Utterance
import com.nova.ai.audio.VadSensitivity
import com.nova.ai.settings.AppLanguage
import com.nova.ai.time.TimeText
import com.nova.ai.ui.theme.LocalAppSettings
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope

/**
 * Test card for the new listening engine: switch the microphone on, watch the
 * level move, compare the two microphone types, record and replay 5 seconds,
 * see how the engine cuts your speech into pieces, and send each piece to
 * Google's recognizer to get the text.
 * The microphone closes when the app goes to the background or the screen is left.
 */
@Composable
fun MicLabCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val scope: CoroutineScope = rememberCoroutineScope()
    val settings = LocalAppSettings.current
    val currentLanguage: AppLanguage by rememberUpdatedState(settings.language)
    val controller: MicLabController = remember {
        MicLabController(context, scope) { currentLanguage }
    }

    val lifecycleOwner: LifecycleOwner? = context as? LifecycleOwner
    DisposableEffect(lifecycleOwner, controller) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) controller.stop()
        }
        lifecycleOwner?.lifecycle?.addObserver(observer)
        onDispose {
            lifecycleOwner?.lifecycle?.removeObserver(observer)
            controller.release()
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted: Boolean ->
        if (granted) controller.start() else controller.reportPermissionDenied()
    }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.mic_lab_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.mic_lab_note),
                style = MaterialTheme.typography.bodySmall
            )

            Button(
                onClick = {
                    if (controller.isRunning) {
                        controller.stop()
                    } else {
                        val micGranted: Boolean = ContextCompat.checkSelfPermission(
                            context, Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                        if (micGranted) {
                            controller.start()
                        } else {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    stringResource(
                        if (controller.isRunning) R.string.mic_lab_stop else R.string.mic_lab_start
                    )
                )
            }

            if (controller.isRunning) {
                Text(
                    text = stringResource(R.string.mic_lab_level),
                    style = MaterialTheme.typography.bodySmall
                )
                LinearProgressIndicator(
                    progress = { controller.meterLevel },
                    modifier = Modifier.fillMaxWidth()
                )
                controller.effects?.let { status ->
                    Text(
                        text = effectsLine(status),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                if (controller.silentWarning) {
                    Text(
                        text = stringResource(R.string.mic_lab_silent),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }

            NovaChoiceGroup(
                title = stringResource(R.string.mic_lab_profile_title),
                options = CaptureProfile.values().toList(),
                selected = controller.profile,
                labelOf = { profileLabel(it) },
                onSelected = { controller.selectProfile(it) }
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { controller.recordClip() },
                    enabled = controller.isRunning && controller.phase == LabPhase.IDLE,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        stringResource(
                            if (controller.phase == LabPhase.RECORDING) {
                                R.string.mic_lab_recording
                            } else {
                                R.string.mic_lab_record
                            }
                        )
                    )
                }
                OutlinedButton(
                    onClick = { controller.playClip() },
                    enabled = controller.clipSeconds > 0 && controller.phase == LabPhase.IDLE,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        stringResource(
                            if (controller.phase == LabPhase.PLAYING && controller.playingUtteranceId == null) {
                                R.string.mic_lab_playing
                            } else {
                                R.string.mic_lab_play
                            }
                        )
                    )
                }
            }

            if (controller.clipSeconds > 0) {
                Text(
                    text = stringResource(R.string.mic_lab_clip_ready, controller.clipSeconds),
                    style = MaterialTheme.typography.bodySmall
                )
            }

            DetectionSection(controller)
            RecognitionSection(controller)
            UtteranceListSection(controller)

            controller.errorMessage?.let { message ->
                Text(
                    text = stringResource(R.string.mic_lab_error, message),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }
        }
    }
}

/** The speech detection part: live state and settings. */
@Composable
private fun ColumnScope.DetectionSection(controller: MicLabController) {
    Text(
        text = stringResource(R.string.vad_title),
        style = MaterialTheme.typography.titleMedium
    )
    Text(
        text = stringResource(R.string.vad_note),
        style = MaterialTheme.typography.bodySmall
    )

    if (controller.isRunning) {
        Text(
            text = stringResource(
                if (controller.speaking) R.string.vad_status_speaking else R.string.vad_status_quiet
            ),
            style = MaterialTheme.typography.titleMedium
        )
        Text(
            text = stringResource(R.string.vad_noise, controller.noiseFloorDb.roundToInt()),
            style = MaterialTheme.typography.bodySmall
        )
    }

    NovaChoiceGroup(
        title = stringResource(R.string.vad_sensitivity_title),
        options = VadSensitivity.values().toList(),
        selected = controller.sensitivity,
        labelOf = { sensitivityLabel(it) },
        onSelected = { controller.selectSensitivity(it) }
    )

    NovaChoiceGroup(
        title = stringResource(R.string.vad_pause_title),
        options = PauseTolerance.values().toList(),
        selected = controller.pause,
        labelOf = { pauseLabel(it) },
        onSelected = { controller.selectPause(it) }
    )

    Text(
        text = stringResource(R.string.vad_count, controller.detectedCount, controller.discardedCount),
        style = MaterialTheme.typography.bodyMedium
    )
}

/** The Google recognition part: support status, automatic sending and the chosen service. */
@Composable
private fun ColumnScope.RecognitionSection(controller: MicLabController) {
    Text(
        text = stringResource(R.string.rec_title),
        style = MaterialTheme.typography.titleMedium
    )
    Text(
        text = stringResource(R.string.rec_note),
        style = MaterialTheme.typography.bodySmall
    )
    Text(
        text = stringResource(R.string.rec_privacy),
        style = MaterialTheme.typography.bodySmall
    )
    Text(
        text = stringResource(
            if (controller.feedSupported) R.string.rec_support_ok else R.string.rec_support_no
        ),
        style = MaterialTheme.typography.bodySmall
    )
    Text(
        text = stringResource(
            if (controller.onDeviceAvailable) R.string.rec_ondevice_yes else R.string.rec_ondevice_no
        ),
        style = MaterialTheme.typography.bodySmall
    )

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = stringResource(R.string.rec_auto_label),
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f)
        )
        Switch(
            checked = controller.autoRecognize,
            onCheckedChange = { controller.updateAutoRecognize(it) },
            enabled = controller.feedSupported
        )
    }

    NovaChoiceGroup(
        title = stringResource(R.string.rec_engine_title),
        options = GoogleRecognizerBridge.Service.values().toList(),
        selected = controller.recognitionService,
        labelOf = { serviceLabel(it) },
        onSelected = { controller.selectRecognitionService(it) }
    )

    WhisperEngineSection()
}

/** The list of detected pieces of speech, each with replay and recognition result. */
@Composable
private fun ColumnScope.UtteranceListSection(controller: MicLabController) {
    if (controller.utterances.isEmpty()) {
        Text(
            text = stringResource(R.string.vad_empty),
            style = MaterialTheme.typography.bodySmall
        )
        return
    }
    Text(
        text = stringResource(R.string.vad_list_title),
        style = MaterialTheme.typography.titleMedium
    )
    controller.utterances.forEach { item ->
        key(item.id) { UtteranceRow(controller, item) }
    }
}

@Composable
private fun UtteranceRow(controller: MicLabController, item: Utterance) {
    val seconds: String = formatSeconds(item.durationMs)
    val cutNote: String =
        if (item.endReason == SegmentEnd.MAX_LENGTH) stringResource(R.string.vad_reason_max) else ""
    val isPlayingThis: Boolean =
        controller.phase == LabPhase.PLAYING && controller.playingUtteranceId == item.id

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = stringResource(R.string.vad_item, item.id, seconds) + cutNote,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f)
            )
            OutlinedButton(
                onClick = { controller.playUtterance(item.id) },
                enabled = controller.phase == LabPhase.IDLE
            ) {
                Text(
                    stringResource(
                        if (isPlayingThis) R.string.vad_item_playing else R.string.vad_item_play
                    )
                )
            }
        }

        when (val status = item.recognition) {
            is RecognitionStatus.NotSent -> {
                OutlinedButton(
                    onClick = { controller.recognize(item.id) },
                    enabled = controller.feedSupported
                ) {
                    Text(stringResource(R.string.rec_send))
                }
            }
            is RecognitionStatus.Sending -> {
                Text(
                    text = stringResource(R.string.rec_sending),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            is RecognitionStatus.Done -> {
                Text(
                    text = stringResource(R.string.rec_result, status.text, formatSeconds(status.latencyMs)),
                    style = MaterialTheme.typography.bodyMedium
                )
                OutlinedButton(onClick = { controller.recognize(item.id) }) {
                    Text(stringResource(R.string.rec_resend))
                }
            }
            is RecognitionStatus.Failed -> {
                Text(
                    text = stringResource(R.string.rec_failed, status.message, formatSeconds(status.latencyMs)),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
                OutlinedButton(onClick = { controller.recognize(item.id) }) {
                    Text(stringResource(R.string.rec_resend))
                }
            }
        }
    }
}

/** For example 3200 gives "৩.২" (Bangla digits, one decimal). */
private fun formatSeconds(milliseconds: Long): String =
    TimeText.digits(String.format(Locale.US, "%.1f", milliseconds / 1000f))

@Composable
private fun profileLabel(profile: CaptureProfile): String = stringResource(
    when (profile) {
        CaptureProfile.CLEAN -> R.string.mic_lab_profile_clean
        CaptureProfile.ECHO_SAFE -> R.string.mic_lab_profile_echo
    }
)

@Composable
private fun sensitivityLabel(value: VadSensitivity): String = stringResource(
    when (value) {
        VadSensitivity.HIGH -> R.string.vad_sens_high
        VadSensitivity.NORMAL -> R.string.vad_sens_normal
        VadSensitivity.LOW -> R.string.vad_sens_low
    }
)

@Composable
private fun pauseLabel(value: PauseTolerance): String = stringResource(
    when (value) {
        PauseTolerance.SHORT -> R.string.vad_pause_short
        PauseTolerance.NORMAL -> R.string.vad_pause_normal
        PauseTolerance.LONG -> R.string.vad_pause_long
    }
)

@Composable
private fun serviceLabel(service: GoogleRecognizerBridge.Service): String = stringResource(
    when (service) {
        GoogleRecognizerBridge.Service.ONLINE -> R.string.rec_engine_online
        GoogleRecognizerBridge.Service.ON_DEVICE -> R.string.rec_engine_on_device
    }
)

@Composable
private fun effectsLine(status: AudioEffectsStatus): String = stringResource(
    R.string.mic_lab_effects,
    effectLabel(status.echoCancel),
    effectLabel(status.noiseSuppress),
    effectLabel(status.autoGain)
)

@Composable
private fun effectLabel(state: EffectState): String = stringResource(
    when (state) {
        EffectState.ON -> R.string.mic_lab_effect_on
        EffectState.AVAILABLE_OFF -> R.string.mic_lab_effect_off
        EffectState.UNAVAILABLE -> R.string.mic_lab_effect_none
    }
)
