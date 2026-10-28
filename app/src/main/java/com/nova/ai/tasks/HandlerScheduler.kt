package com.nova.ai.tasks

import android.os.Handler

/** A [Scheduler] that runs its work on the thread of [handler] (the main thread on the phone). */
class HandlerScheduler(private val handler: Handler) : Scheduler {

    override fun postDelayed(delayMs: Long, task: () -> Unit): Cancellable {
        val runnable = Runnable { task() }
        handler.postDelayed(runnable, delayMs)
        return Cancellable { handler.removeCallbacks(runnable) }
    }
}
