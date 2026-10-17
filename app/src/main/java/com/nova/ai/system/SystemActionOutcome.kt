package com.nova.ai.system

/** How a system action ended. */
enum class OutcomeKind {
    /** The app did the job itself. */
    DONE,

    /** The app opened the right screen; the user must finish with one tap. */
    GUIDED,

    /** A special permission is missing; the user can open its screen. */
    NEEDS_PERMISSION,

    /** The command was understood but needs more detail. */
    HINT,

    /** Something went wrong. */
    FAILED
}

/** Result of a system action, with a Bangla message to show the user. */
data class SystemActionOutcome(val kind: OutcomeKind, val message: String)
