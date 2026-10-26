package com.nova.ai.core

/**
 * What a step is expected to cause on the screen. The task planner sets this for each step, so
 * the verification engine checks the right thing: a copy or a button that only plays a sound
 * changes nothing visible, while opening a page must show that page.
 */
enum class ExpectedOutcome {
    /** Something on the screen changes. This is the default. */
    SCREEN_CHANGES,

    /** Nothing visible needs to change (for example a copy, or a button that only plays a sound). */
    NO_CHANGE_EXPECTED,

    /** The text in [TaskStep.expectedValue] shows up on the screen, outside of input fields. */
    TEXT_VISIBLE,

    /** The app with the package name in [TaskStep.expectedValue] is in front. */
    APP_IN_FRONT
}
