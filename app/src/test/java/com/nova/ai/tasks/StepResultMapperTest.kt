package com.nova.ai.tasks

import com.nova.ai.bubble.BubbleOption
import com.nova.ai.bubble.BubbleOutput
import com.nova.ai.bubble.MessageKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Tests how a controller's answer becomes the result of a task step. Plain JVM test. */
class StepResultMapperTest {

    @Test
    fun nothingYetGivesNoResult() {
        assertNull(StepResultMapper.fromOutput(BubbleOutput.None))
    }

    @Test
    fun doneMessageIsSuccess() {
        assertEquals(
            StepResult.Done("ok"),
            StepResultMapper.fromOutput(BubbleOutput.Message("ok", MessageKind.DONE))
        )
    }

    @Test
    fun errorAndPlainInfoMessagesStopTheTask() {
        assertEquals(
            StepResult.Failed("bad"),
            StepResultMapper.fromOutput(BubbleOutput.Message("bad", MessageKind.ERROR))
        )
        assertEquals(
            StepResult.Failed("not found"),
            StepResultMapper.fromOutput(BubbleOutput.Message("not found", MessageKind.INFO))
        )
    }

    @Test
    fun anErrorTheAppReportedMayBeTriedAgainButOtherFailuresMayNot() {
        assertEquals(
            StepResult.Failed("could not open", FailureKind.RETRYABLE),
            StepResultMapper.fromOutput(BubbleOutput.Message("could not open", MessageKind.ERROR, retryable = true))
        )
        assertEquals(
            StepResult.Failed("not found", FailureKind.PERMANENT),
            StepResultMapper.fromOutput(BubbleOutput.Message("not found", MessageKind.INFO))
        )
    }

    @Test
    fun aGuidedInfoMessageMarkedCompletedIsSuccess() {
        assertEquals(
            StepResult.Done("screen opened"),
            StepResultMapper.fromOutput(BubbleOutput.Message("screen opened", MessageKind.INFO, completed = true))
        )
    }

    @Test
    fun aQuestionIsHandedToTheUser() {
        val decision = BubbleOutput.Decision(
            source = Any(),
            question = "which?",
            options = listOf(BubbleOption("A") {}, BubbleOption("B") {})
        )
        assertEquals(StepResult.NeedsUser("which?", listOf("A", "B")), StepResultMapper.fromOutput(decision))
    }

    @Test
    fun needingTheAppScreenStopsTheTask() {
        assertEquals(StepResult.Failed("allow it"), StepResultMapper.fromOutput(BubbleOutput.NeedsApp("allow it")))
    }
}
