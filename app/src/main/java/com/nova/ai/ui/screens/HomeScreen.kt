package com.nova.ai.ui.screens

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.nova.ai.R
import com.nova.ai.apps.AppCommandController
import com.nova.ai.contacts.ContactCommandController
import com.nova.ai.core.Language
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.media.MediaCommandController
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.SpeechSpeed
import com.nova.ai.system.SystemCommandController
import com.nova.ai.time.TimeCommandController
import com.nova.ai.ui.components.AppActionCard
import com.nova.ai.ui.components.CommandInsightCard
import com.nova.ai.ui.components.ContactActionCard
import com.nova.ai.ui.components.IntentInsightCard
import com.nova.ai.ui.components.MediaActionCard
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.tasks.TaskHub
import com.nova.ai.ui.components.TaskQueueCard
import com.nova.ai.ui.components.NovaScreenLayout
import com.nova.ai.ui.components.SetupReminderCard
import com.nova.ai.ui.components.SystemActionCard
import com.nova.ai.ui.components.TimeActionCard
import com.nova.ai.ui.theme.LocalAppSettings
import com.nova.ai.voice.AndroidVoiceEngine
import com.nova.ai.voice.ConversationController
import com.nova.ai.voice.ConversationEnd
import com.nova.ai.voice.ConversationListener
import com.nova.ai.voice.ConversationState
import com.nova.ai.voice.SpokenReply
import com.nova.ai.voice.toSpeechLanguage
import com.nova.ai.voice.VoiceFocus
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.CoroutineScope

private const val TAG: String = "HomeScreen"
private const val TRANSCRIPT_LIMIT: Int = 5

/**
 * Home: voice button, command box, current status and running-task progress.
 * The mic button starts a conversation: the app listens, confirms by voice,
 * and (when continuous mode is on) listens again by itself until the user says
 * stop, stays silent, or leaves the screen. Every command also goes to the
 * controllers for opening apps, system actions, calls and messages, alarms and
 * timers, and music, search, navigation and camera.
 */
