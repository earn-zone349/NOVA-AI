package com.nova.ai.models

import android.content.Context
import android.os.StatFs
import com.nova.ai.audio.WhisperEngine
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.ModelInfo
import com.nova.ai.core.ModelType
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import java.io.File

/**
 * Keeps downloaded models in the app's private storage. A model counts as
 * installed only when every file is present and the "complete" mark was written
 * after the last download finished.
 */
class FileModelManager(context: Context) : LocalModelManager {

    private val appContext: Context = context.applicationContext
    private val root: File = File(appContext.filesDir, ROOT_DIR)

    /** The folder that holds the files of [spec]. */
    fun modelDir(spec: WhisperModelSpec): File = File(root, "whisper-${spec.id}")

    override fun isInstalled(modelId: String): Boolean {
        val spec: WhisperModelSpec = ModelCatalog.find(modelId) ?: return false
        return isInstalled(spec)
    }

    /** True if [spec] is completely downloaded. */
    fun isInstalled(spec: WhisperModelSpec): Boolean {
        val dir: File = modelDir(spec)
        if (!File(dir, COMPLETE_MARK).exists()) return false
        return spec.files.all { File(dir, it.fileName).length() > 0L }
    }

    /** Writes the mark that says every file of [spec] was downloaded. */
    fun markComplete(spec: WhisperModelSpec): NovaResult<Unit> = try {
        File(modelDir(spec), COMPLETE_MARK).writeText("ok")
        NovaResult.Success(Unit)
    } catch (e: Exception) {
        NovaLogger.e(TAG, "Failed to write the complete mark", e)
        NovaResult.failure(ErrorCode.EXECUTION_FAILED, "মডেল সংরক্ষণ শেষ করা যায়নি।", e)
    }

    /** Disk space used by the files of [spec] now. */
    fun installedSizeBytes(spec: WhisperModelSpec): Long {
        val dir: File = modelDir(spec)
        return spec.files.sumOf { File(dir, it.fileName).length() }
    }

    /** Free space left on the phone for app files. */
    fun freeSpaceBytes(): Long = try {
        appContext.filesDir.mkdirs()
        StatFs(appContext.filesDir.path).availableBytes
    } catch (e: Exception) {
        NovaLogger.e(TAG, "Failed to read free space", e)
        0L
    }

    override fun listModels(): NovaResult<List<ModelInfo>> = try {
        val infos: List<ModelInfo> = ModelCatalog.whisperModels.map { spec ->
            val installed: Boolean = isInstalled(spec)
            ModelInfo(
                id = spec.id,
                name = appContext.getString(spec.titleRes),
                type = ModelType.SPEECH,
                sizeBytes = if (installed) installedSizeBytes(spec) else spec.approxBytes,
                isInstalled = installed
            )
        }
        NovaResult.Success(infos)
    } catch (e: Exception) {
        NovaLogger.e(TAG, "Failed to list models", e)
        NovaResult.failure(ErrorCode.EXECUTION_FAILED, "মডেলের তালিকা পড়া যায়নি।", e)
    }

    override fun listModels(type: ModelType): NovaResult<List<ModelInfo>> =
        when (val all: NovaResult<List<ModelInfo>> = listModels()) {
            is NovaResult.Success -> NovaResult.Success(all.value.filter { it.type == type })
            is NovaResult.Failure -> all
        }

    override fun delete(modelId: String): NovaResult<Unit> {
        val spec: WhisperModelSpec = ModelCatalog.find(modelId)
            ?: return NovaResult.failure(ErrorCode.NOT_FOUND, "এই মডেল পাওয়া যায়নি।")
        return try {
            // The engine may still hold the model in memory.
            WhisperEngine.release()
            val dir: File = modelDir(spec)
            if (!dir.exists() || dir.deleteRecursively()) {
                NovaResult.Success(Unit)
            } else {
                NovaResult.failure(ErrorCode.EXECUTION_FAILED, "মডেল মোছা যায়নি।")
            }
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to delete a model", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "মডেল মোছা যায়নি।", e)
        }
    }

    private companion object {
        const val TAG: String = "FileModelManager"
        const val ROOT_DIR: String = "models"
        const val COMPLETE_MARK: String = ".complete"
    }
}
