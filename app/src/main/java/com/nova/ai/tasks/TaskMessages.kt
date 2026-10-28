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

    /** The command has more steps than NOVA runs in one task. */
    fun tooManySteps(max: Int): String = "একবারে সর্বোচ্চ ${max}টি ধাপ করা যায়। কাজ ছোট করে বলুন।"

    /** One part of the command was not understood. Nothing was started. */
    fun unknownPart(part: String): String = "“$part” অংশটা বুঝতে পারিনি। কিছুই শুরু করিনি।"

    /** All steps finished. */
    fun allDone(count: Int): String = "সব ${count}টি ধাপ শেষ।"

    /** A step failed, so the task stopped there. */
    fun stoppedAt(position: Int, total: Int, reason: String): String =
        "${position}/${total} ধাপে আটকে গেছি: $reason"
}
