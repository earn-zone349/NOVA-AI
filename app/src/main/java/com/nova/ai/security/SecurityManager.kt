package com.nova.ai.security

import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.SecurityDecision
import com.nova.ai.core.TaskStep

/** Decides whether a step is safe and whether it needs user confirmation. */
interface SecurityManager {
    /** Evaluates [step] against the current [screen] (if known). */
    fun evaluate(step: TaskStep, screen: ScreenSnapshot?): SecurityDecision

    /** True if [text] looks like a password, OTP, or similar secret. */
    fun isSensitiveText(text: String): Boolean

    /** Immediately halts all automation. */
    fun triggerEmergencyStop()

    /** True while an emergency stop is active. */
    fun isEmergencyStopped(): Boolean

    /** Clears the emergency stop after the user confirms. */
    fun resetEmergencyStop()
}
