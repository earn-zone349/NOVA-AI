package com.nova.ai.tasks

/** Texts the planner and the queue show to the user (Bangla). Kept in one place. */
object TaskMessages {

    const val MSG_EMPTY: String = "কী করতে হবে বুঝতে পারিনি। কমান্ড খালি।"
    const val MSG_QUEUE_FULL: String = "কাজের লাইন ভর্তি। আগের কাজ শেষ হলে আবার বলুন।"
    const val MSG_STEP_TIMEOUT: String = "ধাপটি সময়মতো শেষ হয়নি।"
    const val MSG_QUESTION_TIMEOUT: String = "উত্তর পাওয়া যায়নি, তাই কাজ বাতিল করেছি।"
    const val MSG_CANCELLED: String = "কাজ বাতিল করা হয়েছে।"
    const val MSG_START_FAILED: String = "ধাপটি চালু করা যায়নি।"
    const val MSG_NOT_FOUND: String = "এই কাজটি এখন চলছে না।"
    const val MSG_NO_QUESTION: String = "এখন কোনো প্রশ্ন নেই।"
    const val MSG_BAD_CHOICE: String = "এই বিকল্পটি নেই।"
    const val MSG_CANNOT_PAUSE: String = "এই কাজ এখন থামানো যাবে না।"
    const val MSG_CANNOT_RESUME: String = "এই কাজ থামানো নেই।"

    const val MSG_PAUSED: String = "কাজ থামানো হয়েছে। চলতি ধাপ শেষ হলে এখানেই থামবে।"
    const val MSG_ALREADY_PAUSED: String = "কাজ আগে থেকেই থামানো আছে।"
    const val MSG_RESUMED: String = "কাজ আবার চলছে।"
    const val MSG_NOTHING_TO_RERUN: String = "আবার চালানোর মতো ব্যর্থ বা বাতিল কাজ নেই।"
    const val MSG_NOTHING_LEFT: String = "এই কাজের সব ধাপ আগেই শেষ হয়েছে।"
    const val MSG_NO_TASK: String = "এখন কোনো কাজ নেই।"
    const val MSG_HISTORY_CLEARED: String = "কাজের ইতিহাস মোছা হয়েছে।"
    const val MSG_HISTORY_NOT_FOUND: String = "এই কাজটি ইতিহাসে পাওয়া যায়নি।"

    /** The rerun of a task has the same title with this word in front. */
    fun rerunTitle(title: String): String = "আবার: $title"

    /** A rerun was put in the queue. */
    fun rerunStarted(count: Int): String = "বাকি ${count}টি ধাপ আবার চালু করছি।"

    /** The answer to "what is the progress?" while a task runs. */
    fun statusRunning(done: Int, total: Int, current: String): String =
        "${done}/${total} ধাপ শেষ। এখন: $current।"

    /** The answer to "what is the progress?" while a task is paused. */
    fun statusPaused(done: Int, total: Int): String = "কাজ থামানো আছে। ${done}/${total} ধাপ শেষ।"

    /** The answer to "what is the progress?" while a task waits for the user. */
    fun statusQuestion(done: Int, total: Int): String = "${done}/${total} ধাপ শেষ। আপনার উত্তরের অপেক্ষায় আছি।"

    const val OPTION_RETRY: String = "আবার চেষ্টা করো"
    const val OPTION_SKIP: String = "এই ধাপ বাদ দিয়ে এগোও"
    const val OPTION_CANCEL: String = "কাজ বাতিল করো"

    /** The next try of a step is about to start. */
    fun retrying(attempt: Int, max: Int, reason: String): String = "$reason (আবার চেষ্টা $attempt/$max)"

    /** The step was done another way. */
    fun alternativeDone(note: String): String = note

    /** Asks what to do after a step failed for good. */
    fun recoveryQuestion(position: Int, total: Int, reason: String): String =
        "${position}/${total} ধাপ হয়নি: $reason। এখন কী করবো?"

    /** The task ended, but some steps were skipped on the user's choice. */
    fun doneWithSkips(done: Int, skipped: Int): String = "${done}টি ধাপ শেষ, ${skipped}টি বাদ দেওয়া হয়েছে।"

    /** The command has more steps than NOVA runs in one task. */
    fun tooManySteps(max: Int): String = "একবারে সর্বোচ্চ ${max}টি ধাপ করা যায়। কাজ ছোট করে বলুন।"

    /** One part of the command was not understood. Nothing was started. */
    fun unknownPart(part: String): String = "“$part” অংশটা বুঝতে পারিনি। কিছুই শুরু করিনি।"

    /** All steps finished. */
    fun allDone(count: Int): String = "সব ${count}টি ধাপ শেষ।"

    /** A step failed, so the task stopped there. */
    fun stoppedAt(position: Int, total: Int, reason: String, attempts: Int = 1, triedAlternative: Boolean = false): String {
        val tries: String = if (attempts > 1) " (${attempts} বার চেষ্টা করেছি)" else ""
        val alt: String = if (triedAlternative) " বিকল্প পথেও হয়নি।" else ""
        return "${position}/${total} ধাপে আটকে গেছি: $reason$tries$alt"
    }
}
