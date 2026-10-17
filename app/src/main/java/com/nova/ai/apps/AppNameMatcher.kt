package com.nova.ai.apps

/**
 * Matches the app name the user said against the apps in the library.
 * Order of trust: exact name, same sound, name inside name, similar sound.
 * Pure logic, no Android needed.
 */
object AppNameMatcher {

    const val MIN_SCORE: Float = 0.72f
    const val STRONG_SCORE: Float = 0.9f
    const val CLEAR_GAP: Float = 0.08f

    private const val MAX_AMBIGUOUS: Int = 3
    private const val SCORE_EXACT: Float = 1.0f
    private const val SCORE_SAME_SOUND: Float = 0.95f
    private const val SCORE_CONTAINS: Float = 0.92f
    private const val MIN_CONTAINS_LENGTH: Int = 3
    private const val MIN_CONTAINS_RATIO: Float = 0.5f
    private const val MIN_SKELETON_LENGTH: Int = 2
    private const val SOUND_WEIGHT: Float = 0.35f
    private const val SKELETON_WEIGHT: Float = 0.65f

    /** Standard names from the command parser, mapped to the names phones really use. */
    private val STANDARD_SYNONYMS: Map<String, List<String>> = mapOf(
        "dialer" to listOf("Phone", "Dialer", "ফোন"),
        "gallery" to listOf("Photos", "Gallery"),
        "files" to listOf("My Files", "Files by Google", "File Manager", "Files"),
        "x" to listOf("Twitter", "X"),
        "contacts" to listOf("Contacts", "People"),
        "google" to listOf("Google", "Google app"),
        "clock" to listOf("Clock", "Alarm", "ঘড়ি"),
        "calendar" to listOf("Calendar", "Google Calendar"),
        "maps" to listOf("Maps", "Google Maps")
    )

    /** Matches [spoken] against [apps] and decides what to do. */
    fun match(spoken: String, apps: List<RegisteredApp>): MatchOutcome =
        decide(rank(spoken, apps))

    /** All apps that fit [spoken] well enough, best first. */
    fun rank(spoken: String, apps: List<RegisteredApp>): List<AppMatch> {
        val variants: List<String> = spokenVariants(spoken)
        if (variants.isEmpty()) return emptyList()

        val matches = ArrayList<AppMatch>()
        for (app in apps) {
            var bestScore = 0f
            var bestName: String = app.label
            for (name in app.allNames()) {
                for (variant in variants) {
                    val score: Float = scoreNames(variant, name)
                    if (score > bestScore) {
                        bestScore = score
                        bestName = name
                    }
                }
            }
            if (bestScore >= MIN_SCORE) matches.add(AppMatch(app, bestScore, bestName))
        }
        return matches.sortedByDescending { it.score }
    }

    /** Turns a ranked list into one decision. */
    fun decide(ranked: List<AppMatch>): MatchOutcome {
        val top: AppMatch = ranked.firstOrNull() ?: return MatchOutcome.None
        val close: List<AppMatch> = ranked.filter { top.score - it.score < CLEAR_GAP }
        return when {
            close.size >= 2 -> MatchOutcome.Ambiguous(close.take(MAX_AMBIGUOUS).map { it.app })
            top.score >= STRONG_SCORE -> MatchOutcome.Single(top.app)
            else -> MatchOutcome.Confirm(top.app)
        }
    }

    private fun spokenVariants(spoken: String): List<String> {
        val trimmed: String = spoken.trim()
        val key: String = PhoneticKey.nameKey(trimmed)
        if (key.isEmpty()) return emptyList()
        return listOf(trimmed) + STANDARD_SYNONYMS[key].orEmpty()
    }

    private fun scoreNames(spoken: String, name: String): Float {
        val spokenKey: String = PhoneticKey.nameKey(spoken)
        val nameKey: String = PhoneticKey.nameKey(name)
        if (spokenKey.isEmpty() || nameKey.isEmpty()) return 0f
        if (spokenKey == nameKey) return SCORE_EXACT

        val spokenSound: String = PhoneticKey.phonetic(spoken)
        val nameSound: String = PhoneticKey.phonetic(name)
        if (spokenSound.isNotEmpty() && spokenSound == nameSound) return SCORE_SAME_SOUND

        val contains: Float = containsScore(spokenSound, nameSound)

        val spokenSkeleton: String = PhoneticKey.skeleton(spoken)
        val nameSkeleton: String = PhoneticKey.skeleton(name)
        val soundSimilarity: Float = PhoneticKey.similarity(spokenSound, nameSound)
        val similarity: Float =
            if (spokenSkeleton.length >= MIN_SKELETON_LENGTH && nameSkeleton.length >= MIN_SKELETON_LENGTH) {
                SOUND_WEIGHT * soundSimilarity +
                    SKELETON_WEIGHT * PhoneticKey.similarity(spokenSkeleton, nameSkeleton)
            } else {
                soundSimilarity
            }
        return maxOf(contains, similarity)
    }

    /** High score when one sound key sits inside the other and is a big enough part of it. */
    private fun containsScore(first: String, second: String): Float {
        val shorter: String = if (first.length <= second.length) first else second
        val longer: String = if (first.length <= second.length) second else first
        if (shorter.length < MIN_CONTAINS_LENGTH) return 0f
        if (!longer.contains(shorter)) return 0f
        val ratio: Float = shorter.length.toFloat() / longer.length.toFloat()
        return if (ratio >= MIN_CONTAINS_RATIO) SCORE_CONTAINS else 0f
    }
}
