package com.nova.ai.tasks

import com.nova.ai.core.TaskStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests what a control word means for the queue as it is now. */
class TaskControlPlannerTest {

    private fun task(status: TaskStatus, states: List<StepState>, question: PendingQuestion? = null) = TaskSnapshot(
        id = "t1", title = "কাজ", status = status,
        steps = states.mapIndexed { i, s -> StepSnapshot("s$i", "ধাপ ${i + 1}", s, null, 1, 3) },
        question = question, summary = null
    )

    private fun queue(task: TaskSnapshot?, waiting: List<String> = emptyList()) = QueueSnapshot(task, waiting)

    private val running = task(TaskStatus.RUNNING, listOf(StepState.DONE, StepState.RUNNING, StepState.PENDING))
    private val paused = task(TaskStatus.PAUSED, listOf(StepState.DONE, StepState.PENDING))
    private val failed = task(TaskStatus.FAILED, listOf(StepState.DONE, StepState.FAILED))

    @Test
    fun pauseWorksOnARunningTask() {
        val d = TaskControlPlanner.decide(TaskControlCommand.PAUSE, queue(running), 0)!!
        assertEquals(ControlAction.PAUSE, d.action)
        assertEquals(TaskMessages.MSG_PAUSED, d.reply)
    }

    @Test
    fun pauseOnAPausedTaskOnlyTellsIt() {
        val d = TaskControlPlanner.decide(TaskControlCommand.PAUSE, queue(paused), 0)!!
        assertEquals(ControlAction.NONE, d.action)
        assertEquals(TaskMessages.MSG_ALREADY_PAUSED, d.reply)
    }

    @Test
    fun pauseWithoutATaskIsNotHandled() {
        assertNull(TaskControlPlanner.decide(TaskControlCommand.PAUSE, queue(null), 0))
        assertNull(TaskControlPlanner.decide(TaskControlCommand.PAUSE, queue(failed), 0))
    }

    @Test
    fun resumeOnlyWorksOnAPausedTask() {
        assertEquals(ControlAction.RESUME, TaskControlPlanner.decide(TaskControlCommand.RESUME, queue(paused), 0)!!.action)
        assertNull(TaskControlPlanner.decide(TaskControlCommand.RESUME, queue(running), 0))
        assertNull(TaskControlPlanner.decide(TaskControlCommand.RESUME, queue(null), 0))
    }

    @Test
    fun cancelNeedsATaskAndCancelAllAlsoCountsTheLine() {
        assertEquals(ControlAction.CANCEL_CURRENT, TaskControlPlanner.decide(TaskControlCommand.CANCEL_CURRENT, queue(running), 0)!!.action)
        assertNull(TaskControlPlanner.decide(TaskControlCommand.CANCEL_CURRENT, queue(null), 0))
        assertEquals(ControlAction.CANCEL_ALL, TaskControlPlanner.decide(TaskControlCommand.CANCEL_ALL, queue(null, listOf("x")), 0)!!.action)
        assertNull(TaskControlPlanner.decide(TaskControlCommand.CANCEL_ALL, queue(null), 0))
    }

    @Test
    fun rerunNeedsAnIdleQueueAndUnfinishedSteps() {
        val d = TaskControlPlanner.decide(TaskControlCommand.RERUN, queue(failed), 2)!!
        assertEquals(ControlAction.RERUN, d.action)
        assertEquals(TaskMessages.rerunStarted(2), d.reply)
        assertNull(TaskControlPlanner.decide(TaskControlCommand.RERUN, queue(failed), 0))
        assertNull(TaskControlPlanner.decide(TaskControlCommand.RERUN, queue(running), 2))
    }

    @Test
    fun statusTellsTheProgress() {
        val d = TaskControlPlanner.decide(TaskControlCommand.STATUS, queue(running), 0)!!
        assertEquals(ControlAction.NONE, d.action)
        assertEquals(TaskMessages.statusRunning(1, 3, "ধাপ 2"), d.reply)
        assertEquals(TaskMessages.statusPaused(1, 2), TaskControlPlanner.decide(TaskControlCommand.STATUS, queue(paused), 0)!!.reply)
        val asking = task(TaskStatus.RUNNING, listOf(StepState.WAITING_USER), PendingQuestion("?", listOf("a")))
        assertEquals(TaskMessages.statusQuestion(0, 1), TaskControlPlanner.decide(TaskControlCommand.STATUS, queue(asking), 0)!!.reply)
        assertNull(TaskControlPlanner.decide(TaskControlCommand.STATUS, queue(null), 0))
        assertTrue(TaskMessages.statusRunning(1, 3, "x").contains("1/3"))
    }
}
