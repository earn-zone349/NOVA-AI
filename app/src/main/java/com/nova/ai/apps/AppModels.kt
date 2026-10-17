package com.nova.ai.apps

/** An app found on the phone that can be launched. */
data class InstalledApp(val packageName: String, val label: String)

/** An app the user allowed NOVA to control, with the nicknames the user gave it. */
data class RegisteredApp(
    val packageName: String,
    val label: String,
    val aliases: List<String> = emptyList()
) {
    /** The app's real name followed by every nickname. */
    fun allNames(): List<String> = listOf(label) + aliases
}

/** One candidate app with how well its name matched what the user said. */
data class AppMatch(val app: RegisteredApp, val score: Float, val matchedName: String)

/** The decision after matching a spoken name against the app library. */
sealed class MatchOutcome {
    /** One clear winner: open it directly. */
    data class Single(val app: RegisteredApp) : MatchOutcome()

    /** One likely app, but not sure enough: ask the user first. */
    data class Confirm(val app: RegisteredApp) : MatchOutcome()

    /** Several apps fit equally: let the user choose. */
    data class Ambiguous(val apps: List<RegisteredApp>) : MatchOutcome()

    /** Nothing in the library fits. */
    object None : MatchOutcome()
}
