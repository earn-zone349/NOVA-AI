package com.nova.ai.security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests the logic of the emergency stop. Plain JVM test, no phone needed. */
class EmergencyStopControllerTest {

    private var stopped = false
    private val errors = mutableListOf<String>()
    private val events = mutableListOf<String>()

    private fun controller() = EmergencyStopController(
        readStopped = { stopped },
        writeStopped = { stopped = it },
        onHookError = { key, _ -> errors.add(key) },
        onEvent = { events.add(it) }
    )

    @Test
    fun triggerSwitchesTheStopOnAndReleaseSwitchesItOff() {
        val c = controller()
        assertFalse(c.isActive)
        assertTrue(c.trigger("test"))
        assertTrue(c.isActive)
        assertTrue(c.release("test"))
        assertFalse(c.isActive)
    }

    @Test
    fun secondTriggerReportsNoChangeButStillRunsTheHooks() {
        val c = controller()
        var runs = 0
        c.registerHook("a") { runs += 1 }
        assertTrue(c.trigger("one"))
        assertFalse(c.trigger("two"))
        assertEquals(2, runs)
    }

    @Test
    fun releaseWhenNotStoppedReportsNoChange() {
        assertFalse(controller().release("test"))
    }

    @Test
    fun aFailingHookDoesNotBlockTheOthers() {
        val c = controller()
        var ran = false
        c.registerHook("bad") { throw IllegalStateException("boom") }
        c.registerHook("good") { ran = true }
        c.trigger("test")
        assertTrue(ran)
        assertEquals(listOf("bad"), errors)
        assertTrue(c.isActive)
    }

    @Test
    fun registeringTheSameKeyReplacesTheHook() {
        val c = controller()
        var first = 0
        var second = 0
        c.registerHook("k") { first += 1 }
        c.registerHook("k") { second += 1 }
        c.trigger("test")
        assertEquals(0, first)
        assertEquals(1, second)
    }

    @Test
    fun unregisteredHookDoesNotRun() {
        val c = controller()
        var runs = 0
        c.registerHook("k") { runs += 1 }
        c.unregisterHook("k")
        c.trigger("test")
        assertEquals(0, runs)
    }

    @Test
    fun listenersHearOnlyRealChanges() {
        val c = controller()
        val heard = mutableListOf<Boolean>()
        c.addListener { heard.add(it) }
        c.trigger("a")
        c.trigger("b")
        c.release("a")
        c.release("b")
        assertEquals(listOf(true, false), heard)
    }

    @Test
    fun removedListenerHearsNothing() {
        val c = controller()
        val heard = mutableListOf<Boolean>()
        val listener: (Boolean) -> Unit = { heard.add(it) }
        c.addListener(listener)
        c.removeListener(listener)
        c.trigger("a")
        assertTrue(heard.isEmpty())
    }

    @Test
    fun hooksMayRegisterAnotherHookWhileRunning() {
        val c = controller()
        var lateRuns = 0
        c.registerHook("first") { c.registerHook("late") { lateRuns += 1 } }
        c.trigger("a")
        assertEquals(0, lateRuns)
        c.trigger("b")
        assertEquals(1, lateRuns)
    }

    @Test
    fun theSourceIsLogged() {
        val c = controller()
        c.trigger("quick tile")
        assertTrue(events.single().contains("quick tile"))
    }
}
