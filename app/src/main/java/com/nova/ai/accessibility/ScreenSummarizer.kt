package com.nova.ai.accessibility

/**
 * A short, readable summary of a screen: the texts, the things that can be clicked,
 * and the input fields, each in top-to-bottom, left-to-right order.
 * A blank entry in [fields] means a field without a name.
 */
data class ScreenSummary(
    val texts: List<String>,
    val actions: List<String>,
    val fields: List<String>
)

/** Builds a [ScreenSummary] from a [ScreenCapture]. Pure logic. */
object ScreenSummarizer {

    fun summarize(capture: ScreenCapture): ScreenSummary {
        val ordered: List<UiNode> = capture.nodes.sortedWith(
            compareBy<UiNode>({ it.bounds.top }, { it.bounds.left })
        )

        val texts: List<String> = ordered
            .filter { !it.isEditable }
            .map { it.text.ifBlank { it.description } }
            .filter { it.isNotBlank() }
            .distinct()

        val actions: List<String> = ordered
            .filter { it.isClickable && it.isEnabled }
            .map { it.label() }
            .filter { it.isNotBlank() }
            .distinct()

        val fields: List<String> = ordered
            .filter { it.isEditable }
            .map { it.label() }

        return ScreenSummary(texts = texts, actions = actions, fields = fields)
    }
}
