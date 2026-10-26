package com.nova.ai.verification

import com.nova.ai.accessibility.SensitiveNodePolicy
import com.nova.ai.core.ExpectedOutcome
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenBounds
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.StepAction
import com.nova.ai.core.TaskStep
import com.nova.ai.core.VerificationReport
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests how [ScreenVerificationEngine] judges a step from the screen before and after. */
class ScreenVerificationEngineTest {

    private val engine = ScreenVerificationEngine()
    private val area = ScreenBounds(0, 0, 100, 50)

    private fun node(
        text: String?,
        editable: Boolean = false,
        checked: Boolean = false,
        description: String? = null
    ): ScreenNode = ScreenNode(
        text = text,
        contentDescription = description,
        className = "android.widget.Button",
        packageName = "pkg",
        isClickable = true,
        isEditable = editable,
        isScrollable = false,
        bounds = area,
        isChecked = checked
    )

    private fun screen(packageName: String?, vararg nodes: ScreenNode): ScreenSnapshot =
        ScreenSnapshot(packageName, nodes.toList(), 0L)

    private fun step(
        action: StepAction,
        value: String? = null,
        expected: ExpectedOutcome = ExpectedOutcome.SCREEN_CHANGES,
        expectedValue: String? = null
    ): TaskStep = TaskStep(
        id = "s1",
        action = action,
        value = value,
        expected = expected,
        expectedValue = expectedValue
    )

    private fun verdict(step: TaskStep, before: ScreenSnapshot?, after: ScreenSnapshot?): VerificationReport =
        when (val result = engine.verify(step, before, after)) {
            is NovaResult.Success -> result.value
            is NovaResult.Failure -> throw AssertionError(result.error.message)
        }

    private val home = screen("launcher", node("Chrome"), node("Phone"))
    private val chrome = screen("chrome", node("Search"), node("Menu"))

    // ------------------------------------------------------------ the screen must change

    @Test
    fun clickPassesWhenAnotherAppComesToFront() {
        assertTrue(verdict(step(StepAction.CLICK), home, chrome).passed)
    }

    @Test
    fun clickFailsWhenTheScreenIsTheSame() {
        val same = screen("launcher", node("Chrome"), node("Phone"))
        assertFalse(verdict(step(StepAction.CLICK), home, same).passed)
    }

    @Test
    fun clickPassesWhenAnItemAppearsInTheSameApp() {
        val withDialog = screen("launcher", node("Chrome"), node("Phone"), node("Dialog"))
        assertTrue(verdict(step(StepAction.CLICK), home, withDialog).passed)
    }

    @Test
    fun switchToggleCountsAsAChange() {
        val off = screen("s", node("Wi-Fi", checked = false))
        val on = screen("s", node("Wi-Fi", checked = true))
        assertTrue(verdict(step(StepAction.CLICK), off, on).passed)
    }

    @Test
    fun aTickingClockDoesNotHideAFailedClick() {
        val before = screen("s", node("Ok"), node("10:52"))
        val after = screen("s", node("Ok"), node("10:53"))
        assertFalse(verdict(step(StepAction.CLICK), before, after).passed)
        val banglaBefore = screen("s", node("Ok"), node("১০:৫২"))
        val banglaAfter = screen("s", node("Ok"), node("১০:৫৩"))
        assertFalse(verdict(step(StepAction.CLICK), banglaBefore, banglaAfter).passed)
    }

    @Test
    fun aCounterThatChangesIsAChange() {
        assertTrue(verdict(step(StepAction.CLICK), screen("s", node("3")), screen("s", node("4"))).passed)
    }

    @Test
    fun missingScreensMeanNotVerified() {
        assertFalse(verdict(step(StepAction.CLICK), home, null).passed)
        assertFalse(verdict(step(StepAction.CLICK), null, chrome).passed)
    }

    @Test
    fun twoCopiesBecomingOneIsAChange() {
        val two = screen("s", node("A"), node("A"))
        val one = screen("s", node("A"))
        assertTrue(verdict(step(StepAction.SCROLL), two, one).passed)
    }

