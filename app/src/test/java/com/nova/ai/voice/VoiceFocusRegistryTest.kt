package com.nova.ai.voice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests that only one voice user listens at a time. Plain JVM test. */
class VoiceFocusRegistryTest {

    @Test
    fun claimStopsEveryoneElseButNotTheClaimer() {
        val registry = VoiceFocusRegistry()
        val stopped = mutableListOf<String>()
        registry.register("home") { stopped.add("home") }
        registry.register("bubble") { stopped.add("bubble") }
        registry.claim("bubble")
        assertEquals(listOf("home"), stopped)
    }

    @Test
    fun stopAllStopsEveryone() {
        val registry = VoiceFocusRegistry()
        val stopped = mutableListOf<String>()
        registry.register("home") { stopped.add("home") }
        registry.register("bubble") { stopped.add("bubble") }
        registry.stopAll()
        assertEquals(listOf("home", "bubble"), stopped)
    }

    @Test
    fun unregisteredOwnerIsNotStopped() {
        val registry = VoiceFocusRegistry()
        var runs = 0
        registry.register("home") { runs += 1 }
        registry.unregister("home")
        registry.stopAll()
        assertEquals(0, runs)
    }

    @Test
    fun aFailingStopIsReportedAndOthersStillRun() {
        val failed = mutableListOf<String>()
        val registry = VoiceFocusRegistry { owner, _ -> failed.add(owner) }
        var ran = false
        registry.register("bad") { throw IllegalStateException("boom") }
        registry.register("good") { ran = true }
        registry.stopAll()
        assertTrue(ran)
        assertEquals(listOf("bad"), failed)
    }

    @Test
    fun registeringAgainReplacesTheStopAction() {
        val registry = VoiceFocusRegistry()
        var old = 0
        var new = 0
        registry.register("home") { old += 1 }
        registry.register("home") { new += 1 }
        registry.stopAll()
        assertEquals(0, old)
        assertEquals(1, new)
    }
}
