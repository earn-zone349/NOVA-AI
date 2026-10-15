package com.nova.ai.accessibility

import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.ScrollDirection

/** Reads and controls the screen through the Android Accessibility Service. */
interface AccessibilityEngine {
    /** True if the user has enabled the accessibility service. */
    fun isServiceEnabled(): Boolean

    /** Captures the visible UI elements. */
    fun captureScreen(): NovaResult<ScreenSnapshot>

    /** Taps the given [node]. */
    fun click(node: ScreenNode): NovaResult<Unit>

    /** Types [text] into the given editable [node]. */
    fun typeText(node: ScreenNode, text: String): NovaResult<Unit>

    /** Scrolls the screen in [direction]. */
    fun scroll(direction: ScrollDirection): NovaResult<Unit>

    /** Presses the system Back button. */
    fun pressBack(): NovaResult<Unit>

    /** Goes to the Home screen. */
    fun pressHome(): NovaResult<Unit>
}
