package com.nova.ai.nlp

import com.nova.ai.core.Language

/** A command after cleanup, ready for the intent parser (Phase 11). */
data class NormalizedCommand(
    /** Exactly what the user said or typed. */
    val original: String,
    /** Cleaned text: no filler words, ASCII digits, app names in one standard form. */
    val normalizedText: String,
    /** [normalizedText] split into words. */
    val tokens: List<String>,
    /** Standard names of the apps mentioned (for example "Chrome"), in order. */
    val detectedApps: List<String>,
    val language: Language
)
