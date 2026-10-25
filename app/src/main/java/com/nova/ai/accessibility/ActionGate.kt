package com.nova.ai.accessibility

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult

/**
 * The emergency stop. While it is on, every action of the accessibility service
 * (clicks, typing, scrolling, Back, Home, gestures) is refused. Reading is not affected.
 * The floating stop button of a later phase switches it on.
 */
object ActionGate {

    private const val MSG_STOPPED: String =
        "জরুরি Stop চালু আছে। ছাড়া না পর্যন্ত নোভা কোনো কাজ করবে না।"

    /** True while the emergency stop is on. */
    var isStopped: Boolean by mutableStateOf(false)
        private set

    /** Switches the emergency stop on. */
    fun stop() {
        isStopped = true
    }

    /** Switches the emergency stop off. */
    fun resume() {
        isStopped = false
    }

    /** Returns a failure to hand back to the caller while stopped, or null when actions are allowed. */
    fun check(): NovaResult.Failure? =
        if (isStopped) NovaResult.failure(ErrorCode.SECURITY_BLOCKED, MSG_STOPPED) else null
}
