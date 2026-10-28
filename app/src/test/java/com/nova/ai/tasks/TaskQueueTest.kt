package com.nova.ai.tasks

import com.nova.ai.core.ErrorCode
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaResult
import com.nova.ai.core.TaskStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests the task queue with a fake clock and a fake phone. Plain JVM test. */
class TaskQueueTest {

    /** A clock that only moves when the test says so. */
    private class FakeScheduler : Scheduler {
        private class Item(val at: Long, val task: () -> Unit) { var cancelled = false }
        private val items = mutableListOf<Item>()
        var now = 0L

        override fun postDelayed(delayMs: Long, task: () -> Unit): Cancellable {
            val item = Item(now + delayMs, task)
            items.add(item)
            return Cancellable { item.cancelled = true }
        }

        fun advance(ms: Long) {
            val target = now + ms
            while (true) {
                val next = items.filter { !it.cancelled && it.at <= target }.minByOrNull { it.at } ?: break
                items.remove(next)
                now = next.at
                next.task()
            }
            now = target
        }

        fun pendingCount() = items.count { !it.cancelled }
    }

    /** A phone that answers only when the test tells it to. */
    private class FakeExecutor : StepExecutor {
        val started = mutableListOf<String>()
        val answers = mutableListOf<Int>()
        var cancels = 0
        var throwOnExecute = false
        private var callback: ((StepResult) -> Unit)? = null

        override fun execute(step: PlannedStep, onResult: (StepResult) -> Unit) {
            if (throwOnExecute) throw IllegalStateException("boom")
            started.add(step.id)
            callback = onResult
        }

        override fun answer(optionIndex: Int) { answers.add(optionIndex) }
        override fun cancel() { cancels += 1 }
        fun reply(result: StepResult) { callback?.invoke(result) }
    }

    private val clock = FakeScheduler()
    private val executor = FakeExecutor()
    private val snapshots = mutableListOf<QueueSnapshot>()
    private val timing = TaskTiming(
        gapMs = 100, settleAfterLaunchMs = 1000, stepTimeoutMs = 5000, questionTimeoutMs = 20000, betweenTasksMs = 300
    )
    private val queue = TaskQueue(executor, clock, { snapshots.add(it) }, timing)

    private fun step(n: Int, type: IntentType = IntentType.SYSTEM_ACTION) =
        PlannedStep("s$n", "step $n", "cmd $n", type)

    private fun draft(id: String, vararg types: IntentType) =
        TaskDraft(id, "task $id", types.mapIndexed { i, t -> step(i + 1, t) })

    private fun threeSteps(id: String = "t1") =
        draft(id, IntentType.SYSTEM_ACTION, IntentType.SYSTEM_ACTION, IntentType.SYSTEM_ACTION)

    private fun current() = queue.snapshot().current!!

    @Test
    fun threeStepsRunInOrderAndTheTaskCompletes() {
        queue.submit(threeSteps())
        assertEquals(listOf("s1"), executor.started)
        executor.reply(StepResult.Done("one"))
        assertEquals(listOf("s1"), executor.started)          // waits for the gap
        clock.advance(100)
        assertEquals(listOf("s1", "s2"), executor.started)
        executor.reply(StepResult.Done("two"))
        clock.advance(100)
        executor.reply(StepResult.Done("three"))
        val task = current()
        assertEquals(TaskStatus.COMPLETED, task.status)
        assertEquals(3, task.doneCount)
        assertEquals(TaskMessages.allDone(3), task.summary)
        assertEquals(listOf("one", "two", "three"), task.steps.map { it.message })
    }

    @Test
    fun aStepThatOpensAnAppWaitsLongerBeforeTheNextOne() {
        queue.submit(draft("t1", IntentType.OPEN_APP, IntentType.SYSTEM_ACTION))
        executor.reply(StepResult.Done("opened"))
        clock.advance(999)
        assertEquals(listOf("s1"), executor.started)
        clock.advance(1)
        assertEquals(listOf("s1", "s2"), executor.started)
    }

    @Test
    fun aFailedStepStopsTheTaskAndSkipsTheRest() {
        queue.submit(threeSteps())
        executor.reply(StepResult.Done("one"))
        clock.advance(100)
        executor.reply(StepResult.Failed("no such app"))
        val task = current()
        assertEquals(TaskStatus.FAILED, task.status)
        assertEquals(
            listOf(StepState.DONE, StepState.FAILED, StepState.SKIPPED),
            task.steps.map { it.state }
        )
        assertEquals(TaskMessages.stoppedAt(2, 3, "no such app"), task.summary)
        clock.advance(10_000)
        assertEquals(listOf("s1", "s2"), executor.started)
    }

    @Test
    fun aStepThatNeverAnswersTimesOut() {
        queue.submit(threeSteps())
        clock.advance(5000)
        val task = current()
        assertEquals(TaskStatus.FAILED, task.status)
        assertEquals(TaskMessages.MSG_STEP_TIMEOUT, task.steps[0].message)
        assertEquals(1, executor.cancels)
    }

