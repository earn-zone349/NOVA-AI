package com.nova.ai.bubble

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.nova.ai.apps.AppCommandController
import com.nova.ai.apps.InstalledApp
import com.nova.ai.apps.RegisteredApp
import com.nova.ai.contacts.Contact
import com.nova.ai.contacts.ContactCommandController
import com.nova.ai.media.MediaCommandController
import com.nova.ai.security.EmergencyStop
import com.nova.ai.system.SystemCommandController
import com.nova.ai.time.TimeCommandController
import kotlinx.coroutines.CoroutineScope

/**
 * Runs a command from the bubble through the same five controllers the Home screen uses, and
 * turns what they report into a [BubbleOutput] for the bubble. Some controllers answer a moment
 * later (they look up apps or contacts first), so after a command the router looks at them every
 * [POLL_MS] until one has something to show or [WAIT_MS] is over.
 * Use from the main thread.
 */
internal class BubbleCommandRouter(
    context: Context,
    scope: CoroutineScope,
    private val texts: BubbleTexts,
    private val onOutput: (BubbleOutput) -> Unit,
    private val onBusyChanged: (Boolean) -> Unit
) : BubbleActions {

    private val app = AppCommandController(context, scope)
    private val system = SystemCommandController(context)
    private val contact = ContactCommandController(context, scope)
    private val time = TimeCommandController(context)
    private val media = MediaCommandController(context)

    private val mapper = BubbleOutputMapper(texts, this)
    private val handler = Handler(Looper.getMainLooper())

    private var pollTask: Runnable? = null
    private var busy: Boolean = false

    /** Carries out [text]. The answer arrives through [onOutput]. */
    fun handle(text: String) {
        cancel()
        if (EmergencyStop.isActive) {
            onOutput(BubbleOutput.Message(EmergencyStop.MESSAGE, MessageKind.ERROR))
            return
        }
        // Every controller looks at the text; the ones it does not concern reset themselves.
        app.handleCommand(text)
        system.handleCommand(text)
        contact.handleCommand(text)
        time.handleCommand(text)
        media.handleCommand(text)
        await(answeredSource = null, timeoutText = texts.notUnderstood())
    }

    /** The user tapped [option] of [decision]: run it and wait for what it leads to. */
    fun choose(decision: BubbleOutput.Decision, option: BubbleOption) {
        cancel()
        if (EmergencyStop.isActive) {
            onOutput(BubbleOutput.Message(EmergencyStop.MESSAGE, MessageKind.ERROR))
            return
        }
        option.action()
        await(answeredSource = decision.source, timeoutText = texts.notDone())
    }

    /** The user closed a question without answering: forget it. */
    fun dismissQuestion() {
        cancel()
        app.dismiss()
        contact.dismiss()
        time.dismiss()
        system.dismiss()
        media.dismiss()
    }

    /** Stops waiting for an answer (for example when the emergency stop goes on). */
    fun cancel() {
        pollTask?.let { handler.removeCallbacks(it) }
        pollTask = null
        setBusy(false)
    }

    /** Releases listeners. Call when the bubble is gone. */
    fun release() {
        cancel()
        system.release()
    }

    // ---------------------------------------------------------------- BubbleActions

    override fun confirmApp() = app.confirm()
    override fun chooseApp(app: RegisteredApp) = this.app.choose(app)
    override fun addAndOpen(app: InstalledApp) = this.app.addAndOpen(app)
    override fun pickContact(contact: Contact) = this.contact.pickContact(contact)
    override fun pickNumber(number: String) = contact.pickNumber(number)
    override fun placeCall(number: String) = contact.placeCall(number)
    override fun choosePeriod(isEvening: Boolean) = time.choosePeriod(isEvening)

    // ---------------------------------------------------------------- waiting

    private fun current(): BubbleOutput =
        mapper.map(app.state, contact.state, time.state, system.state, media.state)

    // Looks again and again until something new is there. A question that was just answered
    // (answeredSource) does not count as new while it is still the same question.
    private fun await(answeredSource: Any?, timeoutText: String) {
        setBusy(true)
        val startedAt: Long = SystemClock.uptimeMillis()
        val task = object : Runnable {
            override fun run() {
                val output: BubbleOutput = current()
                val stale: Boolean = output is BubbleOutput.Decision && output.source === answeredSource
                when {
                    output !is BubbleOutput.None && !stale -> finish(output)
                    SystemClock.uptimeMillis() - startedAt >= WAIT_MS ->
                        finish(BubbleOutput.Message(timeoutText, MessageKind.INFO))
                    else -> handler.postDelayed(this, POLL_MS)
                }
            }
        }
        pollTask = task
        handler.post(task)
    }

    private fun finish(output: BubbleOutput) {
        pollTask = null
        setBusy(false)
        onOutput(output)
    }

    private fun setBusy(value: Boolean) {
        if (busy == value) return
        busy = value
        onBusyChanged(value)
    }

    private companion object {
        const val POLL_MS: Long = 150L
        const val WAIT_MS: Long = 4000L
    }
}
