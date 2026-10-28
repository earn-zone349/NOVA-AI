package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaResult
import com.nova.ai.core.TaskStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests the history record, its text form, the database row, the recorder and the rerun. */
class TaskHistoryTest {

    private fun step(n: Int, type: IntentType = IntentType.OPEN_APP, vararg e: Pair<String, String>) =
        PlannedStep("s$n", "ধাপ $n", "কমান্ড $n", type, entities = mapOf(*e))

    private fun draft(id: String = "t1") = TaskDraft(id, "কাজ", listOf(step(1, IntentType.OPEN_APP, "app" to "ক্রোম"), step(2), step(3)))

    private fun snap(id: String, status: TaskStatus, vararg states: StepState) = QueueSnapshot(
        TaskSnapshot(
            id, "কাজ", status,
            states.mapIndexed { i, s -> StepSnapshot("s${i + 1}", "ধাপ ${i + 1}", s, if (s == StepState.FAILED) "ব্যর্থ" else null, 1, 3) },
            null, "সারাংশ"
        ),
        emptyList()
    )

    private fun item(status: TaskStatus = TaskStatus.FAILED) =
        HistoryItem.from(draft(), snap("t1", status, StepState.DONE, StepState.FAILED, StepState.CANCELLED).current!!, 1000L)

    @Test
    fun itemKeepsPlanAndResult() {
        val i = item()
        assertEquals(3, i.steps.size)
        assertEquals(StepState.DONE, i.steps[0].state)
        assertEquals("ব্যর্থ", i.steps[1].message)
        assertEquals("ক্রোম", i.steps[0].entities["app"])
        assertEquals(1000L, i.finishedAtMs)
    }

    @Test
    fun codecRoundTripKeepsEverything() {
        val i = item()
        val (summary, steps) = HistoryCodec.decode(HistoryCodec.encode(i))
        assertEquals("সারাংশ", summary)
        assertEquals(i.steps, steps)
    }

    @Test
    fun codecRemovesSeparatorsFromTexts() {
        val bad = HistoryItem("x", "t", TaskStatus.FAILED, "a\u001Eb", 1L,
            listOf(HistoryStep("t\u001Fx", "c\u001Dd", IntentType.OPEN_APP, mapOf("k\u001C" to "v\u001E"), StepState.FAILED, "m\u001F")))
        val (summary, steps) = HistoryCodec.decode(HistoryCodec.encode(bad))
        assertEquals("a b", summary)
        assertEquals(1, steps.size)
        assertEquals("t x", steps[0].title)
        assertEquals(mapOf("k " to "v "), steps[0].entities)
    }

    @Test
    fun damagedOrUnknownDetailGivesNothing() {
        assertEquals(null to emptyList<HistoryStep>(), HistoryCodec.decode(null))
        assertEquals(null to emptyList<HistoryStep>(), HistoryCodec.decode(""))
        assertEquals(null to emptyList<HistoryStep>(), HistoryCodec.decode("9\u001Fx"))
        val (_, steps) = HistoryCodec.decode("1\u001F\u001Ea\u001Fb\u001FNO_SUCH\u001FDONE\u001F\u001F")
        assertTrue(steps.isEmpty())
    }

    @Test
    fun rowRoundTripAndUnknownStatus() {
        val i = item()
        val row = HistoryRow.from(i)
        assertEquals("FAILED", row.status)
        assertEquals(3, row.stepCount)
        assertEquals(i, row.toItem())
        assertNull(row.copy(status = "FUTURE_STATUS").toItem())
    }

    @Test
    fun rerunKeepsOnlyUnfinishedStepsInOrder() {
        val d = item().toRerunDraft("new")!!
        assertEquals("new", d.id)
        assertEquals(TaskMessages.rerunTitle("কাজ"), d.title)
        assertEquals(listOf("কমান্ড 2", "কমান্ড 3"), d.steps.map { it.command })
        assertEquals(listOf("s1", "s2"), d.steps.map { it.id })
    }

    @Test
    fun completedTaskCannotBeRerun() {
        val done = HistoryItem.from(draft(), snap("t1", TaskStatus.COMPLETED, StepState.DONE, StepState.DONE, StepState.DONE).current!!, 1L)
        assertFalse(done.canRerun)
        assertNull(done.toRerunDraft("n"))
        assertTrue(item(TaskStatus.CANCELLED).canRerun)
    }

    @Test
    fun recorderSavesAFinishedTaskOnce() {
        val r = HistoryRecorder { 5L }
        r.remember(draft())
        assertNull(r.onSnapshot(snap("t1", TaskStatus.RUNNING, StepState.RUNNING, StepState.PENDING, StepState.PENDING)))
        val saved = r.onSnapshot(snap("t1", TaskStatus.FAILED, StepState.DONE, StepState.FAILED, StepState.CANCELLED))
        assertNotNull(saved)
        assertEquals(5L, saved!!.finishedAtMs)
        assertNull(r.onSnapshot(snap("t1", TaskStatus.FAILED, StepState.DONE, StepState.FAILED, StepState.CANCELLED)))
        assertNull(r.onSnapshot(QueueSnapshot.EMPTY))
    }

    @Test
    fun recorderIgnoresATaskItDoesNotKnow() {
        val r = HistoryRecorder { 5L }
        assertNull(r.onSnapshot(snap("other", TaskStatus.COMPLETED, StepState.DONE)))
    }

    @Test
    fun rerunThroughTheQueueFinishesTheRemainingSteps() {
        val started = mutableListOf<String>()
        var callback: ((StepResult) -> Unit)? = null
        val executor = object : StepExecutor {
            override fun execute(step: PlannedStep, onResult: (StepResult) -> Unit) { started.add(step.command); callback = onResult }
            override fun answer(optionIndex: Int) {}
            override fun cancel() {}
        }
        val scheduler = object : Scheduler {
            override fun postDelayed(delayMs: Long, task: () -> Unit): Cancellable = Cancellable { }
        }
        val q = TaskQueue(executor, scheduler, { }, TaskTiming(), retry = RetryPolicy.NONE)
        val result = q.submit(item().toRerunDraft("again")!!)
        assertTrue(result is NovaResult.Success)
        assertEquals(listOf("কমান্ড 2"), started)
        assertEquals(2, q.snapshot().current!!.steps.size)
    }
}
