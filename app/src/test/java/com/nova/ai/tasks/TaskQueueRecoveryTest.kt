package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaResult
import com.nova.ai.core.TaskStatus
import com.nova.ai.nlp.IntentAction
import com.nova.ai.nlp.IntentEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests retry, alternative paths and the question after a failure. Fake clock, fake phone. */
class TaskQueueRecoveryTest {

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

    private class FakeExecutor : StepExecutor {
        val started = mutableListOf<PlannedStep>()
        val answers = mutableListOf<Int>()
        var cancels = 0
        private var callback: ((StepResult) -> Unit)? = null

        override fun execute(step: PlannedStep, onResult: (StepResult) -> Unit) {
            started.add(step)
            callback = onResult
        }

        override fun answer(optionIndex: Int) { answers.add(optionIndex) }
        override fun cancel() { cancels += 1 }
        fun reply(result: StepResult) { callback?.invoke(result) }
        fun ids() = started.map { it.id }
    }

    private val clock = FakeScheduler()
    private val executor = FakeExecutor()
    private val timing = TaskTiming(gapMs = 100, settleAfterLaunchMs = 1000, stepTimeoutMs = 5000, questionTimeoutMs = 20000, betweenTasksMs = 300)
    private val policy = RetryPolicy(maxAttempts = 3, backoffMs = listOf(1000L, 2500L), askUserOnFailure = true)

    private fun queue(
        retry: RetryPolicy = policy,
        fallback: FallbackPlanner = NoFallback
    ) = TaskQueue(executor, clock, { }, timing, retry = retry, fallback = fallback)

    private fun step(n: Int, type: IntentType = IntentType.OPEN_APP, vararg entities: Pair<String, String>) =
        PlannedStep("s$n", "step $n", "cmd $n", type, entities = mapOf(*entities))

    private fun draft(vararg steps: PlannedStep) = TaskDraft("t1", "task", steps.toList())

    private fun TaskQueue.current() = snapshot().current!!

    private val retryable = StepResult.Failed("could not open", FailureKind.RETRYABLE)

    // ---------------------------------------------------------------- retry

    @Test
    fun aFailedStepIsTriedAgainAfterAShortWaitAndCanSucceed() {
        val q = queue()
        q.submit(draft(step(1), step(2)))
        executor.reply(retryable)
        assertEquals(StepState.RETRYING, q.current().steps[0].state)
        assertEquals(listOf("s1"), executor.ids())
        clock.advance(999)
        assertEquals(listOf("s1"), executor.ids())
        clock.advance(1)
        assertEquals(listOf("s1", "s1"), executor.ids())
        assertEquals(2, q.current().steps[0].attempt)
        executor.reply(StepResult.Done("opened"))
        assertEquals(StepState.DONE, q.current().steps[0].state)
        clock.advance(1000)
        assertEquals(listOf("s1", "s1", "s2"), executor.ids())
    }

    @Test
    fun theWaitGrowsBetweenTries() {
        val q = queue()
        q.submit(draft(step(1)))
        executor.reply(retryable)
        clock.advance(1000)
        executor.reply(retryable)
        clock.advance(2499)
        assertEquals(2, executor.started.size)
        clock.advance(1)
        assertEquals(3, executor.started.size)
    }

    @Test
    fun afterTheLastTryTheUserIsAsked() {
        val q = queue()
        q.submit(draft(step(1), step(2)))
        executor.reply(retryable)
        clock.advance(1000)
        executor.reply(retryable)
        clock.advance(2500)
        executor.reply(retryable)
        val task = q.current()
        assertEquals(TaskStatus.RUNNING, task.status)
        assertEquals(StepState.WAITING_USER, task.steps[0].state)
        assertEquals(
            listOf(TaskMessages.OPTION_RETRY, TaskMessages.OPTION_SKIP, TaskMessages.OPTION_CANCEL),
            task.question!!.options
        )
        assertEquals(3, executor.started.size)
    }

    @Test
    fun aPermanentFailureIsNotRepeatedButTheUserIsStillAsked() {
        val q = queue()
        q.submit(draft(step(1)))
        executor.reply(StepResult.Failed("not found", FailureKind.PERMANENT))
        assertEquals(1, executor.started.size)
        assertEquals(StepState.WAITING_USER, q.current().steps[0].state)
    }

