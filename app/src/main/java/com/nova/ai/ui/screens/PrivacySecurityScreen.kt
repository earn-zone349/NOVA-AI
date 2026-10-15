package com.nova.ai.ui.screens

import android.content.pm.ApplicationInfo
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.data.entity.LogEntity
import com.nova.ai.logging.NovaLogger
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val RECENT_LOG_LIMIT: Int = 5
private const val LOG_MESSAGE_PREVIEW: Int = 80

/** Privacy and Security: local data, sensitive-action rules, and the app log. */
@Composable
fun PrivacySecurityScreen(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val isDebuggable: Boolean =
        (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    var logs: List<LogEntity> by remember { mutableStateOf(emptyList()) }
    var totalCount: Int by remember { mutableStateOf(0) }
    var refreshKey: Int by remember { mutableStateOf(0) }

    // Reload whenever the refresh button is pressed (and once on open).
    LaunchedEffect(refreshKey) {
        val (entries, total) = withContext(Dispatchers.IO) {
            NovaLogger.getRecent(RECENT_LOG_LIMIT) to NovaLogger.count()
        }
        logs = entries
        totalCount = total
    }

    val emptyText: String = stringResource(R.string.privacy_logs_empty)
    val countText: String = stringResource(R.string.privacy_logs_count, totalCount)
    val logBody: String = if (logs.isEmpty()) {
        "$countText\n$emptyText"
    } else {
        countText + "\n" + logs.joinToString("\n") { formatLogLine(it) }
    }

    NovaScreenLayout(
        title = stringResource(R.string.privacy_title),
        subtitle = stringResource(R.string.privacy_subtitle),
        modifier = modifier
    ) {
        NovaInfoCard(
            title = stringResource(R.string.privacy_local_title),
            body = stringResource(R.string.privacy_local_body)
        )
        NovaInfoCard(
            title = stringResource(R.string.privacy_sensitive_title),
            body = stringResource(R.string.privacy_sensitive_body)
        )
        NovaInfoCard(
            title = stringResource(R.string.privacy_log_title),
            body = stringResource(R.string.privacy_log_body)
        )

        NovaInfoCard(
            title = stringResource(R.string.privacy_logs_title),
            body = logBody
        )
        OutlinedButton(
            onClick = { refreshKey += 1 },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(stringResource(R.string.privacy_logs_refresh))
        }

        // Only shown in debug builds, to verify that crashes get saved.
        if (isDebuggable) {
            NovaInfoCard(
                title = stringResource(R.string.privacy_test_crash_title),
                body = stringResource(R.string.privacy_test_crash_note)
            )
            Button(
                onClick = { throw IllegalStateException("NOVA AI intentional test crash") },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.privacy_test_crash_button))
            }
        }
    }
}

private fun formatLogLine(entry: LogEntity): String {
    val time: String = SimpleDateFormat("dd/MM HH:mm:ss", Locale.getDefault())
        .format(Date(entry.timestampMs))
    return "$time [${entry.level}] ${entry.tag}: ${entry.message.take(LOG_MESSAGE_PREVIEW)}"
}
