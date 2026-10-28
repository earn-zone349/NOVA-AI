package com.nova.ai.tasks

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.security.EmergencyStop
import com.nova.ai.voice.LanguageDetector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
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

    private var queue: TaskQueue? = null
    private var planner: CommandPlanner? = null
    private var notice: String? = null
    private var noticeSeq: Int = 0

    /** Gets everything ready. Safe to call many times. */
    fun init(context: Context) {
        if (queue != null) return
        val appContext: Context = context.applicationContext
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        queue = TaskQueue(
            executor = CommandStepExecutor(appContext, scope),
            scheduler = HandlerScheduler(mainHandler),
            onChanged = { snapshot -> publish(snapshot) },
            log = { message -> NovaLogger.i(TAG, message) }
        )
        planner = CommandPlanner(analyze = { part -> analyze(part) })
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

    /** Closes the result of the last task and the notice. */
    fun dismiss() {
        notice = null
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

    private fun setNotice(message: String?) {
        notice = message
        if (message != null) noticeSeq += 1
        publish(queue?.snapshot() ?: QueueSnapshot.EMPTY)
    }

    private fun publish(snapshot: QueueSnapshot) {
        val merged: QueueSnapshot = snapshot.copy(notice = notice, noticeSeq = noticeSeq)
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
