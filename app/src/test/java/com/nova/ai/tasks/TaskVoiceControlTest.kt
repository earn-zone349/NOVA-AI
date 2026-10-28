package com.nova.ai.tasks

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Tests that only whole short control phrases are taken for task controls. */
class TaskVoiceControlTest {

    @Test
    fun banglaAndEnglishWordsAreUnderstood() {
        assertEquals(TaskControlCommand.PAUSE, TaskVoiceControl.parse("থামো"))
        assertEquals(TaskControlCommand.PAUSE, TaskVoiceControl.parse("Pause"))
        assertEquals(TaskControlCommand.RESUME, TaskVoiceControl.parse("চালিয়ে যাও"))
        assertEquals(TaskControlCommand.RESUME, TaskVoiceControl.parse("resume"))
        assertEquals(TaskControlCommand.CANCEL_CURRENT, TaskVoiceControl.parse("বাতিল করো"))
        assertEquals(TaskControlCommand.CANCEL_ALL, TaskVoiceControl.parse("সব বাতিল করো"))
        assertEquals(TaskControlCommand.RERUN, TaskVoiceControl.parse("আবার চালাও"))
        assertEquals(TaskControlCommand.RERUN, TaskVoiceControl.parse("try again"))
        assertEquals(TaskControlCommand.STATUS, TaskVoiceControl.parse("কতদূর হলো"))
    }

    @Test
    fun marksCaseAndFillerWordsAreIgnored() {
        assertEquals(TaskControlCommand.PAUSE, TaskVoiceControl.parse("  নোভা, থামো!  "))
        assertEquals(TaskControlCommand.PAUSE, TaskVoiceControl.parse("Hey Nova, PAUSE."))
        assertEquals(TaskControlCommand.PAUSE, TaskVoiceControl.parse("থামো।"))
        assertEquals(TaskControlCommand.STATUS, TaskVoiceControl.parse("What's the progress?"))
        assertEquals(TaskControlCommand.PAUSE, TaskVoiceControl.parse("please pause"))
    }

    @Test
    fun longerCommandsAreNotControls() {
        assertNull(TaskVoiceControl.parse("গান থামাও"))
        assertNull(TaskVoiceControl.parse("অ্যালার্ম বাতিল করো"))
        assertNull(TaskVoiceControl.parse("ক্রোম খোলো তারপর থামো"))
        assertNull(TaskVoiceControl.parse("cancel my alarm"))
        assertNull(TaskVoiceControl.parse("resume the music"))
    }

    @Test
    fun emptyTextIsNotAControl() {
        assertNull(TaskVoiceControl.parse(""))
        assertNull(TaskVoiceControl.parse("   "))
        assertNull(TaskVoiceControl.parse("..."))
    }
}
