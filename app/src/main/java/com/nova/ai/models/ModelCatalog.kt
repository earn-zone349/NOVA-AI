package com.nova.ai.models

import androidx.annotation.StringRes
import com.nova.ai.R

private const val REPO_BASE_URL: String = "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-"
private const val BYTES_PER_MEGABYTE: Long = 1_048_576L

/** One file of a model and where to download it from. */
data class ModelFile(val fileName: String, val url: String)

/**
 * A Whisper speech model (in sherpa-onnx format, 8-bit) that can be downloaded.
 * [approxMegabytes] is only an estimate, used for the progress bar and free-space check.
 */
data class WhisperModelSpec(
    val id: String,
    @StringRes val titleRes: Int,
    val approxMegabytes: Int
) {
    val encoderFile: String get() = "$id-encoder.int8.onnx"
    val decoderFile: String get() = "$id-decoder.int8.onnx"
    val tokensFile: String get() = "$id-tokens.txt"
    val approxBytes: Long get() = approxMegabytes * BYTES_PER_MEGABYTE

    /** Every file the model needs, with its download address. */
    val files: List<ModelFile>
        get() = listOf(encoderFile, decoderFile, tokensFile).map { name ->
            ModelFile(name, "$REPO_BASE_URL$id/resolve/main/$name")
        }
}

/** The models NOVA knows how to download. */
object ModelCatalog {

    val whisperModels: List<WhisperModelSpec> = listOf(
        WhisperModelSpec("tiny", R.string.model_whisper_tiny, 100),
        WhisperModelSpec("base", R.string.model_whisper_base, 160),
        WhisperModelSpec("small", R.string.model_whisper_small, 375)
    )

    /** The model with [id], or null if unknown. */
    fun find(id: String): WhisperModelSpec? = whisperModels.firstOrNull { it.id == id }
}
