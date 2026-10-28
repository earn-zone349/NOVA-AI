package com.nova.ai.tasks

import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.voice.LanguageDetector
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests the planner with the real rule-based brain, with the same wiring the app uses. */
class CommandPlannerBrainTest {

    private val brain = RuleBasedBrain()

    private val planner = CommandPlanner(analyze = { part ->
        brain.analyze(VoiceCommand(part, LanguageDetector.detect(part), 0L), emptyList()).getOrNull()
    })

    private fun types(text: String): List<IntentType> {
        val plan = planner.plan(text)
        assertTrue("Expected a plan for: $text", plan is NovaResult.Success)
        return (plan as NovaResult.Success).value.steps.map { it.intentType }
    }

    @Test
    fun banglaThreeStepCommandIsPlannedCorrectly() {
        assertEquals(
            listOf(IntentType.OPEN_APP, IntentType.SYSTEM_ACTION, IntentType.SYSTEM_ACTION),
            types("ক্রোম খোলো তারপর ভলিউম বাড়াও তারপর টর্চ জ্বালাও")
        )
    }

    @Test
    fun englishCommandIsPlannedCorrectly() {
        assertEquals(
            listOf(IntentType.OPEN_APP, IntentType.SYSTEM_ACTION),
            types("open chrome then turn on wifi")
        )
    }

    @Test
    fun callAndAlarmPartsAreRecognised() {
        assertEquals(
            listOf(IntentType.MAKE_CALL, IntentType.SET_ALARM),
            types("রহিমকে ফোন করো এরপর সকাল ৭টায় অ্যালার্ম দাও")
        )
    }

    @Test
    fun aPartThatIsNotUnderstoodRefusesTheWholeTask() {
        val plan = planner.plan("ক্রোম খোলো তারপর hello")
        assertTrue(plan is NovaResult.Failure)
        assertTrue((plan as NovaResult.Failure).error.message.contains("hello"))
    }
}
