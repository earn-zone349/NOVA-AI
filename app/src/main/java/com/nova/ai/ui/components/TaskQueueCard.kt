package com.nova.ai.ui.components

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.core.NovaResult
import com.nova.ai.core.TaskStatus
import com.nova.ai.tasks.QueueSnapshot
import com.nova.ai.tasks.StepSnapshot
import com.nova.ai.tasks.StepState
import com.nova.ai.tasks.TaskHub
import com.nova.ai.tasks.TaskSnapshot

/**
 * Shows the task NOVA is running (every step with its state), the tasks waiting behind it, a
 * question when a step needs an answer, and the controls (pause, cancel). With [showInput] the card
 * also has a box to type a command with several parts; without it, the card appears only while
 * there is something to show (used on the Home screen).
 */
@Composable
fun TaskQueueCard(modifier: Modifier = Modifier, showInput: Boolean = true) {
    val context: Context = LocalContext.current
    val snapshot: QueueSnapshot = TaskHub.state
    val current: TaskSnapshot? = snapshot.current

    var typed: String by rememberSaveable { mutableStateOf("") }

    if (!showInput && current == null && snapshot.waiting.isEmpty() && snapshot.notice == null) return

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.tsk_card_title),
                style = MaterialTheme.typography.titleMedium
            )

            if (showInput) {
                Text(
                    text = stringResource(R.string.tsk_card_note),
                    style = MaterialTheme.typography.bodySmall
                )
                OutlinedTextField(
                    value = typed,
                    onValueChange = { typed = it },
                    label = { Text(stringResource(R.string.tsk_input_label)) },
                    modifier = Modifier.fillMaxWidth()
                )
                Button(
                    onClick = {
                        if (TaskHub.submit(context, typed) is NovaResult.Success) typed = ""
                    },
                    enabled = typed.isNotBlank(),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.tsk_run))
                }
            }

            snapshot.notice?.let { notice ->
                Text(
                    text = notice,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (snapshot.noticeIsError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
                )
            }

            if (current != null) TaskBlock(current)

            if (snapshot.waiting.isNotEmpty()) {
                Text(
                    text = stringResource(R.string.tsk_waiting, snapshot.waiting.joinToString(" • ")),
                    style = MaterialTheme.typography.bodySmall
                )
                OutlinedButton(
                    onClick = { TaskHub.cancelAll() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.tsk_cancel_all))
                }
            }

            if (current != null && !current.isOpen) {
                OutlinedButton(
                    onClick = { TaskHub.dismiss() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.tsk_dismiss))
                }
            } else if (snapshot.notice != null && current == null) {
                OutlinedButton(
                    onClick = { TaskHub.dismiss() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.tsk_dismiss))
                }
            }
        }
    }
}

// One task: title, progress, the steps, the question (if any) and the pause and cancel buttons.
@Composable
private fun TaskBlock(task: TaskSnapshot) {
    Text(text = task.title, style = MaterialTheme.typography.bodyMedium)
    Text(
        text = stringResource(R.string.tsk_progress, task.doneCount, task.steps.size) +
            " · " + stringResource(statusText(task.status)),
        style = MaterialTheme.typography.bodySmall
    )
    for ((position, step) in task.steps.withIndex()) {
        Text(
            text = "${icon(step.state)} ${position + 1}. ${stepLine(step)}",
            style = MaterialTheme.typography.bodySmall
        )
    }
    task.summary?.let { Text(text = it, style = MaterialTheme.typography.bodyMedium) }

    task.question?.let { question ->
        Text(text = question.text, style = MaterialTheme.typography.bodyMedium)
        for ((index, label) in question.options.withIndex()) {
            Button(
                onClick = { TaskHub.answer(index) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(label)
            }
        }
    }

    if (task.isOpen) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (task.status == TaskStatus.PAUSED) {
                Button(onClick = { TaskHub.resume() }, modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.tsk_resume))
                }
            } else {
                OutlinedButton(onClick = { TaskHub.pause() }, modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.tsk_pause))
                }
            }
            OutlinedButton(onClick = { TaskHub.cancelCurrent() }, modifier = Modifier.weight(1f)) {
                Text(stringResource(R.string.tsk_cancel))
            }
        }
    }
}

private fun stepLine(step: StepSnapshot): String {
    val tries: String = if (step.attempt > 1 && step.state != StepState.DONE) " [${step.attempt}/${step.maxAttempts}]" else ""
    val note: String = if (step.message.isNullOrBlank()) "" else " — ${step.message}"
    return step.title + tries + note
}

private fun icon(state: StepState): String = when (state) {
    StepState.PENDING -> "○"
    StepState.RUNNING -> "▶"
    StepState.RETRYING -> "🔁"
    StepState.WAITING_USER -> "❓"
    StepState.DONE -> "✅"
    StepState.FAILED -> "❌"
    StepState.SKIPPED -> "⏭"
    StepState.CANCELLED -> "⏹"
}

private fun statusText(status: TaskStatus): Int = when (status) {
    TaskStatus.PENDING -> R.string.tsk_status_pending
    TaskStatus.RUNNING -> R.string.tsk_status_running
    TaskStatus.PAUSED -> R.string.tsk_status_paused
    TaskStatus.COMPLETED -> R.string.tsk_status_completed
    TaskStatus.FAILED -> R.string.tsk_status_failed
    TaskStatus.CANCELLED -> R.string.tsk_status_cancelled
}
