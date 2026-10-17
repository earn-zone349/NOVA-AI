package com.nova.ai.nlp

import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent

/**
 * Understands camera commands ("ছবি তোলো", "ভিডিও রেকর্ড করো", "ক্যামেরা খোলো")
 * and navigation commands ("মিরপুর যাওয়ার রাস্তা দেখাও").
 * Pure logic, no Android needed.
 */
internal object ExtraCommandParser {

    private const val CONF_HIGH: Float = 0.9f
    private const val CONF_LOW: Float = 0.5f

    private val PHOTO_WORDS: Set<String> = setOf(
        "ছবি", "ছবিটা", "ফটো", "photo", "picture", "pic", "selfie", "সেলফি"
    )
    private val PHOTO_VERBS: Set<String> = setOf(
        "তোলো", "তুলো", "তোল", "তুলুন", "তুলে", "take", "click", "snap", "capture"
    )
    private val VIDEO_WORDS: Set<String> = setOf("ভিডিও", "ভিডিওটা", "video")
    private val VIDEO_VERBS: Set<String> = setOf(
        "রেকর্ড", "রেকর্ডিং", "record", "recording", "শুট", "শ্যুট", "shoot"
    )
    private val CAMERA_WORDS: Set<String> = setOf("camera", "ক্যামেরা")

    private val NAVIGATION_WORDS: Set<String> = setOf(
        "navigate", "navigation", "নেভিগেট", "নেভিগেশন", "directions", "direction",
        "route", "রুট", "রাস্তা", "রাস্তাটা", "দিকনির্দেশ", "দিকনির্দেশনা", "ডিরেকশন"
    )
    private val DESTINATION_NOISE: Set<String> = setOf(
        "যাওয়ার", "যেতে", "যাব", "যাবো", "যাই", "যাচ্ছি", "যাও",
        "go", "going", "to", "from", "থেকে", "show", "me", "get",
        "পথ", "পথটা", "গন্তব্য"
    )

    /** Returns the understood command, or null if this is not a camera or navigation command. */
    fun parse(v: CommandView): NovaIntent? = parseCapture(v) ?: parseNavigation(v)

    private fun parseCapture(v: CommandView): NovaIntent? {
        val mode: String = when {
            v.hasAny(VIDEO_WORDS) && v.hasAny(VIDEO_VERBS) -> IntentMode.VIDEO
            v.hasAny(PHOTO_WORDS) && v.hasAny(PHOTO_VERBS) -> IntentMode.PHOTO
            v.hasAny(CAMERA_WORDS) && v.hasAny(IntentVocabulary.OPEN_VERBS_STRONG) -> IntentMode.PHOTO
            else -> return null
        }
        return NovaIntent(
            IntentType.CAPTURE_MEDIA,
            mapOf(IntentEntity.MODE to mode),
            CONF_HIGH
        )
    }

    private fun parseNavigation(v: CommandView): NovaIntent? {
        if (!v.hasAny(NAVIGATION_WORDS)) return null

        val destination: String = v.remaining(
            NAVIGATION_WORDS,
            DESTINATION_NOISE,
            IntentVocabulary.HELPER_WORDS,
            IntentVocabulary.COMMON_STRIP,
            IntentVocabulary.OPEN_VERBS_STRONG
        ).joinToString(" ")

        val entities = LinkedHashMap<String, String>()
        if (destination.isNotEmpty()) entities[IntentEntity.QUERY] = destination
        return NovaIntent(
            IntentType.NAVIGATE,
            entities,
            if (destination.isNotEmpty()) CONF_HIGH else CONF_LOW
        )
    }
}
