package com.nova.ai.models

/** Where a model download stands right now. */
sealed class ModelDownloadState {
    /** Nothing is being downloaded. */
    object Idle : ModelDownloadState()

    /** Downloading: [percent] 0 to 99 and the megabytes saved so far. */
    data class Downloading(val percent: Int, val downloadedMegabytes: Int) : ModelDownloadState()

    /** The last download stopped with a problem. Starting again continues from where it stopped. */
    data class Failed(val message: String) : ModelDownloadState()
}
