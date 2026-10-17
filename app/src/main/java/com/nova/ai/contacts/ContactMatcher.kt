package com.nova.ai.contacts

import com.nova.ai.apps.PhoneticKey

/**
 * Finds the contact the user meant. Works across Bangla and English spellings
 * ("সুমন" finds "Sumon"), and a single word matches part of a full name
 * ("সুমন" finds "সুমন আহমেদ"). Pure logic, no Android needed.
 */
object ContactMatcher {

    const val MIN_SCORE: Float = 0.75f
    const val CLEAR_GAP: Float = 0.08f

    private const val MAX_CHOICES: Int = 4
    private const val SCORE_EXACT: Float = 1.0f
    private const val SCORE_SAME_SOUND: Float = 0.95f
    private const val SCORE_CONTAINS: Float = 0.92f
    private const val WORD_FACTOR: Float = 0.97f
    private const val MIN_CONTAINS_LENGTH: Int = 3
    private const val MIN_CONTAINS_RATIO: Float = 0.5f
    private const val MIN_SKELETON_LENGTH: Int = 2
    private const val SOUND_WEIGHT: Float = 0.35f
    private const val SKELETON_WEIGHT: Float = 0.65f

    private val WHITESPACE: Regex = Regex("\\s+")

    /** Matches [spoken] against [contacts] and decides what to do. */
    fun match(spoken: String, contacts: List<Contact>): ContactOutcome =
        decide(rank(spoken, contacts))

    /** All contacts that fit [spoken] well enough, best first. */
    fun rank(spoken: String, contacts: List<Contact>): List<ContactMatch> {
        if (PhoneticKey.nameKey(spoken).isEmpty()) return emptyList()
        return contacts
            .map { ContactMatch(it, scoreName(spoken, it.name)) }
            .filter { it.score >= MIN_SCORE }
            .sortedByDescending { it.score }
    }

    /** Turns a ranked list into one decision. */
    fun decide(ranked: List<ContactMatch>): ContactOutcome {
        val top: ContactMatch = ranked.firstOrNull() ?: return ContactOutcome.None
        val close: List<ContactMatch> = ranked.filter { top.score - it.score < CLEAR_GAP }
        return if (close.size >= 2) {
            ContactOutcome.Ambiguous(close.take(MAX_CHOICES).map { it.contact })
        } else {
            ContactOutcome.Single(top.contact)
        }
    }

    /** Full-name score, or the best single-word score for longer names. */
    private fun scoreName(spoken: String, fullName: String): Float {
        val fullScore: Float = scorePair(spoken, fullName)
        val words: List<String> = fullName.split(WHITESPACE).filter { it.isNotBlank() }
        if (words.size < 2) return fullScore
        val bestWord: Float = words.maxOf { scorePair(spoken, it) } * WORD_FACTOR
        return maxOf(fullScore, bestWord)
    }

    private fun scorePair(spoken: String, name: String): Float {
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

    private fun containsScore(first: String, second: String): Float {
        val shorter: String = if (first.length <= second.length) first else second
        val longer: String = if (first.length <= second.length) second else first
        if (shorter.length < MIN_CONTAINS_LENGTH) return 0f
        if (!longer.contains(shorter)) return 0f
        val ratio: Float = shorter.length.toFloat() / longer.length.toFloat()
        return if (ratio >= MIN_CONTAINS_RATIO) SCORE_CONTAINS else 0f
    }
}
