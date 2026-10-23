package com.nova.ai.accessibility

import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot

/**
 * What is on the screen, sorted into three groups in reading order.
 * [unnamedFields] counts input fields that have no label.
 */
data class ScreenReport(
    val packageName: String?,
    val texts: List<String>,
    val buttons: List<String>,
    val fields: List<String>,
    val unnamedFields: Int
) {
    /** True when nothing readable was found. */
    val isEmpty: Boolean
        get() = texts.isEmpty() && buttons.isEmpty() && fields.isEmpty() && unnamedFields == 0
}

/** Text prepared for speaking. [truncated] is true if the end was cut off. */
data class SpeechText(val text: String, val truncated: Boolean)

/** Pure logic (no Android classes), so it is easy to test. */
object ScreenSummarizer {

    /** Speech engines refuse very long text; this keeps a safe margin. */
    const val MAX_SPEECH_CHARS: Int = 1400

    // Nodes whose tops are closer than this are treated as one visual row.
    private const val ROW_BUCKET_PX: Int = 40
    private const val SEPARATOR: String = ". "

    /** Sorts the nodes of [snapshot] into texts, buttons and input fields. */
    fun summarize(snapshot: ScreenSnapshot): ScreenReport {
        val ordered: List<ScreenNode> = snapshot.nodes.sortedWith(
            compareBy<ScreenNode>({ it.bounds.top / ROW_BUCKET_PX }, { it.bounds.left })
        )

        val texts: MutableList<String> = ArrayList()
        val buttons: MutableList<String> = ArrayList()
        val fields: MutableList<String> = ArrayList()
        var unnamedFields = 0

        for (node in ordered) {
            val label: String? = node.text ?: node.contentDescription
            if (node.isEditable) {
                if (label != null) fields.add(label) else unnamedFields++
            } else if (node.isClickable) {
                if (label != null) buttons.add(label)
            } else if (label != null) {
                texts.add(label)
            }
        }

        return ScreenReport(
            packageName = snapshot.packageName,
            texts = texts.distinct(),
            buttons = buttons.distinct(),
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
}