    @Test
    fun aQuestionWaitsForTheUserThenGoesOn() {
        queue.submit(threeSteps())
        executor.reply(StepResult.NeedsUser("which?", listOf("A", "B")))
        assertEquals(StepState.WAITING_USER, current().steps[0].state)
        assertEquals("which?", current().question?.text)
        // No step timeout while waiting for the user (5 s timeout, 20 s question time).
        clock.advance(6000)
        assertEquals(TaskStatus.RUNNING, current().status)

        assertTrue(queue.answer(1) is NovaResult.Success)
        assertEquals(listOf(1), executor.answers)
        assertNull(current().question)
        assertEquals(StepState.RUNNING, current().steps[0].state)
        executor.reply(StepResult.Done("opened B"))
        clock.advance(100)
        assertEquals(listOf("s1", "s2"), executor.started)
    }

    @Test
    fun anUnansweredQuestionCancelsTheTask() {
        queue.submit(threeSteps())
        executor.reply(StepResult.NeedsUser("which?", listOf("A")))
        clock.advance(20000)
        val task = current()
        assertEquals(TaskStatus.CANCELLED, task.status)
        assertEquals(TaskMessages.MSG_QUESTION_TIMEOUT, task.summary)
        assertEquals(1, executor.cancels)
    }

    @Test
    fun answeringWithoutAQuestionOrWithABadNumberFails() {
        assertEquals(ErrorCode.NOT_FOUND, (queue.answer(0) as NovaResult.Failure).error.code)
        queue.submit(threeSteps())
        assertEquals(ErrorCode.INVALID_INPUT, (queue.answer(0) as NovaResult.Failure).error.code)
        executor.reply(StepResult.NeedsUser("which?", listOf("A", "B")))
        assertEquals(ErrorCode.INVALID_INPUT, (queue.answer(5) as NovaResult.Failure).error.code)
        assertEquals(ErrorCode.INVALID_INPUT, (queue.answer(-1) as NovaResult.Failure).error.code)
        assertTrue(executor.answers.isEmpty())
    }

    @Test
    fun aQuestionWithoutOptionsFailsTheStep() {
        queue.submit(threeSteps())
        executor.reply(StepResult.NeedsUser("nothing to pick", emptyList()))
        assertEquals(TaskStatus.FAILED, current().status)
    }

    @Test
    fun cancelStopsTheRunningTask() {
        queue.submit(threeSteps())
        executor.reply(StepResult.Done("one"))
        assertTrue(queue.cancel("t1") is NovaResult.Success)
        val task = current()
        assertEquals(TaskStatus.CANCELLED, task.status)
        assertEquals(listOf(StepState.DONE, StepState.CANCELLED, StepState.CANCELLED), task.steps.map { it.state })
        clock.advance(10_000)
        assertEquals(listOf("s1"), executor.started)
        assertEquals(1, executor.cancels)
    }

    @Test
    fun aLateAnswerAfterCancelIsIgnored() {
        queue.submit(threeSteps())
        queue.cancel("t1")
        executor.reply(StepResult.Done("too late"))
        assertEquals(TaskStatus.CANCELLED, current().status)
        assertEquals(StepState.CANCELLED, current().steps[0].state)
    }

    @Test
    fun cancelOfAnUnknownTaskFails() {
        assertEquals(ErrorCode.NOT_FOUND, (queue.cancel("nope") as NovaResult.Failure).error.code)
    }

    @Test
    fun pauseHoldsTheTaskBeforeItsNextStepAndResumeContinues() {
        queue.submit(threeSteps())
        assertTrue(queue.pause("t1") is NovaResult.Success)
        assertEquals(TaskStatus.PAUSED, queue.status("t1"))
        executor.reply(StepResult.Done("one"))   // the running step still finishes
        clock.advance(10_000)
        assertEquals(listOf("s1"), executor.started)
        assertTrue(queue.resume("t1") is NovaResult.Success)
        assertEquals(listOf("s1", "s2"), executor.started)
        assertEquals(TaskStatus.RUNNING, queue.status("t1"))
    }

    @Test
    fun resumeBeforeTheStepFinishedLetsTheGapRunNormally() {
        queue.submit(threeSteps())
        queue.pause("t1")
        queue.resume("t1")
        executor.reply(StepResult.Done("one"))
        clock.advance(100)
        assertEquals(listOf("s1", "s2"), executor.started)
    }

    @Test
    fun pauseAndResumeCheckTheState() {
        assertEquals(ErrorCode.NOT_FOUND, (queue.pause("x") as NovaResult.Failure).error.code)
        queue.submit(threeSteps())
        assertEquals(ErrorCode.INVALID_INPUT, (queue.resume("t1") as NovaResult.Failure).error.code)
        queue.pause("t1")
        assertEquals(ErrorCode.INVALID_INPUT, (queue.pause("t1") as NovaResult.Failure).error.code)
    }

