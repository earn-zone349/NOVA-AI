package com.nova.ai.verification

import com.nova.ai.accessibility.SensitiveNodePolicy
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.StepAction
import com.nova.ai.core.TaskStep
import com.nova.ai.core.VerificationReport
import com.nova.ai.logging.NovaLogger

/**
 * The real [VerificationEngine]. After a step it looks at the screen again and decides whether
 * the step really did something: a click, scroll, Back, Home or app start must change the screen,
 * and typed text must show up in a text field. Texts of the screen are never logged.
 *
 * Limit: a step that changes nothing visible (for example a click on a button that only
 * plays a sound) is reported as not verified. The caller decides what to do with that.
 */
class ScreenVerificationEngine : VerificationEngine {

    override fun verify(
        step: TaskStep,
        before: ScreenSnapshot?,
        after: ScreenSnapshot?
    ): NovaResult<VerificationReport> = try {
        NovaResult.Success(decide(step, before, after))
    } catch (e: Exception) {
        NovaLogger.e(TAG, "Verification failed", e)
        NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_UNEXPECTED, e)
    }

    private fun decide(step: TaskStep, before: ScreenSnapshot?, after: ScreenSnapshot?): VerificationReport {
        if (after == null) return report(step, false, MSG_NO_AFTER)
        return when (step.action) {
            StepAction.CLICK, StepAction.SCROLL, StepAction.BACK, StepAction.HOME ->
                expectChange(step, before, after, MSG_SCREEN_CHANGED, MSG_SCREEN_SAME)
            StepAction.OPEN_APP -> expectChange(step, before, after, MSG_APP_OPENED, MSG_APP_SAME)
            StepAction.TYPE_TEXT -> expectText(step, after)
            StepAction.WAIT, StepAction.CONFIRM, StepAction.SPEAK ->
                report(step, true, MSG_NOTHING_TO_CHECK)
        }
    }

    private fun expectChange(
        step: TaskStep,
        before: ScreenSnapshot?,
        after: ScreenSnapshot,
        passedMessage: String,
        failedMessage: String
    ): VerificationReport {
        if (before == null) return report(step, false, MSG_NO_BEFORE)
        val changed: Boolean = ScreenDiff.packageChanged(before, after) ||
            ScreenDiff.changedNodeCount(before, after) >= MIN_CHANGED_NODES
        return if (changed) report(step, true, passedMessage) else report(step, false, failedMessage)
    }

    private fun expectText(step: TaskStep, after: ScreenSnapshot): VerificationReport {
        val value: String = step.value.orEmpty()
        if (value.isBlank()) return report(step, false, MSG_NO_TEXT)
        // The screen reader hides code-like digits, so the expected text is hidden the same way.
        val expected: String = tidy(SensitiveNodePolicy.maskCodes(value))
        val found: Boolean = after.nodes.any { node -> isFieldWith(node, expected) }
        return if (found) report(step, true, MSG_TEXT_FOUND) else report(step, false, MSG_TEXT_MISSING)
    }

    private fun isFieldWith(node: ScreenNode, expected: String): Boolean =
        node.isEditable && tidy(node.text.orEmpty()).contains(expected)

    private fun tidy(text: String): String = text.trim().replace(WHITESPACE, " ")

    private fun report(step: TaskStep, passed: Boolean, detail: String): VerificationReport =
        VerificationReport(stepId = step.id, passed = passed, detail = detail)

    private companion object {
        const val TAG: String = "ScreenVerification"
        const val MIN_CHANGED_NODES: Int = 1
        val WHITESPACE: Regex = Regex("\\s+")

        const val MSG_NO_AFTER: String = "কাজের পরের স্ক্রিন পড়া যায়নি, তাই যাচাই করা গেল না।"
        const val MSG_NO_BEFORE: String = "কাজের আগের স্ক্রিন পড়া যায়নি, তাই যাচাই করা গেল না।"
        const val MSG_SCREEN_CHANGED: String = "স্ক্রিন বদলেছে।"
        const val MSG_SCREEN_SAME: String = "স্ক্রিন বদলায়নি। কাজটা হয়নি বলে মনে হচ্ছে।"
        const val MSG_APP_OPENED: String = "অ্যাপ খুলেছে।"
        const val MSG_APP_SAME: String = "অ্যাপ খোলার কোনো চিহ্ন দেখা যায়নি।"
        const val MSG_TEXT_FOUND: String = "লেখাটা ঘরে দেখা যাচ্ছে।"
        const val MSG_TEXT_MISSING: String = "লেখাটা কোনো ঘরে দেখা গেল না।"
        const val MSG_NO_TEXT: String = "কী লেখার কথা তা জানা নেই।"
        const val MSG_NOTHING_TO_CHECK: String = "এই ধাপে যাচাই করার কিছু নেই।"
        const val MSG_UNEXPECTED: String = "যাচাই করতে সমস্যা হয়েছে।"
    }
}
