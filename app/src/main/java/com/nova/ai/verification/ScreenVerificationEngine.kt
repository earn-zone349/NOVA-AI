package com.nova.ai.verification

import com.nova.ai.accessibility.SensitiveNodePolicy
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.ExpectedOutcome
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.StepAction
import com.nova.ai.core.TaskStep
import com.nova.ai.core.VerificationReport
import com.nova.ai.logging.NovaLogger

/**
 * The real [VerificationEngine]. After a step it looks at the screen again and decides whether
 * the step really did what it was expected to do ([TaskStep.expected]):
 * - [ExpectedOutcome.SCREEN_CHANGES] (the default): the screen is different from before.
 * - [ExpectedOutcome.NO_CHANGE_EXPECTED]: nothing needs to change, the step passes.
 * - [ExpectedOutcome.TEXT_VISIBLE]: the text in [TaskStep.expectedValue] is on the screen.
 * - [ExpectedOutcome.APP_IN_FRONT]: the app in [TaskStep.expectedValue] is in front.
 * Typed text ([StepAction.TYPE_TEXT]) must show up in a text field. Texts of the screen are never logged.
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
            StepAction.CLICK, StepAction.SCROLL, StepAction.BACK, StepAction.HOME, StepAction.OPEN_APP ->
                expectOutcome(step, before, after)
            StepAction.TYPE_TEXT -> expectTyped(step, after)
            StepAction.WAIT, StepAction.CONFIRM, StepAction.SPEAK ->
                report(step, true, MSG_NOTHING_TO_CHECK)
        }
    }

    private fun expectOutcome(step: TaskStep, before: ScreenSnapshot?, after: ScreenSnapshot): VerificationReport =
        when (step.expected) {
            ExpectedOutcome.SCREEN_CHANGES -> expectChange(step, before, after)
            ExpectedOutcome.NO_CHANGE_EXPECTED -> report(step, true, MSG_NO_CHANGE_OK)
            ExpectedOutcome.TEXT_VISIBLE -> expectVisibleText(step, after)
            ExpectedOutcome.APP_IN_FRONT -> expectApp(step, after)
        }

    private fun expectChange(step: TaskStep, before: ScreenSnapshot?, after: ScreenSnapshot): VerificationReport {
        if (before == null) return report(step, false, MSG_NO_BEFORE)
        val changed: Boolean = ScreenDiff.packageChanged(before, after) ||
            ScreenDiff.changedNodeCount(before, after) >= MIN_CHANGED_NODES
        val opensApp: Boolean = step.action == StepAction.OPEN_APP
        return when {
            changed && opensApp -> report(step, true, MSG_APP_OPENED)
            changed -> report(step, true, MSG_SCREEN_CHANGED)
            opensApp -> report(step, false, MSG_APP_SAME)
            else -> report(step, false, MSG_SCREEN_SAME)
        }
    }

    // The text must be on the screen outside of input fields, so a typed search word in the
    // search box does not count as "the results page is open".
    private fun expectVisibleText(step: TaskStep, after: ScreenSnapshot): VerificationReport {
        val value: String = step.expectedValue.orEmpty()
        if (value.isBlank()) return report(step, false, MSG_NO_EXPECTED_VALUE)
        val expected: String = tidy(SensitiveNodePolicy.maskCodes(value))
        val found: Boolean = after.nodes.any { node -> !node.isEditable && showsText(node, expected) }
        return if (found) report(step, true, MSG_TEXT_SHOWN) else report(step, false, MSG_TEXT_NOT_SHOWN)
    }

    private fun expectApp(step: TaskStep, after: ScreenSnapshot): VerificationReport {
        val expectedPackage: String = step.expectedValue.orEmpty().trim()
        if (expectedPackage.isEmpty()) return report(step, false, MSG_NO_EXPECTED_VALUE)
        val inFront: Boolean = after.packageName == expectedPackage
        return if (inFront) report(step, true, MSG_APP_OPENED) else report(step, false, MSG_APP_SAME)
    }

    private fun expectTyped(step: TaskStep, after: ScreenSnapshot): VerificationReport {
        val value: String = step.value.orEmpty()
        if (value.isBlank()) return report(step, false, MSG_NO_TEXT)
        // The screen reader hides code-like digits, so the expected text is hidden the same way.
        val expected: String = tidy(SensitiveNodePolicy.maskCodes(value))
        val found: Boolean = after.nodes.any { node -> node.isEditable && tidy(node.text.orEmpty()).contains(expected) }
        return if (found) report(step, true, MSG_TEXT_FOUND) else report(step, false, MSG_TEXT_MISSING)
    }

    private fun showsText(node: ScreenNode, expected: String): Boolean =
        listOf(node.text, node.contentDescription).any { label ->
            tidy(label.orEmpty()).contains(expected, ignoreCase = true)
        }

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
        const val MSG_NO_CHANGE_OK: String = "স্ক্রিন না বদলানোই প্রত্যাশিত ছিল।"
        const val MSG_TEXT_SHOWN: String = "প্রত্যাশিত লেখা স্ক্রিনে দেখা যাচ্ছে।"
        const val MSG_TEXT_NOT_SHOWN: String = "প্রত্যাশিত লেখা স্ক্রিনে দেখা গেল না।"
        const val MSG_NO_EXPECTED_VALUE: String = "কী দেখার কথা তা জানা নেই।"
        const val MSG_TEXT_FOUND: String = "লেখাটা ঘরে দেখা যাচ্ছে।"
        const val MSG_TEXT_MISSING: String = "লেখাটা কোনো ঘরে দেখা গেল না।"
        const val MSG_NO_TEXT: String = "কী লেখার কথা তা জানা নেই।"
        const val MSG_NOTHING_TO_CHECK: String = "এই ধাপে যাচাই করার কিছু নেই।"
        const val MSG_UNEXPECTED: String = "যাচাই করতে সমস্যা হয়েছে।"
    }
}
