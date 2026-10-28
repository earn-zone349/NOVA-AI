package com.nova.ai.tasks

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests how a command is cut into parts. Plain JVM test, no phone needed. */
class CommandSplitterTest {

    @Test
    fun banglaConnectorSplitsIntoParts() {
        assertEquals(
            listOf("ক্রোম খোলো", "ভলিউম বাড়াও", "টর্চ জ্বালাও"),
            CommandSplitter.split("ক্রোম খোলো তারপর ভলিউম বাড়াও তারপর টর্চ জ্বালাও")
        )
    }

    @Test
    fun otherBanglaConnectorsWork() {
        assertEquals(listOf("ক্রোম খোলো", "গান চালাও"), CommandSplitter.split("ক্রোম খোলো এরপর গান চালাও"))
        assertEquals(listOf("ক্রোম খোলো", "গান চালাও"), CommandSplitter.split("ক্রোম খোলো তারপরে গান চালাও"))
        assertEquals(listOf("ক্রোম খোলো", "গান চালাও"), CommandSplitter.split("ক্রোম খোলো তার পর গান চালাও"))
        assertEquals(listOf("ক্রোম খোলো", "গান চালাও"), CommandSplitter.split("ক্রোম খোলো এর পর গান চালাও"))
    }

    @Test
    fun englishConnectorsWorkInAnyCase() {
        assertEquals(listOf("open chrome", "turn on wifi"), CommandSplitter.split("open chrome then turn on wifi"))
        assertEquals(listOf("open chrome", "turn on wifi"), CommandSplitter.split("open chrome and then turn on wifi"))
        assertEquals(listOf("Open Chrome", "turn on wifi"), CommandSplitter.split("Open Chrome After That turn on wifi"))
        assertEquals(listOf("open chrome", "turn on wifi"), CommandSplitter.split("open chrome THEN turn on wifi"))
    }

    @Test
    fun commasAndHangingWordsAreRemoved() {
        assertEquals(
            listOf("ক্রোম খোলো", "ভলিউম বাড়াও"),
            CommandSplitter.split("ক্রোম খোলো, এবং তারপর, ভলিউম বাড়াও।")
        )
        assertEquals(listOf("open chrome", "play music"), CommandSplitter.split("open chrome, and then, play music."))
    }

    @Test
    fun aSingleCommandIsNeverCut() {
        assertEquals(listOf("ক্রোম খোলো"), CommandSplitter.split("ক্রোম খোলো"))
        assertEquals(listOf("রহিমকে ফোন করো"), CommandSplitter.split("রহিমকে ফোন করো"))
        assertFalse(CommandSplitter.isMultiStep("ক্রোম খুলে ভিডিও সার্চ করো"))
    }

    @Test
    fun connectorsAtTheEdgesAndEmptyPartsAreIgnored() {
        assertEquals(listOf("ক্রোম খোলো"), CommandSplitter.split("তারপর ক্রোম খোলো তারপর"))
        assertEquals(listOf("ক্রোম খোলো", "গান চালাও"), CommandSplitter.split("ক্রোম খোলো তারপর তারপর গান চালাও"))
        assertTrue(CommandSplitter.split("   ").isEmpty())
        assertTrue(CommandSplitter.split("তারপর").isEmpty())
    }

    @Test
    fun extraSpacesAreHandled() {
        assertEquals(listOf("a b", "c"), CommandSplitter.split("  a   b   then    c  "))
    }

    @Test
    fun multiStepNeedsTwoParts() {
        assertTrue(CommandSplitter.isMultiStep("ক্রোম খোলো তারপর গান চালাও"))
        assertFalse(CommandSplitter.isMultiStep("ক্রোম খোলো তারপর"))
    }
}
