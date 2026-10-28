package com.nova.ai.tasks

import com.nova.ai.core.ErrorCode
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests how a spoken command becomes a task. Plain JVM test. */
class CommandPlannerTest {

    // A tiny fake brain: knows a few words.
    private val known: Map<String, IntentType> = mapOf(
        "open chrome" to IntentType.OPEN_APP,
        "volume up" to IntentType.SYSTEM_ACTION,
        "call rahim" to IntentType.MAKE_CALL,
        "mumble" to IntentType.UNKNOWN
    )

    private val planner = CommandPlanner(
        analyze = { part -> known[part]?.let { NovaIntent(it, emptyMap(), 0.9f) } },
        newId = { "task-1" }
    )

    private fun draftOf(result: NovaResult<TaskDraft>): TaskDraft = when (result) {
        is NovaResult.Success -> result.value
        is NovaResult.Failure -> throw AssertionError("Expected a plan but got: ${result.error.message}")
    }

    private fun failureOf(result: NovaResult<TaskDraft>): com.nova.ai.core.NovaError = when (result) {
        is NovaResult.Failure -> result.error
        is NovaResult.Success -> throw AssertionError("Expected a failure")
    }

    @Test
    fun threePartsBecomeThreeStepsInOrder() {
        val draft = draftOf(planner.plan("open chrome then volume up then call rahim"))
        assertEquals("task-1", draft.id)
        assertEquals(listOf("s1", "s2", "s3"), draft.steps.map { it.id })
        assertEquals(listOf("open chrome", "volume up", "call rahim"), draft.steps.map { it.command })
        assertEquals(
            listOf(IntentType.OPEN_APP, IntentType.SYSTEM_ACTION, IntentType.MAKE_CALL),
            draft.steps.map { it.intentType }
        )
    }

    @Test
    fun oneUnknownPartRefusesTheWholePlanAndNamesIt() {
        val error = failureOf(planner.plan("open chrome then mumble then volume up"))
        assertEquals(ErrorCode.INVALID_INPUT, error.code)
        assertTrue(error.message.contains("mumble"))
    }

    @Test
    fun aPartTheBrainDoesNotKnowAtAllIsRefused() {
        val error = failureOf(planner.plan("open chrome then something else"))
        assertTrue(error.message.contains("something else"))
    }

    @Test
    fun aBrainThatThrowsIsTreatedAsUnknown() {
        val crashing = CommandPlanner(analyze = { throw IllegalStateException("boom") })
        val error = failureOf(crashing.plan("open chrome then volume up"))
        assertEquals(ErrorCode.INVALID_INPUT, error.code)
    }

    @Test
    fun emptyCommandIsRefused() {
        assertEquals(ErrorCode.INVALID_INPUT, failureOf(planner.plan("  ")).code)
        assertEquals(ErrorCode.INVALID_INPUT, failureOf(planner.plan("then")).code)
    }

    @Test
    fun tooManyStepsAreRefused() {
        val text = (1..9).joinToString(" then ") { "volume up" }
        val error = failureOf(planner.plan(text))
        assertEquals(ErrorCode.INVALID_INPUT, error.code)
        assertTrue(error.message.contains(CommandPlanner.MAX_STEPS.toString()))
    }

    @Test
    fun exactlyTheMaximumIsAccepted() {
        val text = (1..CommandPlanner.MAX_STEPS).joinToString(" then ") { "volume up" }
        assertEquals(CommandPlanner.MAX_STEPS, draftOf(planner.plan(text)).steps.size)
    }

    @Test
    fun aSingleKnownCommandMakesAOneStepPlanButIsNotMultiStep() {
        assertEquals(1, draftOf(planner.plan("open chrome")).steps.size)
        assertTrue(!planner.isMultiStep("open chrome"))
        assertTrue(planner.isMultiStep("open chrome then volume up"))
    }

    @Test
    fun longTitlesAreShortened() {
        val long = "open chrome then " + "volume up then ".repeat(3) + "volume up"
        val title = draftOf(planner.plan(long)).title
        assertNotNull(title)
        assertTrue(title.length <= 60)
    }

    @Test
    fun generatedIdsDifferBetweenPlans() {
        val real = CommandPlanner(analyze = { NovaIntent(IntentType.OPEN_APP, emptyMap(), 1f) })
        val a = draftOf(real.plan("x then y")).id
        val b = draftOf(real.plan("x then y")).id
        assertTrue(a != b)
    }
}
