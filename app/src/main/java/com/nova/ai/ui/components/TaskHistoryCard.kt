package com.nova.ai.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.core.TaskStatus
import com.nova.ai.tasks.HistoryItem
import com.nova.ai.tasks.StepState
import com.nova.ai.tasks.TaskHub
import java.text.DateFormat
import java.util.Date

/**
 * The task history: every finished task with its result and time. A failed or cancelled task can be
 * run again (only its unfinished steps). Tap a task to see its steps. Shows the newest [SHOWN] tasks.
 */
@Composable
fun TaskHistoryCard(modifier: Modifier = Modifier) {
    val history: List<HistoryItem> = TaskHub.history
    var openId: String? by rememberSaveable { mutableStateOf(null) }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.automation_history_title),
                style = MaterialTheme.typography.titleMedium
            )
            if (history.isEmpty()) {
                Text(
                    text = stringResource(R.string.tskh_empty),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            for (item in history.take(SHOWN)) {
                HistoryRowView(item, expanded = openId == item.id) {
                    openId = if (openId == item.id) null else item.id
                }
            }
            if (history.isNotEmpty()) {
                OutlinedButton(onClick = { TaskHub.clearHistory() }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.tskh_clear))
                }
            }
        }
    }
}

@Composable
private fun HistoryRowView(item: HistoryItem, expanded: Boolean, onToggle: () -> Unit) {
    val time: String = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(item.finishedAtMs))
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        OutlinedButton(onClick = onToggle, modifier = Modifier.fillMaxWidth()) {
            Text("${statusIcon(item.status)} ${item.title}")
        }
        Text(
            text = "$time · ${stringResource(statusText(item.status))} · " +
                stringResource(R.string.tsk_progress, item.steps.count { it.state == StepState.DONE }, item.steps.size),
            style = MaterialTheme.typography.bodySmall
        )
        if (expanded) {
            item.summary?.let { Text(text = it, style = MaterialTheme.typography.bodyMedium) }
            for ((position, step) in item.steps.withIndex()) {
                val note: String = if (step.message.isNullOrBlank()) "" else " — ${step.message}"
                Text(
                    text = "${stepIcon(step.state)} ${position + 1}. ${step.title}$note",
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (item.canRerun) {
                OutlinedButton(onClick = { TaskHub.rerun(item) }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.tskh_rerun))
                }
            }
        }
    }
}

private const val SHOWN: Int = 20

private fun statusIcon(status: TaskStatus): String = when (status) {
    TaskStatus.COMPLETED -> "✅"
    TaskStatus.FAILED -> "❌"
    TaskStatus.CANCELLED -> "⏹"
    TaskStatus.PAUSED -> "⏸"
    TaskStatus.RUNNING, TaskStatus.PENDING -> "⏳"
}

private fun stepIcon(state: StepState): String = when (state) {
    StepState.DONE -> "✅"
    StepState.FAILED -> "❌"
    StepState.SKIPPED -> "⏭"
    StepState.CANCELLED -> "⏹"
    else -> "○"
}

private fun statusText(status: TaskStatus): Int = when (status) {
    TaskStatus.PENDING -> R.string.tsk_status_pending
    TaskStatus.RUNNING -> R.string.tsk_status_running
    TaskStatus.PAUSED -> R.string.tsk_status_paused
    TaskStatus.COMPLETED -> R.string.tsk_status_completed
    TaskStatus.FAILED -> R.string.tsk_status_failed
    TaskStatus.CANCELLED -> R.string.tsk_status_cancelled
}
