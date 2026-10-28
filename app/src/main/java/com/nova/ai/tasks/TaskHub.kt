package com.nova.ai.tasks

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.security.EmergencyStop
import com.nova.ai.voice.LanguageDetector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.CopyOnWriteArrayList

/**
 * The one place where multi-step tasks are started and watched. The Home screen, the bubble and
 * the Automation screen all use it: a command with several parts ("ক্রোম খোলো তারপর ভলিউম বাড়াও")
 * is planned, queued and run step by step. The emergency stop cancels everything. [state] is
 * observable by Compose screens; other code can use [addListener]. Use from the main thread.
 */
object TaskHub {

    private const val TAG: String = "TaskHub"
    private const val HOOK_KEY: String = "tasks"

    /** The queue as the screens show it. Changes only on the main thread. */
    var state: QueueSnapshot by mutableStateOf(QueueSnapshot.EMPTY)
        private set

    private val listeners: CopyOnWriteArrayList<(QueueSnapshot) -> Unit> = CopyOnWriteArrayList()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val brain = RuleBasedBrain()

    /** The finished tasks, newest first (at most [TaskHistoryRepository.HISTORY_LIMIT]). Main thread. */
    var history: List<HistoryItem> by mutableStateOf(emptyList())
        private set

    private val recorder = HistoryRecorder { System.currentTimeMillis() }
    private var repository: TaskHistoryRepository? = null
    private var scope: CoroutineScope? = null
    private var noticeIsError: Boolean = true

    private var queue: TaskQueue? = null
    private var planner: CommandPlanner? = null
    private var notice: String? = null
    private var noticeSeq: Int = 0

