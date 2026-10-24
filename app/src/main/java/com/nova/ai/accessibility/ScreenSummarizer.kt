package com.nova.ai.accessibility

/**
 * What is on the screen, sorted into three groups in reading order
 * (top to bottom, left to right). [unnamedFields] counts input fields without a label.
 */
data class ScreenSummary(
    val texts: List<String>,
    val actions: List<String>,
    val fields: List<String>,
    val unnamedFields: Int
) {
    /** True when nothing readable was found. */
    val isEmpty: Boolean
        get() = texts.isEmpty() && actions.isEmpty() && fields.isEmpty() && unnamedFields == 0
}

/** Text prepared for speaking. [truncated] is true if the end was cut off. */
data class SpeechText(val text: String, val truncated: Boolean)

/** Pure logic (no Android classes), so it is easy to test. */
object ScreenSummarizer {

    /** Speech engines refuse very long text; this keeps a safe margin. */
    const val MAX_SPEECH_CHARS: Int = 1400

    // Items whose tops are closer than this count as one visual row.
    private const val ROW_BUCKET_PX: Int = 40
    // A clickable item with a longer name is really a piece of text (a message row, a link line).
    private const val LONG_NAME_CHARS: Int = 30
    private const val SEPARATOR: String = ". "

    /** Sorts the items of [capture] into texts, buttons and input fields. */
    fun summarize(capture: ScreenCapture): ScreenSummary {
        val ordered: List<UiNode> = capture.nodes.sortedWith(
            compareBy<UiNode>({ it.bounds.top / ROW_BUCKET_PX }, { it.bounds.left })
        )

        val texts: MutableList<String> = ArrayList()
        val actions: MutableList<String> = ArrayList()
        val fields: MutableList<String> = ArrayList()
        var unnamedFields = 0

        for (node in ordered) {
            val name: String = readableName(node)
            when {
                node.isEditable ->
                    if (name.isNotBlank()) fields.add(name) else unnamedFields++
                node.isClickable && node.isEnabled && name.isNotBlank() && name.length <= LONG_NAME_CHARS ->
                    actions.add(name)
                name.isNotBlank() -> texts.add(name)
            }
        }

        return ScreenSummary(
            texts = texts.distinct(),
            actions = actions.distinct(),
            fields = fields.distinct(),
            unnamedFields = unnamedFields
        )
    }

    /** Joins [parts] into one speakable text of at most [maxChars] characters. */
    fun toSpeech(parts: List<String>, maxChars: Int = MAX_SPEECH_CHARS): SpeechText {
        val builder = StringBuilder()
        var truncated = false

        for (part in parts) {
            if (builder.isEmpty()) {
                if (part.length > maxChars) {
                    builder.append(part.take(maxChars))
                    truncated = true
                    break
                }
                builder.append(part)
            } else {
                if (builder.length + SEPARATOR.length + part.length > maxChars) {
                    truncated = true
                    break
                }
                builder.append(SEPARATOR).append(part)
            }
        }
        return SpeechText(builder.toString(), truncated)
    }

    // The visible name of an item: text, else description, else hint (never the short id).
    private fun readableName(node: UiNode): String =
        listOf(node.text, node.description, node.hint).firstOrNull { it.isNotBlank() }.orEmpty()
}
