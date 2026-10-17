package com.nova.ai.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.time.TimeActionUi
import com.nova.ai.time.TimeCommandController
import com.nova.ai.time.TimePlanner
import com.nova.ai.time.TimeText

/**
 * Shows the result of an alarm, timer or reminder command on the Home screen,
 * or asks "morning or evening?" when the time is unclear.
 * Shows nothing while there is nothing to report.
 */
@Composable
fun TimeActionCard(
    controller: TimeCommandController,
    modifier: Modifier = Modifier
) {
    val current: TimeActionUi = controller.state
    if (current is TimeActionUi.Idle) return

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.time_title),
                style = MaterialTheme.typography.titleMedium
            )

            when (current) {
                is TimeActionUi.Idle -> Unit

                is TimeActionUi.Done -> {
                    Text("✅ ${current.message}")
                    OutlinedButton(
                        onClick = { controller.openClockApp() },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.time_open_clock))
                    }
                    if (current.calendar != null) {
                        OutlinedButton(
                            onClick = { controller.addToCalendar() },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(stringResource(R.string.time_add_calendar))
                        }
                    }
                }

                is TimeActionUi.AskPeriod -> {
                    val minuteText: String = current.minute.toString().padStart(2, '0')
                    Text(
                        stringResource(
                            R.string.time_ask_period,
                            TimeText.digits("${current.hour}:$minuteText")
                        )
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = { controller.choosePeriod(isEvening = false) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(TimeText.clock(TimePlanner.to24(current.hour, false), current.minute))
                        }
                        Button(
                            onClick = { controller.choosePeriod(isEvening = true) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(TimeText.clock(TimePlanner.to24(current.hour, true), current.minute))
                        }
                    }
                }

                is TimeActionUi.NeedsDetail -> Text("💡 ${current.message}")

                is TimeActionUi.Failed ->
                    Text(stringResource(R.string.time_failed, current.message))
            }

            TextButton(onClick = { controller.dismiss() }) {
                Text(stringResource(R.string.action_dismiss))
            }
        }
    }
}
