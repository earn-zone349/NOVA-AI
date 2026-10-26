package com.nova.ai.verification

import com.nova.ai.accessibility.AccessibilityEngine
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.TaskStep
import com.nova.ai.core.VerificationReport
import com.nova.ai.logging.NovaLogger

/**
 * Runs one step and then checks that it worked: it reads the screen before, performs the
 * action, and keeps looking at the screen (a screen can take a moment to change) until the
 * [verifier] is satisfied or the time is up. Blocking: call from a background thread.
 *
 * If the action itself fails, that failure is handed back unchanged. If the action went
 * through but the screen did not show it, a [VerificationReport] with `passed = false` is returned.
 */
class VerifiedStepRunner(
    private val screen: AccessibilityEngine,
    private val verifier: VerificationEngine = ScreenVerificationEngine(),
    private val sleep: (Long) -> Unit = { millis -> Thread.sleep(millis) }
) {

    /** Performs [action] for [step] and verifies the result. */
    fun run(step: TaskStep, action: () -> NovaResult<Unit>): NovaResult<VerificationReport> {
        return try {
            val before: ScreenSnapshot? = screen.captureScreen().getOrNull()

            val outcome: NovaResult<Unit> = action()
            if (outcome is NovaResult.Failure) return outcome

            var last: VerificationReport = verifyOnce(step, before)
            var attempt = 1
            while (!last.passed && attempt < MAX_ATTEMPTS) {
                sleep(RETRY_DELAY_MS)
                last = verifyOnce(step, before)
                attempt += 1
            }
            NovaResult.Success(last)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            NovaResult.failure(ErrorCode.CANCELLED, MSG_CANCELLED, e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Verified step failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_UNEXPECTED, e)
        }
    }

    // Looks at the screen now and asks the verifier. A screen that cannot be read counts as unknown.
    private fun verifyOnce(step: TaskStep, before: ScreenSnapshot?): VerificationReport {
        val after: ScreenSnapshot? = screen.captureScreen().getOrNull()
        return when (val verdict = verifier.verify(step, before, after)) {
            is NovaResult.Success -> verdict.value
            is NovaResult.Failure -> VerificationReport(step.id, false, verdict.error.message)
        }
    }

    private companion object {
        const val TAG: String = "VerifiedStepRunner"
        // The first look comes right after the action, then up to 7 more, 400 ms apart (about 3 seconds).
        const val MAX_ATTEMPTS: Int = 8
        const val RETRY_DELAY_MS: Long = 400L

        const val MSG_CANCELLED: String = "যাচাই থামানো হয়েছে।"
        const val MSG_UNEXPECTED: String = "কাজ ও যাচাই করতে সমস্যা হয়েছে।"
    }
}
