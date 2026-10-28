package com.nova.ai.tasks

import com.nova.ai.core.IntentType
import com.nova.ai.core.TaskStatus

/** One step of a finished task, as kept in the history. */
data class HistoryStep(
    val title: String,
    val command: String,
    val intentType: IntentType,
    val entities: Map<String, String>,
    val state: StepState,
    val message: String?
)

/** A finished task, as kept in the history on the phone. */
data class HistoryItem(
    val id: String,
    val title: String,
    val status: TaskStatus,
    val summary: String?,
    val finishedAtMs: Long,
    val steps: List<HistoryStep>
) {
    /** True if the user can run the unfinished steps again. */
    val canRerun: Boolean get() = status == TaskStatus.FAILED || status == TaskStatus.CANCELLED

    /**
     * A new task made of the steps that did not finish (failed, skipped or cancelled), in order.
     * Null if every step is done or the steps were not kept.
     */
    fun toRerunDraft(newId: String): TaskDraft? {
        val left: List<HistoryStep> = steps.filter { it.state != StepState.DONE }
        if (left.isEmpty()) return null
        return TaskDraft(
            id = newId,
            title = TaskMessages.rerunTitle(title),
            steps = left.mapIndexed { index, step ->
                PlannedStep(
                    id = "s${index + 1}",
                    title = step.title,
                    command = step.command,
                    intentType = step.intentType,
                    entities = step.entities
                )
            }
        )
    }

    companion object {
        /** Builds the history record of a finished task from its plan and its last snapshot. */
        fun from(draft: TaskDraft, snapshot: TaskSnapshot, finishedAtMs: Long): HistoryItem = HistoryItem(
            id = snapshot.id,
            title = snapshot.title,
            status = snapshot.status,
            summary = snapshot.summary,
            finishedAtMs = finishedAtMs,
            steps = draft.steps.mapIndexed { index, step ->
                val shown: StepSnapshot? = snapshot.steps.getOrNull(index)
                HistoryStep(
                    title = step.title,
                    command = step.command,
                    intentType = step.intentType,
                    entities = step.entities,
                    state = shown?.state ?: StepState.CANCELLED,
                    message = shown?.message
                )
            }
        )
    }
}

/**
 * Writes the steps of a task into one piece of text and reads them back, so the history can keep them
 * in the "detail" column of the existing task table (no database change). Control characters are used
 * as separators and are removed from the texts. Pure logic. Reading is forgiving: a damaged record is skipped.
 */
object HistoryCodec {

    private const val VERSION: String = "1"
    private const val RECORD: Char = '\u001E'
    private const val FIELD: Char = '\u001F'
    private const val PAIR: Char = '\u001C'
    private const val KEY_VALUE: Char = '\u001D'
    private val SEPARATORS: Regex = Regex("[\u001C\u001D\u001E\u001F]")

    /** The "detail" text for [item]. */
    fun encode(item: HistoryItem): String {
        val records: MutableList<String> = mutableListOf(VERSION + FIELD + clean(item.summary.orEmpty()))
        for (step in item.steps) {
            val entities: String = step.entities.entries.joinToString(PAIR.toString()) {
                clean(it.key) + KEY_VALUE + clean(it.value)
            }
            records.add(
                listOf(
                    clean(step.title), clean(step.command), step.intentType.name, step.state.name,
                    clean(step.message.orEmpty()), entities
                ).joinToString(FIELD.toString())
            )
        }
        return records.joinToString(RECORD.toString())
    }

    /** The summary and the steps kept in [detail]. An unknown or empty text gives no summary and no steps. */
    fun decode(detail: String?): Pair<String?, List<HistoryStep>> {
        if (detail.isNullOrEmpty()) return null to emptyList()
        val records: List<String> = detail.split(RECORD)
        val header: List<String> = records.first().split(FIELD)
        if (header.firstOrNull() != VERSION) return null to emptyList()
        val summary: String? = header.getOrNull(1)?.ifEmpty { null }
        val steps: List<HistoryStep> = records.drop(1).mapNotNull { readStep(it) }
        return summary to steps
    }

    private fun readStep(record: String): HistoryStep? {
        val parts: List<String> = record.split(FIELD)
        if (parts.size < 6) return null
        val type: IntentType = enumOrNull<IntentType>(parts[2]) ?: return null
        val state: StepState = enumOrNull<StepState>(parts[3]) ?: return null
        val entities: Map<String, String> = if (parts[5].isEmpty()) {
            emptyMap()
        } else {
            parts[5].split(PAIR).mapNotNull { pair ->
                val kv: List<String> = pair.split(KEY_VALUE)
                if (kv.size == 2) kv[0] to kv[1] else null
            }.toMap()
        }
        return HistoryStep(
            title = parts[0],
            command = parts[1],
            intentType = type,
            entities = entities,
            state = state,
            message = parts[4].ifEmpty { null }
        )
    }

    private fun clean(text: String): String = text.replace(SEPARATORS, " ")

    private inline fun <reified E : Enum<E>> enumOrNull(name: String): E? =
        enumValues<E>().firstOrNull { it.name == name }
}

/** A history record as stored in the existing "tasks" table (the Room entity has the same fields). */
data class HistoryRow(
    val id: String,
    val title: String,
    val status: String,
    val stepCount: Int,
    val createdAtMs: Long,
    val updatedAtMs: Long,
    val detail: String?
) {
    /** The history item for this row, or null if the status is not one this version knows. */
    fun toItem(): HistoryItem? {
        val parsed: TaskStatus = TaskStatus.values().firstOrNull { it.name == status } ?: return null
        val (summary, steps) = HistoryCodec.decode(detail)
        return HistoryItem(id, title, parsed, summary, updatedAtMs, steps)
    }

    companion object {
        /** The row to store for [item]. */
        fun from(item: HistoryItem): HistoryRow = HistoryRow(
            id = item.id,
            title = item.title,
            status = item.status.name,
            stepCount = item.steps.size,
            createdAtMs = item.finishedAtMs,
            updatedAtMs = item.finishedAtMs,
            detail = HistoryCodec.encode(item)
        )
    }
}

/**
 * Turns the queue snapshots into history items. Remember a plan with [remember] when it is queued;
 * give every snapshot to [onSnapshot]: the first time a task is seen finished, its item is returned
 * (once only). Pure logic.
 */
class HistoryRecorder(private val clock: () -> Long) {

    private val plans: LinkedHashMap<String, TaskDraft> = LinkedHashMap()
    private var lastRecordedId: String? = null

    /** Keeps the plan of a queued task so its steps can be saved when it finishes. */
    fun remember(draft: TaskDraft) {
        plans[draft.id] = draft
        while (plans.size > MAX_PLANS) plans.remove(plans.keys.first())
    }

    /** The item to save if [snapshot] shows a task that has just finished, else null. */
    fun onSnapshot(snapshot: QueueSnapshot): HistoryItem? {
        val task: TaskSnapshot = snapshot.current ?: return null
        if (task.isOpen || task.id == lastRecordedId) return null
        val draft: TaskDraft = plans.remove(task.id) ?: return null
        lastRecordedId = task.id
        return HistoryItem.from(draft, task, clock())
    }

    private companion object {
        const val MAX_PLANS: Int = 20
    }
}
