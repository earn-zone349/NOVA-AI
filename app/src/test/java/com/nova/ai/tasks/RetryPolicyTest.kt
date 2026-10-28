package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.nlp.IntentAction
import com.nova.ai.nlp.IntentEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests when a failed step may be tried again. Plain JVM test. */
class RetryPolicyTest {

    private val policy = RetryPolicy(maxAttempts = 3, backoffMs = listOf(1000L, 2500L))

    private fun step(type: IntentType, action: String? = null) = PlannedStep(
        id = "s1", title = "t", command = "c", intentType = type,
        entities = if (action == null) emptyMap() else mapOf(IntentEntity.ACTION to action)
    )

    @Test
    fun anErrorTheAppReportedIsRepeatedForAnyKindOfStep() {
        for (type in listOf(IntentType.OPEN_APP, IntentType.MAKE_CALL, IntentType.SET_ALARM, IntentType.SYSTEM_ACTION)) {
            assertTrue(policy.allowsRetry(step(type), FailureKind.RETRYABLE, attempt = 1))
        }
    }

    @Test
    fun aPermanentFailureIsNeverRepeated() {
        assertFalse(policy.allowsRetry(step(IntentType.OPEN_APP), FailureKind.PERMANENT, 1))
    }

    @Test
    fun silenceIsRepeatedOnlyWhenDoingItTwiceIsHarmless() {
        assertTrue(policy.allowsRetry(step(IntentType.OPEN_APP), FailureKind.UNCERTAIN, 1))
        assertTrue(policy.allowsRetry(step(IntentType.WEB_SEARCH), FailureKind.UNCERTAIN, 1))
        assertTrue(policy.allowsRetry(step(IntentType.SYSTEM_ACTION, IntentAction.ON), FailureKind.UNCERTAIN, 1))
        assertFalse(policy.allowsRetry(step(IntentType.SYSTEM_ACTION, IntentAction.UP), FailureKind.UNCERTAIN, 1))
        assertFalse(policy.allowsRetry(step(IntentType.MAKE_CALL), FailureKind.UNCERTAIN, 1))
        assertFalse(policy.allowsRetry(step(IntentType.SET_ALARM), FailureKind.UNCERTAIN, 1))
        assertFalse(policy.allowsRetry(step(IntentType.SEND_MESSAGE), FailureKind.UNCERTAIN, 1))
        assertFalse(policy.allowsRetry(step(IntentType.MEDIA_CONTROL, IntentAction.NEXT), FailureKind.UNCERTAIN, 1))
    }

    @Test
    fun theNumberOfTriesIsLimited() {
        val s = step(IntentType.OPEN_APP)
        assertTrue(policy.allowsRetry(s, FailureKind.RETRYABLE, 2))
        assertFalse(policy.allowsRetry(s, FailureKind.RETRYABLE, 3))
        assertFalse(RetryPolicy.NONE.allowsRetry(s, FailureKind.RETRYABLE, 1))
    }

    @Test
    fun anAlternativeStepIsNeverRepeated() {
        val alt = step(IntentType.OPEN_APP).copy(isAlternative = true)
        assertFalse(policy.allowsRetry(alt, FailureKind.RETRYABLE, 1))
    }

    @Test
    fun theWaitGrowsAndTheLastValueRepeats() {
        assertEquals(1000L, policy.delayBefore(2))
        assertEquals(2500L, policy.delayBefore(3))
        assertEquals(2500L, policy.delayBefore(9))
        assertEquals(0L, RetryPolicy.NONE.delayBefore(2))
    }

    @Test
    fun standardPolicyAsksTheUserAndNonePolicyDoesNot() {
        assertTrue(RetryPolicy.STANDARD.askUserOnFailure)
        assertEquals(3, RetryPolicy.STANDARD.maxAttempts)
        assertFalse(RetryPolicy.NONE.askUserOnFailure)
    }
}