    /** Gets everything ready. Safe to call many times. */
    fun init(context: Context) {
        if (queue != null) return
        val appContext: Context = context.applicationContext
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        this.scope = scope
        repository = try {
            TaskHistoryRepository(appContext)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "The task history is not available", e)
            null
        }
        queue = TaskQueue(
            executor = CommandStepExecutor(appContext, scope),
            scheduler = HandlerScheduler(mainHandler),
            onChanged = { snapshot -> publish(snapshot) },
            timing = TaskTiming(
                perTypeTimeoutMs = mapOf(
                    IntentType.SYSTEM_ACTION to 10_000L,
                    IntentType.MEDIA_CONTROL to 10_000L,
                    IntentType.OPEN_APP to 15_000L
                )
            ),
            log = { message -> NovaLogger.i(TAG, message) },
            retry = RetryPolicy.STANDARD,
            fallback = WebFallbackPlanner
        )
        planner = CommandPlanner(analyze = { part -> analyze(part) })
        loadHistory()
        // The emergency stop cancels the running task and empties the line.
        EmergencyStop.registerHook(HOOK_KEY) { mainHandler.post { queue?.cancelAll() } }
    }

    /** Gets [listener] every time the queue changes (main thread). */
    fun addListener(listener: (QueueSnapshot) -> Unit) {
        listeners.addIfAbsent(listener)
    }

    /** Stops [listener]. */
    fun removeListener(listener: (QueueSnapshot) -> Unit) {
        listeners.remove(listener)
    }

    /**
     * If [text] has several parts, plans it and puts it in the queue and returns true (the caller
     * must not run it any other way). Returns false for an ordinary single command.
     * A part that is not understood is reported through [QueueSnapshot.notice], and nothing starts.
     */
    fun submitIfMultiStep(context: Context, text: String): Boolean {
        init(context)
        val planner: CommandPlanner = planner ?: return false
        if (!planner.isMultiStep(text)) return false
        submit(context, text)
        return true
    }

    /** Plans [text] and puts it in the queue. A failure result carries a Bangla message (also shown as the notice). */
    fun submit(context: Context, text: String): NovaResult<String> {
        init(context)
        val queue: TaskQueue = queue ?: return failed("")
        val planner: CommandPlanner = planner ?: return failed("")
        if (EmergencyStop.isActive) return failed(EmergencyStop.MESSAGE)
        return when (val plan: NovaResult<TaskDraft> = planner.plan(text)) {
            is NovaResult.Failure -> failed(plan.error.message)
            is NovaResult.Success -> when (val queued: NovaResult<String> = queue.submit(plan.value)) {
                is NovaResult.Failure -> failed(queued.error.message)
                is NovaResult.Success -> {
                    recorder.remember(plan.value)
                    setNotice(null)
                    queued
                }
            }
        }
    }

    /** The user picked option number [index] of the question. */
    fun answer(index: Int) {
        val result: NovaResult<Unit> = queue?.answer(index) ?: return
        if (result is NovaResult.Failure) setNotice(result.error.message)
    }

    /** Cancels the task in front. */
    fun cancelCurrent() {
        val id: String = state.current?.takeIf { it.isOpen }?.id ?: return
        queue?.cancel(id)
    }

    /** Cancels the task in front and empties the line. */
    fun cancelAll() {
        queue?.cancelAll()
    }

    /** Pauses the task in front before its next step. */
    fun pause() {
        val id: String = state.current?.id ?: return
        val result: NovaResult<Unit> = queue?.pause(id) ?: return
        if (result is NovaResult.Failure) setNotice(result.error.message)
    }

    /** Lets a paused task go on. */
    fun resume() {
        val id: String = state.current?.id ?: return
        val result: NovaResult<Unit> = queue?.resume(id) ?: return
        if (result is NovaResult.Failure) setNotice(result.error.message)
    }

    /**
     * P25: if [text] is a control word for the task ("থামো", "চালিয়ে যাও", "বাতিল", "আবার চালাও",
     * "কতদূর হলো") that applies now, does it, shows the answer as a notice and returns true.
     * Returns false when the text is something else, so the caller runs it as an ordinary command.
     */
    fun handleControl(context: Context, text: String): Boolean {
        init(context)
        val command: TaskControlCommand = TaskVoiceControl.parse(text) ?: return false
        return execute(command)
    }

    /**
     * P25: the user said a stop word ("থামো") and the conversation ended. If a task is running it
     * is paused (it can be resumed). Returns true if a task was paused.
     */
    fun pauseIfRunning(context: Context): Boolean {
        init(context)
        return execute(TaskControlCommand.PAUSE)
    }

    private fun execute(command: TaskControlCommand): Boolean {
        val queue: TaskQueue = queue ?: return false
        val rerunnable: HistoryItem? = lastRerunnable()
        val rerunSteps: Int = rerunnable?.steps?.count { it.state != StepState.DONE } ?: 0
        val decision: ControlDecision = TaskControlPlanner.decide(command, queue.snapshot(), rerunSteps) ?: return false
        when (decision.action) {
            ControlAction.PAUSE -> pause()
            ControlAction.RESUME -> resume()
            ControlAction.CANCEL_CURRENT -> cancelCurrent()
            ControlAction.CANCEL_ALL -> cancelAll()
            ControlAction.RERUN -> if (rerunnable != null) rerun(rerunnable)
            ControlAction.NONE -> Unit
        }
        decision.reply?.let { setNotice(it, isError = false) }
        return true
    }

    // The newest finished task that can be run again: the one just finished, or the newest in the history.
    private fun lastRerunnable(): HistoryItem? = history.firstOrNull()?.takeIf { it.canRerun }

    /** P25: runs the steps of [item] that did not finish as a new task. Returns false if nothing could be queued. */
    fun rerun(item: HistoryItem): Boolean {
        val queue: TaskQueue = queue ?: return false
        if (EmergencyStop.isActive) {
            setNotice(EmergencyStop.MESSAGE, isError = true)
            return false
        }
        val draft: TaskDraft? = item.toRerunDraft("t" + System.currentTimeMillis())
        if (draft == null) {
            setNotice(if (item.steps.isEmpty()) TaskMessages.MSG_HISTORY_NOT_FOUND else TaskMessages.MSG_NOTHING_LEFT, true)
            return false
        }
        return when (val queued: NovaResult<String> = queue.submit(draft)) {
            is NovaResult.Failure -> {
                setNotice(queued.error.message, isError = true)
                false
            }
            is NovaResult.Success -> {
                recorder.remember(draft)
                setNotice(null)
                true
            }
        }
    }

    /** P25: deletes the task history (the memory copy and the database). */
    fun clearHistory() {
        history = emptyList()
        val repo: TaskHistoryRepository = repository ?: return
        scope?.launch { repo.clear() }
        setNotice(TaskMessages.MSG_HISTORY_CLEARED, isError = false)
    }

    private fun loadHistory() {
        val repo: TaskHistoryRepository = repository ?: return
        scope?.launch {
            val loaded: List<HistoryItem> = repo.recent()
            // A task may have finished while the list was loading; keep it in front.
            val fresh: List<HistoryItem> = history.filter { h -> loaded.none { it.id == h.id } }
            history = (fresh + loaded).take(TaskHistoryRepository.HISTORY_LIMIT)
        }
    }

    private fun record(item: HistoryItem) {
        history = (listOf(item) + history.filter { it.id != item.id }).take(TaskHistoryRepository.HISTORY_LIMIT)
        val repo: TaskHistoryRepository = repository ?: return
        scope?.launch { repo.save(item) }
    }

    /** Closes the result of the last task and the notice. */
    fun dismiss() {
        notice = null
        noticeIsError = true
        val queue: TaskQueue? = queue
        if (queue != null) {
            queue.dismissFinished()
            publish(queue.snapshot())
        } else {
            publish(QueueSnapshot.EMPTY)
        }
    }

    private fun failed(message: String): NovaResult<String> {
        setNotice(message.ifBlank { null })
        return NovaResult.failure(ErrorCode.INVALID_INPUT, message)
    }

    private fun setNotice(message: String?, isError: Boolean = true) {
        notice = message
        noticeIsError = isError
        if (message != null) noticeSeq += 1
        publish(queue?.snapshot() ?: QueueSnapshot.EMPTY)
    }

    private fun publish(snapshot: QueueSnapshot) {
        val merged: QueueSnapshot = snapshot.copy(notice = notice, noticeSeq = noticeSeq, noticeIsError = noticeIsError)
        recorder.onSnapshot(merged)?.let { record(it) }
        state = merged
        for (listener in listeners) {
            try {
                listener(merged)
            } catch (e: Exception) {
                NovaLogger.e(TAG, "A task listener failed", e)
            }
        }
    }

    // The meaning of one part of a command, from the rule-based brain.
    private fun analyze(part: String): NovaIntent? {
        val command = VoiceCommand(
            rawText = part,
            language = LanguageDetector.detect(part),
            timestampMs = System.currentTimeMillis()
        )
        return brain.analyze(command, emptyList()).getOrNull()
    }
}