    @Test
    fun silenceIsRepeatedForAnOpenAppStepButNotForACall() {
        val q = queue()
        q.submit(draft(step(1, IntentType.OPEN_APP)))
        clock.advance(5000)                               // step timeout
        assertEquals(StepState.RETRYING, q.current().steps[0].state)
        assertEquals(1, executor.cancels)
        clock.advance(1000)
        assertEquals(2, executor.started.size)
        q.cancelAll()

        val q2 = queue()
        executor.started.clear()
        q2.submit(draft(step(1, IntentType.MAKE_CALL)))
        clock.advance(5000)
        assertEquals(1, executor.started.size)
        assertEquals(StepState.WAITING_USER, q2.current().steps[0].state)
    }

    @Test
    fun withoutAPolicyAFailureStopsTheTaskLikeBefore() {
        val q = queue(retry = RetryPolicy.NONE)
        q.submit(draft(step(1), step(2)))
        executor.reply(retryable)
        assertEquals(TaskStatus.FAILED, q.current().status)
        assertEquals(StepState.SKIPPED, q.current().steps[1].state)
    }

    @Test
    fun aLateAnswerFromAFailedTryIsIgnored() {
        val q = queue()
        q.submit(draft(step(1)))
        clock.advance(5000)                               // timeout, retry starts later
        executor.reply(StepResult.Done("too late"))
        assertEquals(StepState.RETRYING, q.current().steps[0].state)
    }

    // ---------------------------------------------------------------- alternative path

    private class OneAlternative : FallbackPlanner {
        override fun alternativeFor(step: PlannedStep): PlannedStep? =
            if (step.isAlternative) null else PlannedStep(
                id = step.id + "-alt", title = step.title, command = step.command, intentType = step.intentType,
                kind = StepKind.OPEN_URL, url = "https://example.com", note = "opened the website", isAlternative = true
            )
    }

    @Test
    fun whenTheTriesAreUsedUpAnAlternativeIsTriedOnce() {
        val q = queue(fallback = OneAlternative())
        q.submit(draft(step(1)))
        executor.reply(StepResult.Failed("no app", FailureKind.PERMANENT))
        assertEquals(listOf("s1", "s1-alt"), executor.ids())
        assertEquals(StepKind.OPEN_URL, executor.started.last().kind)
        executor.reply(StepResult.Done("page opened"))
        val task = q.current()
        assertEquals(TaskStatus.COMPLETED, task.status)
        assertEquals("opened the website", task.steps[0].message)
    }

    @Test
    fun theAlternativeComesAfterTheRetries() {
        val q = queue(fallback = OneAlternative())
        q.submit(draft(step(1)))
        executor.reply(retryable)
        clock.advance(1000)
        executor.reply(retryable)
        clock.advance(2500)
        executor.reply(retryable)
        assertEquals(listOf("s1", "s1", "s1", "s1-alt"), executor.ids())
    }

    @Test
    fun aFailingAlternativeIsNotRepeatedAndTheUserIsAsked() {
        val q = queue(fallback = OneAlternative())
        q.submit(draft(step(1)))
        executor.reply(StepResult.Failed("no app", FailureKind.PERMANENT))
        executor.reply(StepResult.Failed("no browser", FailureKind.RETRYABLE))
        assertEquals(listOf("s1", "s1-alt"), executor.ids())
        assertEquals(StepState.WAITING_USER, q.current().steps[0].state)
        assertTrue(q.current().question!!.text.contains("no browser"))
    }

    @Test
    fun aFallbackThatThrowsIsIgnored() {
        val q = queue(fallback = object : FallbackPlanner {
            override fun alternativeFor(step: PlannedStep): PlannedStep? = throw IllegalStateException("boom")
        })
        q.submit(draft(step(1)))
        executor.reply(StepResult.Failed("no app", FailureKind.PERMANENT))
        assertEquals(StepState.WAITING_USER, q.current().steps[0].state)
    }

    // ---------------------------------------------------------------- the question after a failure

    private fun failedForGood(q: TaskQueue, vararg steps: PlannedStep) {
        q.submit(draft(*steps))
        executor.reply(StepResult.Failed("not found", FailureKind.PERMANENT))
    }

    @Test
    fun chosenRetryStartsTheStepAgainWithFreshTries() {
        val q = queue()
        failedForGood(q, step(1), step(2))
        assertTrue(q.answer(0) is NovaResult.Success)
        assertEquals(listOf("s1", "s1"), executor.ids())
        assertEquals(StepState.RUNNING, q.current().steps[0].state)
        assertNull(q.current().question)
        assertTrue(executor.answers.isEmpty())            // this answer is for the queue, not the phone
        executor.reply(StepResult.Done("ok"))
        clock.advance(1000)
        assertEquals(listOf("s1", "s1", "s2"), executor.ids())
    }

