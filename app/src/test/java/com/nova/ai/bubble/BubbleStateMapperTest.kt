package com.nova.ai.bubble

import com.nova.ai.voice.ConversationState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests which look the bubble takes. Plain JVM test. */
class BubbleStateMapperTest {

    @Test
    fun emergencyStopWinsOverEverything() {
        for (c in ConversationState.values()) {
            assertEquals(BubbleState.STOPPED, BubbleStateMapper.map(true, c, true))
        }
    }

    @Test
    fun speakingThenListeningThenWorking() {
        assertEquals(BubbleState.SPEAKING, BubbleStateMapper.map(false, ConversationState.SPEAKING, true))
        assertEquals(BubbleState.LISTENING, BubbleStateMapper.map(false, ConversationState.LISTENING, true))
        assertEquals(BubbleState.LISTENING, BubbleStateMapper.map(false, ConversationState.WAITING, false))
        assertEquals(BubbleState.THINKING, BubbleStateMapper.map(false, ConversationState.IDLE, true))
        assertEquals(BubbleState.IDLE, BubbleStateMapper.map(false, ConversationState.IDLE, false))
    }

    @Test
    fun stopBadgeShowsOnlyWhileBusy() {
        assertTrue(BubbleStateMapper.showsStopBadge(BubbleState.LISTENING))
        assertTrue(BubbleStateMapper.showsStopBadge(BubbleState.SPEAKING))
        assertTrue(BubbleStateMapper.showsStopBadge(BubbleState.THINKING))
        assertFalse(BubbleStateMapper.showsStopBadge(BubbleState.IDLE))
        assertFalse(BubbleStateMapper.showsStopBadge(BubbleState.STOPPED))
    }
}
