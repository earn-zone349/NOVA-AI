package com.nova.ai.accessibility

import com.nova.ai.core.ScreenBounds

/**
 * One item on the screen (a text, button, input field...) as read by the accessibility service.
 * [path] lists the child positions from the top of the screen tree down to this item,
 * so the same item can be found again later (used for clicking in the next phase).
 * Input fields never carry typed text: [text] is always empty for them.
 * Sensitive fields also have an empty [description].
 */
data class UiNode(
    val id: Int,
    val depth: Int,
    val path: List<Int>,
    val text: String,
    val description: String,
    val hint: String,
    val viewId: String,
    val className: String,
    val bounds: ScreenBounds,
    val isClickable: Boolean,
    val isLongClickable: Boolean,
    val isEditable: Boolean,
    val isScrollable: Boolean,
    val isCheckable: Boolean,
    val isChecked: Boolean,
    val isEnabled: Boolean,
    val isFocused: Boolean,
    val isSensitive: Boolean
) {
    /** The best name for this item: its text, else its description, hint, or short id. */
    fun label(): String =
        listOf(text, description, hint).firstOrNull { it.isNotBlank() }
            ?: viewId.substringAfterLast('/')
}

/** Everything visible on the screen at one moment. */
data class ScreenCapture(
    val packageName: String?,
    val nodes: List<UiNode>,
    val visitedCount: Int,
    val truncated: Boolean,
    val hiddenSensitiveCount: Int,
    val capturedAtMs: Long,
    val durationMs: Long
)
