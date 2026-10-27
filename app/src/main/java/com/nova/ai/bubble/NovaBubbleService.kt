package com.nova.ai.bubble

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.nova.ai.MainActivity
import com.nova.ai.R
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.security.EmergencyStop
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.SettingsRepository
import com.nova.ai.voice.AndroidVoiceEngine
import com.nova.ai.voice.ConversationController
import com.nova.ai.voice.ConversationEnd
import com.nova.ai.voice.ConversationListener
import com.nova.ai.voice.ConversationState
import com.nova.ai.voice.VoiceFocus
import com.nova.ai.voice.toSpeechLanguage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * Keeps the floating bubble alive. A foreground service (type microphone) is used so Android
 * lets the microphone work while another app is on the screen. The service owns the bubble
 * window, one listening turn at a time, and the command router. Everything runs on the main thread.
 *
 * Tap the bubble: speak one command. Long press: menu. The red badge and the notification
 * button switch the emergency stop on; the bubble then shows a Resume button.
 */
class NovaBubbleService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private lateinit var settings: SettingsRepository
    private lateinit var overlay: BubbleOverlay
    private lateinit var router: BubbleCommandRouter
    private lateinit var voiceEngine: AndroidVoiceEngine
    private lateinit var conversation: ConversationController
    private lateinit var texts: ResourceBubbleTexts

    private var conversationState: ConversationState = ConversationState.IDLE
    private var routing: Boolean = false
    private var running: Boolean = false
    private var destroyed: Boolean = false

    private val emergencyListener: (Boolean) -> Unit = { _ -> handler.post { onEmergencyChanged() } }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // The channel comes first: even a service that cannot start must be able to show its notification.
        try {
            createChannel()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not create the notification channel", e)
        }
        try {
            settings = SettingsRepository(applicationContext)
            texts = ResourceBubbleTexts(this)
            overlay = BubbleOverlay(this, BubblePrefs(this), overlayCallbacks)
            router = BubbleCommandRouter(
                context = this,
                scope = scope,
                texts = texts,
                onOutput = { output -> showOutput(output) },
                onBusyChanged = { busy ->
                    routing = busy
                    refreshState()
                }
            )
            voiceEngine = AndroidVoiceEngine(
                context = this,
                languageProvider = { settings.getLanguage() },
                speechRateProvider = { settings.getSpeechSpeed().rate }
            )
            conversation = ConversationController(
                engine = voiceEngine,
                listener = conversationListener,
                continuousProvider = { false },
                replyProvider = { _ -> null }
            )
        } catch (e: Exception) {
            // Without these parts the bubble cannot work; onStartCommand sees `running` is false and stops.
            NovaLogger.e(TAG, "Bubble service could not be created", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action: String? = intent?.action
        if (!isReady()) {
            // startForegroundService() demands a notification even when we give up right away.
            if (action == null || action == ACTION_START) enterForeground()
            stopSelf()
            return START_NOT_STICKY
        }
        when (action) {
            ACTION_EMERGENCY_STOP -> {
                EmergencyStop.trigger(SOURCE_NOTIFICATION)
                if (!running) stopSelf()
            }
            ACTION_RESUME -> {
                EmergencyStop.release(SOURCE_NOTIFICATION)
                if (!running) stopSelf()
            }
            ACTION_CLOSE -> {
                stopSelf()
            }
            else -> startBubble()
        }
        // If Android kills the service, the bubble stays closed until the user opens it again.
        return START_NOT_STICKY
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (running) overlay.onConfigurationChanged()
    }

    override fun onDestroy() {
        destroyed = true
        try {
            EmergencyStop.removeListener(emergencyListener)
            EmergencyStop.unregisterHook(HOOK_KEY)
            VoiceFocus.unregister(VOICE_OWNER)
            if (isReady()) {
                conversation.shutdown()
                router.release()
                voiceEngine.shutdown()
                overlay.hide()
            }
            scope.cancel()
            handler.removeCallbacksAndMessages(null)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Bubble service did not close cleanly", e)
        }
        running = false
        BubbleController.isRunning = false
        super.onDestroy()
    }

    // ---------------------------------------------------------------- start

    private fun isReady(): Boolean = this::overlay.isInitialized && this::conversation.isInitialized

    private fun startBubble() {
        if (running) return
        // A foreground service must show its notification within seconds of being started.
        if (!enterForeground()) {
            stopSelf()
            return
        }
        if (!BubbleController.canDrawOverlays(this) || !overlay.show()) {
            NovaLogger.w(TAG, "No permission to draw the bubble; stopping")
            stopSelf()
            return
        }
        running = true
        BubbleController.isRunning = true
        VoiceFocus.register(VOICE_OWNER) { handler.post { stopListeningTurn() } }
        EmergencyStop.registerHook(HOOK_KEY) { handler.post { onEmergencyHook() } }
        EmergencyStop.addListener(emergencyListener)
        refreshState()
        NovaLogger.i(TAG, "Bubble started")
    }

    private fun enterForeground(): Boolean = try {
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        )
        true
    } catch (e: Exception) {
        // For example Android 14 refuses a microphone service started from the background.
        NovaLogger.e(TAG, "Could not enter the foreground", e)
        false
    }

    // ---------------------------------------------------------------- bubble touches

    private val overlayCallbacks = object : BubbleOverlayCallbacks {
        override fun onBubbleTap() = handleTap()
        override fun onBubbleLongPress() = showMenu()
        override fun onStopBadgeTap() {
            EmergencyStop.trigger(SOURCE_BADGE)
        }
    }

    private fun handleTap() {
        if (EmergencyStop.isActive) {
            showResumePanel()
            return
        }
        if (conversation.isActive()) {
            // A second tap while listening cancels it.
            conversation.stop()
            overlay.hidePanel()
            return
        }
        startListeningTurn()
    }

    private fun startListeningTurn() {
        overlay.hidePanel()
        router.cancel()
        VoiceFocus.claim(VOICE_OWNER)
        when (val result: NovaResult<Unit> = conversation.start()) {
            is NovaResult.Success -> overlay.showStatus(getString(R.string.bub_listening), null, 0L)
            is NovaResult.Failure -> {
                val text: String = if (result.error.code == ErrorCode.PERMISSION_DENIED) {
                    getString(R.string.bub_mic_needed)
                } else {
                    result.error.message
                }
                overlay.showStatus(text, MessageKind.ERROR, STATUS_MS)
            }
        }
    }

    private fun stopListeningTurn() {
        if (!isReady() || destroyed) return
        try {
            conversation.stop()
            voiceEngine.stopSpeaking()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not stop the listening turn", e)
        }
    }

    private fun showMenu() {
        val buttons: MutableList<PanelButton> = mutableListOf(
            PanelButton(getString(R.string.bub_menu_open), PanelStyle.PRIMARY) { openNova() }
        )
        if (EmergencyStop.isActive) {
            buttons.add(PanelButton(getString(R.string.bub_menu_resume)) { EmergencyStop.release(SOURCE_MENU) })
        } else {
            buttons.add(PanelButton(getString(R.string.bub_menu_stop)) { EmergencyStop.trigger(SOURCE_MENU) })
        }
        buttons.add(PanelButton(getString(R.string.bub_menu_close)) { stopSelf() })
        overlay.showPanel(getString(R.string.bub_menu_title), buttons, MENU_MS, null)
    }

    private fun showResumePanel() {
        val buttons: List<PanelButton> = listOf(
            PanelButton(getString(R.string.bub_menu_resume), PanelStyle.PRIMARY) { EmergencyStop.release(SOURCE_PANEL) },
            PanelButton(getString(R.string.bub_menu_close)) { stopSelf() }
        )
        overlay.showPanel(EmergencyStop.MESSAGE, buttons, QUESTION_MS, null)
    }

    private fun openNova() {
        try {
            val intent = Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            startActivity(intent)
        } catch (e: Exception) {
            // Android may block opening a screen from the background; the notification still opens it.
            NovaLogger.w(TAG, "Could not open NOVA from the bubble", e)
            overlay.showStatus(getString(R.string.bub_open_blocked), MessageKind.INFO, STATUS_MS)
        }
    }

    // ---------------------------------------------------------------- conversation

    private val conversationListener = object : ConversationListener {
        override fun onStateChanged(state: ConversationState) {
            conversationState = state
            refreshState()
        }

        override fun onPartialText(text: String) {
            if (text.isNotBlank()) overlay.showStatus("“$text”", null, 0L)
        }

        override fun onCommand(command: VoiceCommand) {
            overlay.showStatus("“${command.rawText}”", null, 0L)
            router.handle(command.rawText)
        }

        override fun onEnded(reason: ConversationEnd) {
            when (reason) {
                is ConversationEnd.SingleCompleted, is ConversationEnd.UserStopped -> Unit
                is ConversationEnd.StopPhrase -> overlay.hidePanel()
                is ConversationEnd.SilenceTimeout ->
                    overlay.showStatus(getString(R.string.bub_not_heard), MessageKind.INFO, STATUS_MS)
                is ConversationEnd.Failed -> {
                    val code: ErrorCode = reason.error.code
                    val text: String = if (code == ErrorCode.TIMEOUT || code == ErrorCode.NOT_FOUND) {
                        getString(R.string.bub_not_heard)
                    } else {
                        reason.error.message
                    }
                    overlay.showStatus(text, MessageKind.ERROR, STATUS_MS)
                }
            }
        }
    }

    // ---------------------------------------------------------------- showing what the router found

    private fun showOutput(output: BubbleOutput) {
        when (output) {
            is BubbleOutput.None -> Unit
            is BubbleOutput.Message -> {
                overlay.showStatus(output.text, output.kind, if (output.kind == MessageKind.ERROR) STATUS_MS else DONE_MS)
                speakResult(output.text)
            }
            is BubbleOutput.Decision -> {
                val buttons: MutableList<PanelButton> = output.options.map { option ->
                    PanelButton(
                        label = option.label,
                        style = if (option.emphasis) PanelStyle.PRIMARY else PanelStyle.NORMAL
                    ) { router.choose(output, option) }
                }.toMutableList()
                buttons.add(PanelButton(getString(R.string.bub_cancel)) { router.dismissQuestion() })
                overlay.showPanel(output.question, buttons, QUESTION_MS) { router.dismissQuestion() }
                speakResult(output.question)
            }
            is BubbleOutput.NeedsApp -> {
                val buttons: List<PanelButton> = listOf(
                    PanelButton(getString(R.string.bub_menu_open), PanelStyle.PRIMARY) { openNova() },
                    PanelButton(getString(R.string.bub_cancel)) { router.dismissQuestion() }
                )
                overlay.showPanel(output.text, buttons, QUESTION_MS) { router.dismissQuestion() }
            }
        }
    }

    // Speaks the result when voice replies are on and NOVA is not stopped.
    private fun speakResult(text: String) {
        if (EmergencyStop.isActive) return
        try {
            if (!settings.isVoiceReplyEnabled()) return
            val language: AppLanguage = settings.getLanguage()
            voiceEngine.speak(text, language.toSpeechLanguage())
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not speak the result", e)
        }
    }

    // ---------------------------------------------------------------- emergency stop

    // Runs for every stop, on the main thread: nothing may go on working.
    private fun onEmergencyHook() {
        if (!isReady() || destroyed) return
        router.cancel()
        router.dismissQuestion()
        stopListeningTurn()
        overlay.hidePanel()
    }

    private fun onEmergencyChanged() {
        if (!running || destroyed) return
        refreshState()
        updateNotification()
        if (EmergencyStop.isActive) {
            overlay.showStatus(EmergencyStop.MESSAGE, MessageKind.ERROR, STATUS_MS)
        } else {
            overlay.hidePanel()
        }
    }

    private fun refreshState() {
        if (!isReady() || destroyed) return
        overlay.setState(BubbleStateMapper.map(EmergencyStop.isActive, conversationState, routing))
    }

    // ---------------------------------------------------------------- notification

    private fun createChannel() {
        val manager: NotificationManager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.bub_channel_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply { setShowBadge(false) }
        manager.createNotificationChannel(channel)
    }

    private fun updateNotification() {
        try {
            getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, buildNotification())
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not update the notification", e)
        }
    }

    private fun buildNotification(): Notification {
        val stopped: Boolean = EmergencyStop.isActive
        val open: PendingIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PENDING_FLAGS
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_nova_bubble)
            .setContentTitle(getString(R.string.bub_notif_title))
            .setContentText(getString(if (stopped) R.string.bub_notif_stopped else R.string.bub_notif_text))
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        if (stopped) {
            builder.addAction(0, getString(R.string.bub_menu_resume), servicePending(ACTION_RESUME, 1))
        } else {
            builder.addAction(0, getString(R.string.bub_notif_stop), servicePending(ACTION_EMERGENCY_STOP, 2))
        }
        builder.addAction(0, getString(R.string.bub_menu_close), servicePending(ACTION_CLOSE, 3))
        return builder.build()
    }

    private fun servicePending(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, NovaBubbleService::class.java).setAction(action)
        return PendingIntent.getService(this, requestCode, intent, PENDING_FLAGS)
    }

    companion object {
        private const val TAG: String = "NovaBubbleService"
        private const val CHANNEL_ID: String = "nova_bubble"
        private const val NOTIFICATION_ID: Int = 2201
        private const val PENDING_FLAGS: Int = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        private const val VOICE_OWNER: String = "bubble"
        private const val HOOK_KEY: String = "bubble"
        private const val SOURCE_BADGE: String = "bubble badge"
        private const val SOURCE_MENU: String = "bubble menu"
        private const val SOURCE_PANEL: String = "bubble panel"
        private const val SOURCE_NOTIFICATION: String = "notification"

        private const val STATUS_MS: Long = 4000L
        private const val DONE_MS: Long = 3500L
        private const val MENU_MS: Long = 8000L
        private const val QUESTION_MS: Long = 20000L

        /** Starts the bubble. */
        const val ACTION_START: String = "com.nova.ai.bubble.START"

        /** Switches the emergency stop on. */
        const val ACTION_EMERGENCY_STOP: String = "com.nova.ai.bubble.EMERGENCY_STOP"

        /** Switches the emergency stop off. */
        const val ACTION_RESUME: String = "com.nova.ai.bubble.RESUME"

        /** Closes the bubble. */
        const val ACTION_CLOSE: String = "com.nova.ai.bubble.CLOSE"
    }
}