    @Test
    fun openAppNeedsAnotherAppOrAChange() {
        assertTrue(verdict(step(StepAction.OPEN_APP), home, chrome).passed)
        assertFalse(verdict(step(StepAction.OPEN_APP), home, home).passed)
    }

    @Test
    fun backAndHomeNeedAChange() {
        assertTrue(verdict(step(StepAction.HOME), chrome, home).passed)
        assertFalse(verdict(step(StepAction.BACK), chrome, chrome).passed)
    }

    @Test
    fun reportCarriesTheStepId() {
        assertEquals("s1", verdict(step(StepAction.CLICK), home, chrome).stepId)
    }

    // ------------------------------------------------------------ expected outcomes

    @Test
    fun noChangeExpectedPassesOnAnUnchangedScreen() {
        val copy = step(StepAction.CLICK, expected = ExpectedOutcome.NO_CHANGE_EXPECTED)
        assertTrue(verdict(copy, home, home).passed)
    }

    @Test
    fun noChangeExpectedStillNeedsTheScreenToBeReadable() {
        val copy = step(StepAction.CLICK, expected = ExpectedOutcome.NO_CHANGE_EXPECTED)
        assertFalse(verdict(copy, home, null).passed)
    }

    @Test
    fun expectedTextMustBeOnTheScreenOutsideInputFields() {
        val search = step(
            StepAction.CLICK, expected = ExpectedOutcome.TEXT_VISIBLE, expectedValue = "results for cats"
        )
        val results = screen("chrome", node("Results for CATS"))
        assertTrue(verdict(search, home, results).passed)
        val onlyInBox = screen("chrome", node("results for cats", editable = true))
        assertFalse(verdict(search, home, onlyInBox).passed)
        assertFalse(verdict(search, home, chrome).passed)
    }

    @Test
    fun expectedTextIsAlsoFoundInDescriptions() {
        val send = step(StepAction.CLICK, expected = ExpectedOutcome.TEXT_VISIBLE, expectedValue = "Sent")
        assertTrue(verdict(send, home, screen("wa", node(null, description = "Sent"))).passed)
    }

    @Test
    fun expectedTextWithoutAValueFails() {
        val broken = step(StepAction.CLICK, expected = ExpectedOutcome.TEXT_VISIBLE)
        assertFalse(verdict(broken, home, chrome).passed)
    }

    @Test
    fun expectedAppMustBeInFront() {
        val open = step(StepAction.OPEN_APP, expected = ExpectedOutcome.APP_IN_FRONT, expectedValue = "chrome")
        assertTrue(verdict(open, home, chrome).passed)
        assertFalse(verdict(open, chrome, home).passed)
        val noPackage = step(StepAction.OPEN_APP, expected = ExpectedOutcome.APP_IN_FRONT)
        assertFalse(verdict(noPackage, home, chrome).passed)
    }

    // ------------------------------------------------------------ typed text

    @Test
    fun typedTextMustAppearInAnInputField() {
        val typed = screen("c", node("hello world", editable = true))
        assertTrue(verdict(step(StepAction.TYPE_TEXT, "hello world"), null, typed).passed)
        assertTrue(verdict(step(StepAction.TYPE_TEXT, " hello   world "), null, typed).passed)
        assertFalse(verdict(step(StepAction.TYPE_TEXT, "bye"), null, typed).passed)
        assertFalse(verdict(step(StepAction.TYPE_TEXT, " "), null, typed).passed)
        assertFalse(verdict(step(StepAction.TYPE_TEXT, "hello world"), null, screen("c", node("hello world"))).passed)
    }

    @Test
    fun typedDigitsAreComparedTheWayTheScreenReaderShowsThem() {
        val masked = SensitiveNodePolicy.maskCodes("12345")
        val typed = screen("c", node(masked, editable = true))
        assertTrue(verdict(step(StepAction.TYPE_TEXT, "12345"), null, typed).passed)
    }

    @Test
    fun waitConfirmAndSpeakNeedNoCheck() {
        for (action in listOf(StepAction.WAIT, StepAction.CONFIRM, StepAction.SPEAK)) {
            assertTrue(verdict(step(action), null, home).passed)
        }
    }
}
