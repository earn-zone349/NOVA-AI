package com.nova.ai.verification

import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.TaskStep
import com.nova.ai.core.VerificationReport

/** Checks whether a step really achieved its goal. */
interface VerificationEngine {
    /** Compares the screen [before] and [after] a [step] to confirm success. */
    fun verify(
        step: TaskStep,
        before: ScreenSnapshot?,
        after: ScreenSnapshot?
    ): NovaResult<VerificationReport>
}
