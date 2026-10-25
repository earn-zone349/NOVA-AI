package com.nova.ai.accessibility

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.core.NovaResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The result shown in the test card: the raw capture and its summary. */
data class ScreenReadResult(val capture: ScreenCapture, val summary: ScreenSummary)

/**
 * Runs the screen-reading test independently of any screen, so the countdown keeps
 * going while the user opens another app. The test card reads [waitingSeconds],
 * [result] and [errorMessage]. Use from the main thread.
 */
object ScreenReadLab {

    private const val COUNTDOWN_SECONDS: Int = 5
    private const val ONE_SECOND_MS: Long = 1000L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null

    /** Seconds left before the screen is read; 0 when no countdown is running. */
    var waitingSeconds: Int by mutableStateOf(0)
        private set

    /** The last successful reading. */
    var result: ScreenReadResult? by mutableStateOf<ScreenReadResult?>(null)
        private set

    /** The problem of the last reading, if any. */
    var errorMessage: String? by mutableStateOf<String?>(null)
        private set

    /** Reads the screen now. */
    fun readNow() {
        cancel()
        job = scope.launch { readOnce() }
    }

    /** Reads the screen after a short countdown, so the user can open another app first. */
    fun readAfterCountdown() {
        cancel()
        job = scope.launch {
            for (second in COUNTDOWN_SECONDS downTo 1) {
                waitingSeconds = second
                delay(ONE_SECOND_MS)
            }
            waitingSeconds = 0
            readOnce()
        }
    }

    /** Stops a running countdown. */
    fun cancel() {
        job?.cancel()
        job = null
        waitingSeconds = 0
    }

    private suspend fun readOnce() {
        errorMessage = null
        // Reading talks to the system many times, so it runs off the main thread.
        val outcome: NovaResult<ScreenCapture> = withContext(Dispatchers.Default) {
            AccessibilityBridge.readScreen()
        }
        when (outcome) {
            is NovaResult.Success ->
                result = ScreenReadResult(outcome.value, ScreenSummarizer.summarize(outcome.value))
            is NovaResult.Failure -> errorMessage = outcome.error.message
        }
    }
}