@Composable
fun HomeScreen(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val scope: CoroutineScope = rememberCoroutineScope()
    val settings = LocalAppSettings.current
    val currentLanguage: AppLanguage by rememberUpdatedState(settings.language)
    val currentSpeed: SpeechSpeed by rememberUpdatedState(settings.speechSpeed)
    val replyEnabled: Boolean by rememberUpdatedState(settings.voiceReplyEnabled)
    val continuousEnabled: Boolean by rememberUpdatedState(settings.continuousConversation)

    var commandText: String by rememberSaveable { mutableStateOf("") }
    var statusOverride: String by rememberSaveable { mutableStateOf("") }
    var conversationState: ConversationState by remember {
        mutableStateOf(ConversationState.IDLE)
    }
    var commandCount: Int by remember { mutableStateOf(0) }
    val transcript = remember { mutableStateListOf<String>() }

    val readyText: String = stringResource(R.string.home_status_ready)
    val idleText: String = stringResource(R.string.home_status_ready_voice)
    val receivedText: String = stringResource(R.string.home_status_command_received)
    val emptyText: String = stringResource(R.string.home_status_empty_command)
    val voiceDescription: String = stringResource(R.string.home_voice_button_desc)
    val stopDescription: String = stringResource(R.string.home_voice_stop_desc)

    // One voice engine per Home screen; released when the screen leaves.
    val voiceEngine: AndroidVoiceEngine = remember {
        AndroidVoiceEngine(
            context = context,
            languageProvider = { currentLanguage },
            speechRateProvider = { currentSpeed.rate }
        )
    }

    // Opens apps from commands, using the user's app library.
    val appController: AppCommandController = remember { AppCommandController(context, scope) }

    // Runs system commands: torch, volume, brightness, Wi-Fi and Bluetooth screens.
    val systemController: SystemCommandController = remember { SystemCommandController(context) }

    // Runs call and message commands, using the phone's contacts.
    val contactController: ContactCommandController = remember { ContactCommandController(context, scope) }

    // Sets alarms, timers and reminders in the phone's clock app.
    val timeController: TimeCommandController = remember { TimeCommandController(context) }

    // Runs music control, searches, navigation and camera commands.
    val mediaController: MediaCommandController = remember { MediaCommandController(context) }

    // Conversation events arrive on the main thread, so updating UI state here is safe.
    val conversation: ConversationController = remember {
        ConversationController(
            engine = voiceEngine,
            listener = object : ConversationListener {
                override fun onStateChanged(state: ConversationState) {
                    conversationState = state
                    when (state) {
                        ConversationState.LISTENING ->
                            statusOverride = listeningStatus(context, commandCount)
                        ConversationState.SPEAKING ->
                            statusOverride = context.getString(R.string.home_status_speaking)
                        ConversationState.WAITING ->
                            statusOverride = context.getString(R.string.home_status_next_turn)
                        ConversationState.IDLE -> Unit
                    }
                }

                override fun onPartialText(text: String) {
                    commandText = text
                }

                override fun onCommand(command: VoiceCommand) {
                    commandCount += 1
                    commandText = command.rawText
                    statusOverride = context.getString(R.string.home_status_heard, command.rawText)
                    transcript.add("$commandCount. ${command.rawText}")
                    while (transcript.size > TRANSCRIPT_LIMIT) transcript.removeAt(0)
                    // P23: a command with several parts ("... তারপর ...") runs as a task, step by step.
                    if (TaskHub.submitIfMultiStep(context, command.rawText)) return
                    appController.handleCommand(command.rawText)
                    systemController.handleCommand(command.rawText)
                    contactController.handleCommand(command.rawText)
                    timeController.handleCommand(command.rawText)
                    mediaController.handleCommand(command.rawText)
                }

                override fun onEnded(reason: ConversationEnd) {
                    when (reason) {
                        is ConversationEnd.UserStopped ->
                            statusOverride = context.getString(R.string.home_status_ended_user)
                        is ConversationEnd.StopPhrase -> {
                            statusOverride = context.getString(R.string.home_status_ended_phrase)
                            if (replyEnabled) {
                                val english: Boolean = currentLanguage == AppLanguage.ENGLISH
                                val ackRes: Int = if (english) {
                                    R.string.home_voice_stop_ack_en
                                } else {
                                    R.string.home_voice_stop_ack
                                }
                                voiceEngine.speak(
                                    context.getString(ackRes),
                                    currentLanguage.toSpeechLanguage()
                                )
                            }
                        }
                        is ConversationEnd.SilenceTimeout ->
                            statusOverride = context.getString(R.string.home_status_ended_silence)
                        is ConversationEnd.SingleCompleted ->
                            statusOverride =
                                context.getString(R.string.home_status_heard, commandText)
                        is ConversationEnd.Failed ->
                            statusOverride = context.getString(
                                R.string.home_voice_error,
                                reason.error.message
                            )
                    }
                }
            },
            continuousProvider = { continuousEnabled },
            replyProvider = { command ->
                if (replyEnabled) buildReply(context, command, currentLanguage) else null
            }
        )
    }

    // Release everything when the screen leaves, and close the microphone
    // whenever the app goes to the background.
    val lifecycleOwner: LifecycleOwner? = context as? LifecycleOwner
    DisposableEffect(lifecycleOwner, conversation) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) conversation.stop()
        }
        lifecycleOwner?.lifecycle?.addObserver(observer)
        // The bubble and the emergency stop stop this screen's voice through the shared registry.
        VoiceFocus.register("home") { Handler(Looper.getMainLooper()).post { conversation.stop() } }
        onDispose {
            lifecycleOwner?.lifecycle?.removeObserver(observer)
            VoiceFocus.unregister("home")
            conversation.shutdown()
            voiceEngine.shutdown()
            systemController.release()
        }
    }

    fun startConversation() {
        VoiceFocus.claim("home")
        commandCount = 0
        transcript.clear()
        when (val result: NovaResult<Unit> = conversation.start()) {
            is NovaResult.Success -> Unit
            is NovaResult.Failure -> {
                statusOverride = context.getString(R.string.home_voice_error, result.error.message)
                NovaLogger.w(TAG, "Conversation start failed: ${result.error.message}")
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted: Boolean ->
        if (granted) {
            startConversation()
        } else {
            statusOverride = context.getString(R.string.home_mic_permission_denied)
        }
    }

    val sessionActive: Boolean = conversationState != ConversationState.IDLE
    val currentStatus: String =
        if (statusOverride.isEmpty()) "$readyText\n$idleText" else statusOverride

    NovaScreenLayout(
        title = stringResource(R.string.home_title),
        subtitle = stringResource(R.string.home_subtitle),
        modifier = modifier
    ) {
        Box(
            modifier = Modifier.fillMaxWidth(),
            contentAlignment = Alignment.Center
        ) {
            val buttonDescription: String = if (sessionActive) stopDescription else voiceDescription
            Button(
                onClick = {
                    if (sessionActive) {
                        conversation.stop()
                    } else {
                        val micGranted: Boolean = ContextCompat.checkSelfPermission(
                            context, Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                        if (micGranted) {
                            startConversation()
                        } else {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    }
                },
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (sessionActive) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.primary
                    }
                ),
                modifier = Modifier
                    .size(120.dp)
                    .semantics { contentDescription = buttonDescription }
            ) {
                Text(text = if (sessionActive) "⏹️" else "🎙️", fontSize = 40.sp)
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = stringResource(R.string.home_continuous_label),
                style = MaterialTheme.typography.titleMedium
            )
            Switch(
                checked = settings.continuousConversation,
                onCheckedChange = settings.onContinuousChange
            )
        }
        Text(
            text = stringResource(R.string.home_continuous_hint),
            style = MaterialTheme.typography.bodySmall
        )

        NovaInfoCard(
            title = stringResource(R.string.home_status_label),
            body = currentStatus
        )

        OutlinedTextField(
            value = commandText,
            onValueChange = { commandText = it },
            label = { Text(stringResource(R.string.home_command_hint)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )

        Button(
            onClick = {
                if (commandText.isBlank()) {
                    statusOverride = emptyText
                } else {
                    statusOverride = receivedText
                    if (TaskHub.submitIfMultiStep(context, commandText)) return@Button
                    appController.handleCommand(commandText)
                    systemController.handleCommand(commandText)
                    contactController.handleCommand(commandText)
                    timeController.handleCommand(commandText)
                    mediaController.handleCommand(commandText)
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(stringResource(R.string.home_send))
        }

        AppActionCard(controller = appController)

        SetupReminderCard()

        SystemActionCard(controller = systemController)

        ContactActionCard(controller = contactController)

        TimeActionCard(controller = timeController)

        MediaActionCard(controller = mediaController)

        TaskQueueCard(showInput = false)

        CommandInsightCard(text = commandText)

        IntentInsightCard(text = commandText, history = transcript.toList())

        if (transcript.isNotEmpty()) {
            NovaInfoCard(
                title = stringResource(R.string.home_transcript_title),
                body = transcript.joinToString("\n")
            )
        }

        NovaInfoCard(
            title = stringResource(R.string.home_progress_title),
            body = stringResource(R.string.home_progress_none)
        )
    }
}

/** Status line while listening; shows how many commands this conversation has had. */
private fun listeningStatus(context: Context, count: Int): String =
    if (count == 0) {
        context.getString(R.string.home_status_listening)
    } else {
        context.getString(R.string.home_status_listening_count, count)
    }

/** Builds the spoken confirmation for [command] in the language it was spoken in. */
private fun buildReply(context: Context, command: VoiceCommand, fallback: AppLanguage): SpokenReply {
    val english: Boolean = command.language == Language.ENGLISH
    val replyRes: Int = if (english) R.string.home_voice_ack_en else R.string.home_voice_ack
    val spoken: Language = if (command.language == Language.UNKNOWN) {
        fallback.toSpeechLanguage()
    } else {
        command.language
    }
    return SpokenReply(context.getString(replyRes, command.rawText), spoken)
}
