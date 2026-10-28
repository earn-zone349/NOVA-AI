package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.nlp.IntentEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests the alternative paths (website instead of app, browser search). Plain JVM test. */
class WebFallbackPlannerTest {

    private fun step(type: IntentType, vararg entities: Pair<String, String>) = PlannedStep(
        id = "s2", title = "t", command = "c", intentType = type, entities = mapOf(*entities)
    )

    @Test
    fun anAppThatCannotBeOpenedIsOpenedAsAWebsite() {
        val alt = WebFallbackPlanner.alternativeFor(step(IntentType.OPEN_APP, IntentEntity.APP to "Facebook"))!!
        assertEquals(StepKind.OPEN_URL, alt.kind)
        assertEquals("https://www.facebook.com", alt.url)
        assertEquals("s2-alt", alt.id)
        assertTrue(alt.isAlternative)
        assertNotNull(alt.note)
    }

    @Test
    fun appNamesAreMatchedIgnoringCase() {
        assertEquals(
            "https://www.youtube.com",
            WebFallbackPlanner.alternativeFor(step(IntentType.OPEN_APP, IntentEntity.APP to "YouTube"))!!.url
        )
    }

    @Test
    fun anAppWithoutAWebsiteHasNoAlternative() {
        assertNull(WebFallbackPlanner.alternativeFor(step(IntentType.OPEN_APP, IntentEntity.APP to "Calculator")))
        assertNull(WebFallbackPlanner.alternativeFor(step(IntentType.OPEN_APP)))
    }

    @Test
    fun aSearchThatFailedInAnAppIsDoneInTheBrowser() {
        val alt = WebFallbackPlanner.alternativeFor(
            step(IntentType.WEB_SEARCH, IntentEntity.APP to "Chrome", IntentEntity.QUERY to "free 3d model")
        )!!
        assertEquals("https://www.google.com/search?q=free+3d+model", alt.url)
    }

    @Test
    fun aYouTubeSearchGoesToYouTubeResults() {
        val alt = WebFallbackPlanner.alternativeFor(
            step(IntentType.WEB_SEARCH, IntentEntity.APP to "YouTube", IntentEntity.QUERY to "গান")
        )!!
        assertTrue(alt.url!!.startsWith("https://www.youtube.com/results?search_query="))
        assertTrue(alt.url!!.contains("%E0%A6%97")) // the Bangla word is encoded
    }

    @Test
    fun theSearchWordsCannotChangeTheKindOfLink() {
        val alt = WebFallbackPlanner.alternativeFor(
            step(IntentType.WEB_SEARCH, IntentEntity.QUERY to "x&url=javascript:alert(1)")
        )!!
        assertTrue(alt.url!!.startsWith("https://www.google.com/search?q="))
        assertTrue(!alt.url!!.contains("&url="))
    }

    @Test
    fun emptySearchOrOtherKindsOfStepsHaveNoAlternative() {
        assertNull(WebFallbackPlanner.alternativeFor(step(IntentType.WEB_SEARCH)))
        assertNull(WebFallbackPlanner.alternativeFor(step(IntentType.MAKE_CALL)))
        assertNull(WebFallbackPlanner.alternativeFor(step(IntentType.SYSTEM_ACTION)))
    }

    @Test
    fun anAlternativeHasNoAlternative() {
        val alt = WebFallbackPlanner.alternativeFor(step(IntentType.OPEN_APP, IntentEntity.APP to "Facebook"))!!
        assertNull(WebFallbackPlanner.alternativeFor(alt))
    }

    @Test
    fun noFallbackGivesNothing() {
        assertNull(NoFallback.alternativeFor(step(IntentType.OPEN_APP, IntentEntity.APP to "Facebook")))
    }
}
