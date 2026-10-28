package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.nlp.IntentEntity
import java.net.URLEncoder

/** Finds another way to do a step that failed. */
interface FallbackPlanner {
    /** An alternative for [step], or null if there is none. */
    fun alternativeFor(step: PlannedStep): PlannedStep?
}

/** No alternatives. */
object NoFallback : FallbackPlanner {
    override fun alternativeFor(step: PlannedStep): PlannedStep? = null
}

/**
 * Alternatives that use the web: an app that is not on the phone is opened as its website, and a
 * search that could not be done in an app is done in the browser. Only fixed https addresses are
 * used (plus a search address with the encoded query), so a spoken word can never become another kind of link.
 */
object WebFallbackPlanner : FallbackPlanner {

    private const val NOTE_SITE: String = "অ্যাপ খোলা যায়নি, তাই ওয়েবসাইটে খুলেছি।"
    private const val NOTE_SEARCH: String = "অ্যাপে সার্চ হয়নি, তাই ব্রাউজারে সার্চ করেছি।"

    // The standard app names of the brain (see AppAliases) and their websites.
    private val SITES: Map<String, String> = mapOf(
        "chrome" to "https://www.google.com",
        "google" to "https://www.google.com",
        "whatsapp" to "https://web.whatsapp.com",
        "facebook" to "https://www.facebook.com",
        "messenger" to "https://www.messenger.com",
        "tiktok" to "https://www.tiktok.com",
        "youtube" to "https://www.youtube.com",
        "gmail" to "https://mail.google.com",
        "instagram" to "https://www.instagram.com",
        "telegram" to "https://web.telegram.org",
        "maps" to "https://maps.google.com",
        "x" to "https://x.com",
        "netflix" to "https://www.netflix.com",
        "spotify" to "https://open.spotify.com",
        "play store" to "https://play.google.com/store",
        "snapchat" to "https://www.snapchat.com"
    )

    override fun alternativeFor(step: PlannedStep): PlannedStep? {
        if (step.isAlternative) return null
        return when (step.intentType) {
            IntentType.OPEN_APP -> siteFor(step)
            IntentType.WEB_SEARCH -> searchFor(step)
            else -> null
        }
    }

    private fun siteFor(step: PlannedStep): PlannedStep? {
        val app: String = step.entities[IntentEntity.APP]?.trim().orEmpty()
        val url: String = SITES[app.lowercase()] ?: return null
        return alternative(step, url, NOTE_SITE)
    }

    private fun searchFor(step: PlannedStep): PlannedStep? {
        val query: String = step.entities[IntentEntity.QUERY]?.trim().orEmpty()
        if (query.isEmpty()) return null
        val encoded: String = URLEncoder.encode(query, "UTF-8")
        val app: String = step.entities[IntentEntity.APP]?.trim()?.lowercase().orEmpty()
        val url: String = if (app == "youtube") {
            "https://www.youtube.com/results?search_query=$encoded"
        } else {
            "https://www.google.com/search?q=$encoded"
        }
        return alternative(step, url, NOTE_SEARCH)
    }

    private fun alternative(step: PlannedStep, url: String, note: String): PlannedStep = PlannedStep(
        id = step.id + "-alt",
        title = step.title,
        command = step.command,
        intentType = step.intentType,
        entities = step.entities,
        kind = StepKind.OPEN_URL,
        url = url,
        note = note,
        isAlternative = true
    )
}
