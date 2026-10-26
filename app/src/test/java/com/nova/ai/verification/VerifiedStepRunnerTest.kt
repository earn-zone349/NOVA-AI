package com.nova.ai.verification

import com.nova.ai.accessibility.AccessibilityEngine
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenBounds
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.ScrollDirection
import com.nova.ai.core.StepAction
import com.nova.ai.core.TaskStep
import com.nova.ai.core.VerificationReport
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests the look-again loop of [VerifiedStepRunner] with a fake screen and a fake clock. */
class VerifiedStepRunnerTest {

    /** A screen that returns the given captures one after another (the last one repeats). */
    private class FakeScreen(private val captures: List<NovaResult<ScreenSnapshot>>) : AccessibilityEngine {
        var captureCalls: Int = 0
            private set

        override fun isServiceEnabled(): Boolean = true

        override fun captureScreen(): NovaResult<ScreenSnapshot> {
            val result = captures[minOf(captureCalls, captures.size - 1)]
            captureCalls += 1
            return result
        }

        override fun click(node: ScreenNode): NovaResult<Unit> = NovaResult.Success(Unit)
        override fun typeText(node: ScreenNode, text: String): NovaResult<Unit> = NovaResult.Success(Unit)
        override fun scroll(direction: ScrollDirection): NovaResult<Unit> = NovaResult.Success(Unit)
        override fun pressBack(): NovaResult<Unit> = NovaResult.Success(Unit)
        override fun pressHome(): NovaResult<Unit> = NovaResult.Success(Unit)
    }

    private fun shot(packageName: String, label: String): NovaResult<ScreenSnapshot> {
        val node = ScreenNode(label, null, "android.widget.Button", packageName, true, false, false, ScreenBounds(0, 0, 10, 10))
        return NovaResult.Success(ScreenSnapshot(packageName, listOf(node), 0L))
    }

    private val home = shot("launcher", "Chrome")
    private val chrome = shot("chrome", "Search")
    private val click = TaskStep("s1", StepAction.CLICK)
    private var sleeps = 0
    private val sleeper: (Long) -> Unit = { sleeps += 1 }

    private fun report(result: NovaResult<VerificationReport>): VerificationReport = when (result) {
        is NovaResult.Success -> result.value
        is NovaResult.Failure -> throw AssertionError(result.error.message)
    }

    @Test
    fun passesRightAwayWhenTheScreenChangesAtOnce() {
        val screen = FakeScreen(listOf(home, chrome))
        val result = VerifiedStepRunner(screen, sleep = sleeper).run(click) { NovaResult.Success(Unit) }
        assertTrue(report(result).passed)
        assertEquals(0, sleeps)
        assertEquals(2, screen.captureCalls)
    }

    @Test
    fun waitsAndSeesAChangeThatComesLate() {
        val screen = FakeScreen(listOf(home, home, home, chrome))
        val result = VerifiedStepRunner(screen, sleep = sleeper).run(click) { NovaResult.Success(Unit) }
        assertTrue(report(result).passed)
        assertEquals(2, sleeps)
    }

    @Test
    fun reportsFailureAfterEightLooksWhenNothingChanges() {
        val screen = FakeScreen(listOf(home))
        val result = VerifiedStepRunner(screen, sleep = sleeper).run(click) { NovaResult.Success(Unit) }
        assertFalse(report(result).passed)
        assertEquals(7, sleeps)
        assertEquals(9, screen.captureCalls)
    }

    @Test
    fun handsBackAnActionFailureUnchanged() {
        val screen = FakeScreen(listOf(home))
        val result = VerifiedStepRunner(screen, sleep = sleeper)
            .run(click) { NovaResult.failure(ErrorCode.SECURITY_BLOCKED, "stop") }
        assertTrue(result is NovaResult.Failure)
        assertEquals(ErrorCode.SECURITY_BLOCKED, (result as NovaResult.Failure).error.code)
        assertEquals(1, screen.captureCalls)
    }

    @Test
    fun anUnreadableScreenAfterwardsIsNotAPass() {
        val screen = FakeScreen(listOf(home, NovaResult.failure(ErrorCode.NOT_AVAILABLE, "no")))
        val result = VerifiedStepRunner(screen, sleep = sleeper).run(click) { NovaResult.Success(Unit) }
        assertFalse(report(result).passed)
    }

    @Test
    fun anInterruptStopsTheCheckAsCancelled() {
        val screen = FakeScreen(listOf(home))
        val runner = VerifiedStepRunner(screen, sleep = { throw InterruptedException() })
        val result = runner.run(click) { NovaResult.Success(Unit) }
        // Clear the flag the runner sets again, so it does not leak into other tests.
        Thread.interrupted()
        assertTrue(result is NovaResult.Failure)
        assertEquals(ErrorCode.CANCELLED, (result as NovaResult.Failure).error.code)
    }
}