    @Test
    fun secondTaskWaitsThenStartsAfterTheFirstResultShowed() {
        queue.submit(draft("t1", IntentType.SYSTEM_ACTION))
        queue.submit(draft("t2", IntentType.SYSTEM_ACTION))
        assertEquals(TaskStatus.PENDING, queue.status("t2"))
        assertEquals(listOf("task t2"), queue.snapshot().waiting)
        executor.reply(StepResult.Done("one"))
        assertEquals("t1", current().id)                  // the result of t1 is still shown
        assertEquals(TaskStatus.COMPLETED, current().status)
        clock.advance(300)
        assertEquals("t2", current().id)
        assertEquals(listOf("s1", "s1"), executor.started)
        assertTrue(queue.snapshot().waiting.isEmpty())
    }

    @Test
    fun aFailedTaskDoesNotBlockTheNextOne() {
        queue.submit(draft("t1", IntentType.SYSTEM_ACTION))
        queue.submit(draft("t2", IntentType.SYSTEM_ACTION))
        executor.reply(StepResult.Failed("bad"))
        clock.advance(300)
        assertEquals("t2", current().id)
        assertEquals(TaskStatus.RUNNING, current().status)
    }

    @Test
    fun theLineHasALimit() {
        queue.submit(draft("running", IntentType.SYSTEM_ACTION))
        for (i in 1..TaskQueue.MAX_WAITING) assertTrue(queue.submit(draft("w$i", IntentType.SYSTEM_ACTION)) is NovaResult.Success)
        val full = queue.submit(draft("extra", IntentType.SYSTEM_ACTION)) as NovaResult.Failure
        assertEquals(ErrorCode.TEMPORARY_FAILURE, full.error.code)
    }

    @Test
    fun aWaitingTaskCanBeCancelled() {
        queue.submit(draft("t1", IntentType.SYSTEM_ACTION))
        queue.submit(draft("t2", IntentType.SYSTEM_ACTION))
        assertTrue(queue.cancel("t2") is NovaResult.Success)
        assertTrue(queue.snapshot().waiting.isEmpty())
        assertNull(queue.status("t2"))
    }

    @Test
    fun cancelAllStopsEverythingAndNothingStartsLater() {
        queue.submit(threeSteps("t1"))
        queue.submit(threeSteps("t2"))
        queue.cancelAll()
        assertEquals(TaskStatus.CANCELLED, current().status)
        assertTrue(queue.snapshot().waiting.isEmpty())
        clock.advance(60_000)
        assertEquals(listOf("s1"), executor.started)
        assertEquals(0, clock.pendingCount())
    }

    @Test
    fun cancelAllAlsoClearsATaskThatWaitsForTheNextSlot() {
        queue.submit(draft("t1", IntentType.SYSTEM_ACTION))
        queue.submit(draft("t2", IntentType.SYSTEM_ACTION))
        executor.reply(StepResult.Done("one"))         // t2 now waits for its slot
        queue.cancelAll()
        clock.advance(60_000)
        assertEquals(listOf("s1"), executor.started)
    }

    @Test
    fun anExecutorThatThrowsFailsTheStepCleanly() {
        executor.throwOnExecute = true
        queue.submit(threeSteps())
        val task = current()
        assertEquals(TaskStatus.FAILED, task.status)
        assertEquals(TaskMessages.MSG_START_FAILED, task.steps[0].message)
    }

    @Test
    fun anEmptyTaskIsRefused() {
        val result = queue.submit(TaskDraft("e", "empty", emptyList())) as NovaResult.Failure
        assertEquals(ErrorCode.INVALID_INPUT, result.error.code)
    }

    @Test
    fun aDuplicateResultForTheSameStepIsIgnored() {
        queue.submit(threeSteps())
        executor.reply(StepResult.Done("one"))
        executor.reply(StepResult.Failed("duplicate"))
        clock.advance(100)
        assertEquals(StepState.DONE, current().steps[0].state)
        assertEquals(listOf("s1", "s2"), executor.started)
    }

    @Test
    fun dismissClearsTheFinishedResult() {
        queue.submit(draft("t1", IntentType.SYSTEM_ACTION))
        executor.reply(StepResult.Done("one"))
        queue.dismissFinished()
        assertNull(queue.snapshot().current)
    }

    @Test
    fun aNewTaskAfterAFinishedOneStartsAtOnce() {
        queue.submit(draft("t1", IntentType.SYSTEM_ACTION))
        executor.reply(StepResult.Done("one"))
        queue.submit(draft("t2", IntentType.SYSTEM_ACTION))
        assertEquals("t2", current().id)
        assertEquals(listOf("s1", "s1"), executor.started)
    }

    @Test
    fun theListenerIsToldAboutChangesAndAFailingListenerDoesNotBreakTheQueue() {
        val broken = TaskQueue(executor, clock, { throw IllegalStateException("ui crashed") }, timing)
        broken.submit(threeSteps("b1"))
        executor.reply(StepResult.Done("one"))
        clock.advance(100)
        assertEquals(listOf("s1", "s2"), executor.started)
        queue.submit(threeSteps("t1"))
        assertTrue(snapshots.isNotEmpty())
    }
}
