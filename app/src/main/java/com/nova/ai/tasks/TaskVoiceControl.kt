package com.nova.ai.tasks

import java.util.Locale

/** What the user wants to do with the running task. */
enum class TaskControlCommand { PAUSE, RESUME, CANCEL_CURRENT, CANCEL_ALL, RERUN, STATUS }

/**
 * Understands the short control words said while a task runs ("থামো", "চালিয়ে যাও", "বাতিল",
 * "আবার চালাও", "কতদূর হলো"). Only a whole short phrase counts, so a longer command such as
 * "গান থামাও" or "অ্যালার্ম বাতিল করো" is never taken for a task control. Whether the word applies
 * (a task must be running, paused and so on) is decided by the caller. Pure logic.
 */
object TaskVoiceControl {

    private const val MARKS: String = ",.;:!?।\"“”‘-_"

    // Words at the start that do not change the meaning.
    private val FILLERS: Set<String> = setOf("ভাই", "নোভা", "nova", "hey", "দয়া", "করে", "please", "pls", "একটু", "just")

    private val PHRASES: Map<TaskControlCommand, Set<String>> = mapOf(
        TaskControlCommand.PAUSE to setOf(
            "থামো", "থামুন", "থামাও", "থামিয়ে দাও", "পজ", "পজ করো", "পজ দাও", "অপেক্ষা করো", "দাঁড়াও",
            "কাজ থামাও", "কাজ থামো", "কাজ পজ করো", "টাস্ক থামাও",
            "pause", "pause task", "wait", "hold on", "hold", "stop for now"
        ),
        TaskControlCommand.RESUME to setOf(
            "চালিয়ে যাও", "চালিয়ে যান", "এগিয়ে যাও", "এগোও", "আবার চালু করো", "কাজ চালু করো",
            "কাজ চালিয়ে যাও", "রিজিউম", "কন্টিনিউ",
            "resume", "resume task", "continue", "go on", "carry on", "proceed"
        ),
        TaskControlCommand.CANCEL_CURRENT to setOf(
            "বাতিল", "বাতিল করো", "কাজ বাতিল", "কাজ বাতিল করো", "টাস্ক বাতিল করো", "বাদ দাও", "কাজ বাদ দাও",
            "cancel", "cancel task", "cancel it", "forget it", "abort"
        ),
        TaskControlCommand.CANCEL_ALL to setOf(
            "সব বাতিল", "সব বাতিল করো", "সব কাজ বাতিল", "সব কাজ বাতিল করো", "সব কাজ বন্ধ করো",
            "cancel all", "cancel everything", "cancel all tasks"
        ),
        TaskControlCommand.RERUN to setOf(
            "আবার চালাও", "আবার চেষ্টা করো", "আবার করো", "ব্যর্থ কাজ আবার চালাও", "ব্যর্থ কাজ আবার করো",
            "কাজটা আবার চালাও", "কাজটা আবার করো",
            "retry", "try again", "rerun", "run again", "retry task", "retry the task", "do it again"
        ),
        TaskControlCommand.STATUS to setOf(
            "কাজের অবস্থা", "কাজের অবস্থা কী", "কাজের অবস্থা কি", "কতদূর হলো", "কতদূর", "কতটুকু হলো",
            "কাজ কতদূর", "কাজ কতদূর হলো", "স্ট্যাটাস",
            "task status", "status", "progress", "how far", "how is it going", "whats the progress",
            "what is the progress", "show progress"
        )
    )

    /** The control command in [text], or null if the text is something else. */
    fun parse(text: String): TaskControlCommand? {
        val phrase: String = normalize(text)
        if (phrase.isEmpty()) return null
        return PHRASES.entries.firstOrNull { phrase in it.value }?.key
    }

    private fun normalize(text: String): String {
        var words: List<String> = text.lowercase(Locale.ROOT)
            .filter { it != '\'' && it != '’' }
            .map { if (it in MARKS) ' ' else it }
            .joinToString("")
            .split(Regex("\\s+"))
            .filter { it.isNotEmpty() }
        while (words.size > 1 && words.first() in FILLERS) words = words.drop(1)
        return words.joinToString(" ")
    }
}
