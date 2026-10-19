package com.nova.ai.models

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.core.NovaResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Runs model downloads independently of any screen, so a download keeps going
 * when the user switches tabs. Screens read [stateOf] and [revision].
 * Use from the main thread.
 */
object ModelDownloadHub {

    private const val BYTES_PER_MEGABYTE: Long = 1_048_576L
    private const val MAX_PERCENT_WHILE_RUNNING: Int = 99

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val jobs = HashMap<String, Job>()
    private val states = mutableStateMapOf<String, ModelDownloadState>()

    /** Changes whenever a download ends or a model is deleted, so screens refresh. */
    var revision: Int by mutableStateOf(0)
        private set

    /** The download state of the model [modelId]. */
    fun stateOf(modelId: String): ModelDownloadState = states[modelId] ?: ModelDownloadState.Idle

    /** Starts (or continues) downloading [spec]. */
    fun start(context: Context, spec: WhisperModelSpec) {
        if (jobs[spec.id]?.isActive == true) return

        val downloader = ModelDownloader(FileModelManager(context.applicationContext))
        states[spec.id] = ModelDownloadState.Downloading(0, 0)

        jobs[spec.id] = scope.launch {
            try {
                val result: NovaResult<Unit> = withContext(Dispatchers.IO) {
                    downloader.download(spec, isCancelled = { !isActive }) { bytes ->
                        postProgress(spec, bytes)
                    }
                }
                when (result) {
                    is NovaResult.Success -> states.remove(spec.id)
                    is NovaResult.Failure -> states[spec.id] = ModelDownloadState.Failed(result.error.message)
                }
            } finally {
                jobs.remove(spec.id)
                revision += 1
            }
        }
    }

    /** Stops the download of [modelId]. The saved part stays, so it can continue later. */
    fun cancel(modelId: String) {
        jobs[modelId]?.cancel()
        states.remove(modelId)
    }

    /** Deletes the downloaded files of [spec]. */
    fun delete(context: Context, spec: WhisperModelSpec): NovaResult<Unit> {
        val result: NovaResult<Unit> = FileModelManager(context.applicationContext).delete(spec.id)
        revision += 1
        return result
    }

    // Called from the download thread; the state is updated on the main thread.
    private fun postProgress(spec: WhisperModelSpec, bytes: Long) {
        val percent: Int = (bytes * 100L / spec.approxBytes).toInt().coerceIn(0, MAX_PERCENT_WHILE_RUNNING)
        val megabytes: Int = (bytes / BYTES_PER_MEGABYTE).toInt()
        scope.launch {
            if (jobs.containsKey(spec.id)) {
                states[spec.id] = ModelDownloadState.Downloading(percent, megabytes)
            }
        }
    }
}