    @Test
    fun chosenSkipMovesOnAndTheTaskEndsWithTheSkipReported() {
        val q = queue()
        failedForGood(q, step(1), step(2, IntentType.SYSTEM_ACTION))
        q.answer(1)
        assertEquals(StepState.SKIPPED, q.current().steps[0].state)
        clock.advance(1000)
        assertEquals(listOf("s1", "s2"), executor.ids())
        executor.reply(StepResult.Done("ok"))
        val task = q.current()
        assertEquals(TaskStatus.COMPLETED, task.status)
        assertEquals(TaskMessages.doneWithSkips(1, 1), task.summary)
    }

    @Test
    fun chosenCancelEndsTheTask() {
        val q = queue()
        failedForGood(q, step(1), step(2))
        q.answer(2)
        assertEquals(TaskStatus.CANCELLED, q.current().status)
        clock.advance(10_000)
        assertEquals(listOf("s1"), executor.ids())
    }

    @Test
    fun theLastStepCannotBeSkipped() {
        val q = queue()
        failedForGood(q, step(1))
        assertEquals(listOf(TaskMessages.OPTION_RETRY, TaskMessages.OPTION_CANCEL), q.current().question!!.options)
    }

    @Test
    fun anUnansweredFailureQuestionEndsTheTaskAsFailed() {
        val q = queue()
        failedForGood(q, step(1), step(2))
        clock.advance(20_000)
        val task = q.current()
        assertEquals(TaskStatus.FAILED, task.status)
        assertEquals(StepState.FAILED, task.steps[0].state)
        assertEquals(StepState.SKIPPED, task.steps[1].state)
        assertEquals(TaskMessages.stoppedAt(1, 2, "not found", attempts = 1), task.summary)
    }

    @Test
    fun theFailureSummaryTellsHowOftenItWasTriedAndThatAnAlternativeFailedToo() {
        val q = queue(retry = RetryPolicy(maxAttempts = 2, backoffMs = listOf(10L), askUserOnFailure = false), fallback = OneAlternative())
        q.submit(draft(step(1)))
        executor.reply(retryable)
        clock.advance(10)
        executor.reply(retryable)
        executor.reply(StepResult.Failed("no browser", FailureKind.PERMANENT))
        val task = q.current()
        assertEquals(TaskStatus.FAILED, task.status)
        assertEquals(TaskMessages.stoppedAt(1, 1, "no browser", attempts = 3, triedAlternative = true), task.summary)
        assertTrue(task.summary!!.contains("3"))
    }

    // ---------------------------------------------------------------- cancel and pause

    @Test
    fun cancelDuringTheWaitBeforeARetryStopsEverything() {
        val q = queue()
        q.submit(draft(step(1)))
        executor.reply(retryable)
        q.cancel("t1")
        assertEquals(StepState.CANCELLED, q.current().steps[0].state)
        clock.advance(60_000)
        assertEquals(1, executor.started.size)
        assertEquals(0, clock.pendingCount())
    }

    @Test
    fun answeringWithABadNumberAfterAFailureIsRefused() {
        val q = queue()
        failedForGood(q, step(1), step(2))
        assertTrue(q.answer(9) is NovaResult.Failure)
        assertTrue(q.answer(-1) is NovaResult.Failure)
        assertEquals(StepState.WAITING_USER, q.current().steps[0].state)
    }

    @Test
    fun anOrdinaryQuestionStillGoesToThePhone() {
        val q = queue()
        q.submit(draft(step(1)))
        executor.reply(StepResult.NeedsUser("which?", listOf("A", "B")))
        q.answer(1)
        assertEquals(listOf(1), executor.answers)
    }

    @Test
    fun perTypeTimeoutsAreUsed() {
        val fastTiming = timing.copy(perTypeTimeoutMs = mapOf(IntentType.SYSTEM_ACTION to 1000L))
        val q = TaskQueue(executor, clock, { }, fastTiming)
        q.submit(draft(step(1, IntentType.SYSTEM_ACTION, IntentEntity.ACTION to IntentAction.UP)))
        clock.advance(1000)
        assertEquals(TaskStatus.FAILED, q.current().status)
    }
}
