#!/usr/bin/env bash
# NOVA AI - Engine phase E3: offline Whisper speech recognition (sherpa-onnx) and a model manager.
# Additive: new models package and Whisper engine; a few additive lines in existing files.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
MANIFEST="app/src/main/AndroidManifest.xml"
APP_GRADLE="app/build.gradle.kts"
WORKFLOW=".github/workflows/build-apk.yml"
CONTROLLER_FILE="$BASE/audio/MicLabController.kt"
CARD_FILE="$BASE/ui/components/MicLabCard.kt"
BRAIN_FILE="$BASE/ui/screens/AiBrainScreen.kt"

SHERPA_VERSION="1.13.8"
SHERPA_SHA256="633c24321e06b1fe79feafa03ea16cbc0f8a286641e2da3559bac91bdb13bd96"

for required in \
  "$CONTROLLER_FILE" "$CARD_FILE" "$BRAIN_FILE" \
  "$BASE/audio/GoogleRecognizerBridge.kt" \
  "$BASE/models/LocalModelManager.kt" \
  "$BASE/core/Models.kt" \
  "$APP_GRADLE" "$WORKFLOW" "$MANIFEST" ".gitignore"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after E1, E2 and E4 are installed." >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
mkdir -p "$BASE/models"

# ---------- A. Manifest: internet access (needed to download models) ----------
if ! grep -q "android.permission.INTERNET" "$MANIFEST"; then
  cat > "$TMP_DIR/manifest_add.txt" <<'EOF'
    <uses-permission android:name="android.permission.INTERNET" />
EOF
  sed -i "/android.permission.RECORD_AUDIO/r $TMP_DIR/manifest_add.txt" "$MANIFEST"
fi
grep -q "android.permission.INTERNET" "$MANIFEST" || { echo "ERROR: manifest edit failed" >&2; exit 1; }

# ---------- B. App build file: sherpa-onnx library and phone type ----------
if ! grep -q "sherpa-onnx" "$APP_GRADLE"; then
  grep -q 'ksp(libs.androidx.room.compiler)' "$APP_GRADLE" \
    || { echo "ERROR: app build file anchor (dependencies) not found" >&2; exit 1; }
  cat > "$TMP_DIR/gradle_dep.txt" <<EOF
    implementation(files("libs/sherpa-onnx-${SHERPA_VERSION}.aar"))
EOF
  sed -i "/ksp(libs.androidx.room.compiler)/r $TMP_DIR/gradle_dep.txt" "$APP_GRADLE"
fi
grep -q "sherpa-onnx-${SHERPA_VERSION}.aar" "$APP_GRADLE" || { echo "ERROR: app build file edit failed (library)" >&2; exit 1; }

if ! grep -q "abiFilters" "$APP_GRADLE"; then
  grep -q 'versionName = "0.1.0"' "$APP_GRADLE" \
    || { echo "ERROR: app build file anchor (versionName) not found" >&2; exit 1; }
  cat > "$TMP_DIR/gradle_abi.txt" <<'EOF'
        // Modern phones are 64-bit ARM; this keeps the app small.
        ndk { abiFilters.add("arm64-v8a") }
EOF
  sed -i "/versionName = \"0.1.0\"/r $TMP_DIR/gradle_abi.txt" "$APP_GRADLE"
fi
grep -q "abiFilters" "$APP_GRADLE" || { echo "ERROR: app build file edit failed (abi)" >&2; exit 1; }

# ---------- C. Build workflow: download the library and check its checksum ----------
if ! grep -q "sherpa-onnx-${SHERPA_VERSION}.aar" "$WORKFLOW"; then
  grep -q "gradle-version: '8.7'" "$WORKFLOW" \
    || { echo "ERROR: workflow anchor not found" >&2; exit 1; }
  cat > "$TMP_DIR/workflow_step.txt" <<EOF

      - name: Download sherpa-onnx library (speech engine)
        run: |
          mkdir -p app/libs
          curl -fL --retry 3 -o app/libs/sherpa-onnx-${SHERPA_VERSION}.aar https://github.com/k2-fsa/sherpa-onnx/releases/download/v${SHERPA_VERSION}/sherpa-onnx-${SHERPA_VERSION}.aar
          echo "${SHERPA_SHA256}  app/libs/sherpa-onnx-${SHERPA_VERSION}.aar" | sha256sum -c -
EOF
  sed -i "/gradle-version: '8.7'/r $TMP_DIR/workflow_step.txt" "$WORKFLOW"
fi
grep -q "sherpa-onnx-${SHERPA_VERSION}.aar" "$WORKFLOW" || { echo "ERROR: workflow edit failed" >&2; exit 1; }

# ---------- D. Keep the big library file out of git ----------
if ! grep -q "app/libs/" .gitignore; then
  printf '\n# Downloaded during the build\napp/libs/*.aar\n' >> .gitignore
fi

# ---------- E. New strings file ----------
cat > app/src/main/res/values/strings_e3.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="models_title">অফলাইন মডেল (ইঞ্জিন E3)</string>
    <string name="models_note">ইন্টারনেট ছাড়া কথা চেনার জন্য Whisper মডেল ফোনে নামিয়ে রাখা যায়। একবার নামালে আর নেট লাগে না।</string>
    <string name="models_wifi_note">ফাইল বড়, তাই ওয়াইফাই ব্যবহার করো। নেট কেটে গেলে আবার চালালে যেখানে থেমেছিল সেখান থেকে চলবে।</string>
    <string name="models_free_space">ফোনে ফাঁকা জায়গা: %1$s</string>

    <string name="model_whisper_tiny">Whisper tiny (সবচেয়ে দ্রুত, কম নির্ভুল)</string>
    <string name="model_whisper_base">Whisper base (মাঝারি)</string>
    <string name="model_whisper_small">Whisper small (ধীর, বেশি নির্ভুল)</string>
    <string name="model_size">আকার: প্রায় %1$d MB</string>
    <string name="model_installed">✓ ফোনে আছে (%1$s)</string>
    <string name="model_download">ডাউনলোড করো</string>
    <string name="model_resume">আবার চালাও</string>
    <string name="model_downloading">ডাউনলোড হচ্ছে: %1$d%% (%2$d MB)</string>
    <string name="model_cancel">ডাউনলোড থামাও</string>
    <string name="model_delete">মুছে ফেলো</string>
    <string name="model_failed">ডাউনলোড ব্যর্থ: %1$s</string>

    <string name="whisper_use_label">Google-এর বদলে অফলাইন Whisper ব্যবহার করো</string>
    <string name="whisper_model_title">কোন Whisper মডেল</string>
    <string name="whisper_note">Whisper ধীরে চলে: ছোট কথায়ও কয়েক সেকেন্ড লাগতে পারে, আর প্রথমবার মডেল লোড হতে বেশি সময় যায়।</string>
    <string name="whisper_missing">এই মডেল এখনো ডাউনলোড করা হয়নি। \"অফলাইন মডেল\" কার্ড থেকে নামাও।</string>
</resources>
EOF

# ---------- 1. ModelCatalog.kt ----------
cat > "$BASE/models/ModelCatalog.kt" <<'EOF'
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
EOF

# ---------- 2. FileModelManager.kt ----------
cat > "$BASE/models/FileModelManager.kt" <<'EOF'
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
EOF

# ---------- 3. ModelDownloader.kt ----------
cat > "$BASE/models/ModelDownloader.kt" <<'EOF'
package com.nova.ai.models

import android.os.SystemClock
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Downloads the files of a model, one after another, and keeps unfinished
 * files so a stopped download continues where it left off.
 * Blocking: call from a background thread. Addresses are never logged.
 */
class ModelDownloader(private val manager: FileModelManager) {

    /** Passes progress on at most a few times per second. */
    private class ProgressThrottle(private val onProgress: (Long) -> Unit) {
        private var lastMs: Long = 0L

        fun report(bytes: Long, force: Boolean = false) {
            val now: Long = SystemClock.elapsedRealtime()
            if (force || now - lastMs >= REPORT_INTERVAL_MS) {
                lastMs = now
                onProgress(bytes)
            }
        }
    }

    /**
     * Downloads every file of [spec]. [isCancelled] is checked while downloading.
     * [onProgress] receives the total bytes of this model on disk so far.
     */
    fun download(
        spec: WhisperModelSpec,
        isCancelled: () -> Boolean,
        onProgress: (Long) -> Unit
    ): NovaResult<Unit> {
        val dir: File = manager.modelDir(spec)
        if (!dir.exists() && !dir.mkdirs()) {
            return NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_STORAGE)
        }

        val alreadyOnDisk: Long = spec.files.sumOf { file ->
            File(dir, file.fileName).length() + File(dir, file.fileName + PART_SUFFIX).length()
        }
        val stillNeeded: Long = (spec.approxBytes - alreadyOnDisk).coerceAtLeast(0L)
        val neededWithMargin: Long = stillNeeded + stillNeeded / SPACE_MARGIN_DIVISOR
        if (manager.freeSpaceBytes() < neededWithMargin) {
            val megabytes: Long = neededWithMargin / BYTES_PER_MEGABYTE
            return NovaResult.failure(
                ErrorCode.NOT_AVAILABLE,
                "ফোনে যথেষ্ট ফাঁকা জায়গা নেই। দরকার প্রায় $megabytes MB।"
            )
        }

        val throttle = ProgressThrottle(onProgress)
        var finishedBytes = 0L
        for (file in spec.files) {
            if (isCancelled()) return NovaResult.failure(ErrorCode.CANCELLED, MSG_CANCELLED)

            val target = File(dir, file.fileName)
            val base: Long = finishedBytes
            val result: NovaResult<Unit> = downloadFile(file.url, target, isCancelled) { fileBytes ->
                throttle.report(base + fileBytes)
            }
            if (result is NovaResult.Failure) return result

            finishedBytes += target.length()
            throttle.report(finishedBytes, force = true)
        }
        return manager.markComplete(spec)
    }

    private fun downloadFile(
        url: String,
        target: File,
        isCancelled: () -> Boolean,
        onFileBytes: (Long) -> Unit
    ): NovaResult<Unit> {
        // A finished file has its final name; only unfinished data has the .part ending.
        if (target.exists() && target.length() > 0L) {
            onFileBytes(target.length())
            return NovaResult.Success(Unit)
        }

        val part = File(target.parentFile, target.name + PART_SUFFIX)
        val resumeFrom: Long = if (part.exists()) part.length() else 0L
        var connection: HttpURLConnection? = null

        return try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                instanceFollowRedirects = true
                setRequestProperty("User-Agent", USER_AGENT)
                if (resumeFrom > 0L) setRequestProperty("Range", "bytes=$resumeFrom-")
            }

            val code: Int = connection.responseCode
            val append: Boolean = when (code) {
                HttpURLConnection.HTTP_PARTIAL -> true
                HttpURLConnection.HTTP_OK -> false
                HTTP_RANGE_NOT_SATISFIABLE -> return finishIfPartIsComplete(part, target, resumeFrom, onFileBytes)
                else -> return NovaResult.failure(ErrorCode.NOT_AVAILABLE, "সার্ভার সাড়া দিয়েছে: $code")
            }

            val startOffset: Long = if (append) resumeFrom else 0L
            val contentLength: Long = connection.contentLengthLong
            val expectedTotal: Long = if (contentLength >= 0L) startOffset + contentLength else -1L
            var written: Long = startOffset

            connection.inputStream.use { input ->
                FileOutputStream(part, append).use { output ->
                    val buffer = ByteArray(BUFFER_BYTES)
                    while (true) {
                        if (isCancelled()) {
                            return NovaResult.failure(ErrorCode.CANCELLED, MSG_CANCELLED)
                        }
                        val readCount: Int = input.read(buffer)
                        if (readCount < 0) break
                        output.write(buffer, 0, readCount)
                        written += readCount
                        onFileBytes(written)
                    }
                }
            }

            if (expectedTotal >= 0L && written != expectedTotal) {
                return NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_INCOMPLETE)
            }
            if (target.exists()) target.delete()
            if (!part.renameTo(target)) {
                return NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_STORAGE)
            }
            onFileBytes(target.length())
            NovaResult.Success(Unit)
        } catch (e: IOException) {
            NovaLogger.w(TAG, "Download interrupted", e)
            NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_NETWORK, e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Download failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_GENERIC, e)
        } finally {
            connection?.disconnect()
        }
    }

    /** The server says there is nothing more to send: the saved part is probably the whole file. */
    private fun finishIfPartIsComplete(
        part: File,
        target: File,
        resumeFrom: Long,
        onFileBytes: (Long) -> Unit
    ): NovaResult<Unit> {
        if (resumeFrom > 0L && part.renameTo(target)) {
            onFileBytes(target.length())
            return NovaResult.Success(Unit)
        }
        part.delete()
        return NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_INCOMPLETE)
    }

    private companion object {
        const val TAG: String = "ModelDownloader"
        const val PART_SUFFIX: String = ".part"
        const val USER_AGENT: String = "NOVA-AI"
        const val BUFFER_BYTES: Int = 64 * 1024
        const val CONNECT_TIMEOUT_MS: Int = 15_000
        const val READ_TIMEOUT_MS: Int = 30_000
        const val REPORT_INTERVAL_MS: Long = 250L
        const val HTTP_RANGE_NOT_SATISFIABLE: Int = 416
        const val BYTES_PER_MEGABYTE: Long = 1_048_576L
        const val SPACE_MARGIN_DIVISOR: Long = 10L

        const val MSG_CANCELLED: String = "ডাউনলোড থামানো হয়েছে।"
        const val MSG_STORAGE: String = "ফোনে ফাইল সংরক্ষণ করা যায়নি।"
        const val MSG_INCOMPLETE: String = "ডাউনলোড অসম্পূর্ণ থেকে গেছে। আবার চেষ্টা করো।"
        const val MSG_NETWORK: String =
            "ইন্টারনেট সমস্যা। আবার চালালে যেখানে থেমেছিল সেখান থেকে চলবে।"
        const val MSG_GENERIC: String = "ডাউনলোডে সমস্যা হয়েছে।"
    }
}
EOF

# ---------- 4. ModelDownloadState.kt ----------
cat > "$BASE/models/ModelDownloadState.kt" <<'EOF'
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
EOF

# ---------- 5. ModelDownloadHub.kt ----------
cat > "$BASE/models/ModelDownloadHub.kt" <<'EOF'
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
EOF

# ---------- 6. RecognitionRouting.kt ----------
cat > "$BASE/audio/RecognitionRouting.kt" <<'EOF'
package com.nova.ai.audio

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Which recognizer turns speech into text. Held in memory for the test card;
 * the final conversation settings come in a later phase.
 */
object RecognitionRouting {

    private const val DEFAULT_WHISPER_MODEL: String = "small"

    /** True: use the offline Whisper model. False: use Google's recognizer. */
    var useWhisper: Boolean by mutableStateOf(false)

    /** The id of the Whisper model to use (see ModelCatalog). */
    var whisperModelId: String by mutableStateOf(DEFAULT_WHISPER_MODEL)
}
EOF

# ---------- 7. WhisperEngine.kt ----------
cat > "$BASE/audio/WhisperEngine.kt" <<'EOF'
package com.nova.ai.audio

import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineWhisperModelConfig
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import com.nova.ai.models.WhisperModelSpec
import java.io.File

/**
 * Turns recorded speech into text with a Whisper model that runs inside the phone
 * (through the sherpa-onnx library). The model stays loaded between requests;
 * the first request is slower because of the loading. Sound and text are never logged.
 */
object WhisperEngine {

    private const val TAG: String = "WhisperEngine"
    private const val PCM_SCALE: Float = 32768f
    private const val MIN_THREADS: Int = 2
    private const val MAX_THREADS: Int = 4

    private var recognizer: OfflineRecognizer? = null
    private var loadedKey: String? = null

    /**
     * Converts [samples] (16 kHz, mono) to text. [languageCode] is "bn" for Bangla,
     * "en" for English, or "" to let the model detect the language.
     * Blocking and heavy: call from a background thread.
     */
    @Synchronized
    fun transcribe(
        modelDir: File,
        spec: WhisperModelSpec,
        samples: ShortArray,
        languageCode: String
    ): NovaResult<String> {
        if (samples.isEmpty()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, "শোনার মতো অডিও নেই।")
        }
        return try {
            val engine: OfflineRecognizer = obtain(modelDir, spec, languageCode)
            val floats = FloatArray(samples.size) { index -> samples[index] / PCM_SCALE }
            val stream = engine.createStream()
            try {
                stream.acceptWaveform(floats, AudioConfig.SAMPLE_RATE_HZ)
                engine.decode(stream)
                NovaResult.Success(engine.getResult(stream).text.trim())
            } finally {
                stream.release()
            }
        } catch (e: OutOfMemoryError) {
            NovaLogger.e(TAG, "Out of memory while running Whisper", e)
            releaseInternal()
            NovaResult.failure(
                ErrorCode.EXECUTION_FAILED,
                "ফোনের RAM কম পড়েছে। ছোট মডেল বেছে দেখো।",
                e
            )
        } catch (e: Throwable) {
            NovaLogger.e(TAG, "Whisper failed", e)
            releaseInternal()
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "Whisper চালাতে সমস্যা হয়েছে।", e)
        }
    }

    /** Frees the model from memory. It is loaded again when needed. */
    @Synchronized
    fun release() {
        releaseInternal()
    }

    private fun obtain(modelDir: File, spec: WhisperModelSpec, languageCode: String): OfflineRecognizer {
        val key = "${spec.id}|$languageCode"
        val existing: OfflineRecognizer? = recognizer
        if (existing != null && loadedKey == key) return existing

        releaseInternal()
        val whisper = OfflineWhisperModelConfig(
            encoder = File(modelDir, spec.encoderFile).absolutePath,
            decoder = File(modelDir, spec.decoderFile).absolutePath,
            language = languageCode,
            task = "transcribe"
        )
        val modelConfig = OfflineModelConfig(
            whisper = whisper,
            tokens = File(modelDir, spec.tokensFile).absolutePath,
            numThreads = threadCount(),
            debug = false
        )
        val created = OfflineRecognizer(config = OfflineRecognizerConfig(modelConfig = modelConfig))
        recognizer = created
        loadedKey = key
        return created
    }

    private fun releaseInternal() {
        try {
            recognizer?.release()
        } catch (e: Throwable) {
            NovaLogger.e(TAG, "Failed to release the model", e)
        } finally {
            recognizer = null
            loadedKey = null
        }
    }

    private fun threadCount(): Int =
        Runtime.getRuntime().availableProcessors().coerceIn(MIN_THREADS, MAX_THREADS)
}
EOF

# ---------- 8. RecognitionGateway.kt ----------
cat > "$BASE/audio/RecognitionGateway.kt" <<'EOF'
package com.nova.ai.audio

import android.content.Context
import android.os.SystemClock
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaError
import com.nova.ai.core.NovaResult
import com.nova.ai.models.FileModelManager
import com.nova.ai.models.ModelCatalog
import com.nova.ai.models.WhisperModelSpec
import com.nova.ai.settings.AppLanguage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * One place that turns speech into text. It sends the sound to Google's recognizer,
 * or to the offline Whisper model when [RecognitionRouting.useWhisper] is on.
 * Same calls and result type as [GoogleRecognizerBridge]. One request at a time.
 * Use from the main thread.
 */
class RecognitionGateway(
    context: Context,
    private val scope: CoroutineScope
) {

    private val appContext: Context = context.applicationContext
    private val google = GoogleRecognizerBridge(appContext, scope)
    private val models = FileModelManager(appContext)
    private var whisperJob: Job? = null

    /** True if this Android version can feed our own sound to Google's recognizer. */
    fun isFeedSupported(): Boolean = google.isFeedSupported()

    /** True if the phone has Google's offline recognizer. */
    fun isOnDeviceAvailable(): Boolean = google.isOnDeviceAvailable()

    /** Converts [samples] to text and reports the result to [onResult] on the main thread. */
    fun recognize(
        samples: ShortArray,
        service: GoogleRecognizerBridge.Service,
        language: AppLanguage,
        onResult: (GoogleRecognizerBridge.Outcome) -> Unit
    ) {
        cancel()
        if (RecognitionRouting.useWhisper) {
            recognizeWithWhisper(samples, language, onResult)
        } else {
            google.recognize(samples, service, language, onResult)
        }
    }

    /** Stops the request in progress without reporting a result. */
    fun cancel() {
        google.cancel()
        whisperJob?.cancel()
        whisperJob = null
    }

    private fun recognizeWithWhisper(
        samples: ShortArray,
        language: AppLanguage,
        onResult: (GoogleRecognizerBridge.Outcome) -> Unit
    ) {
        val spec: WhisperModelSpec? = ModelCatalog.find(RecognitionRouting.whisperModelId)
        if (spec == null || !models.isInstalled(spec)) {
            onResult(failure(ErrorCode.NOT_AVAILABLE, MSG_MODEL_MISSING))
            return
        }

        val startedAtMs: Long = SystemClock.elapsedRealtime()
        val languageCode: String = languageCodeOf(language)
        whisperJob = scope.launch {
            val result: NovaResult<String> = withContext(Dispatchers.Default) {
                WhisperEngine.transcribe(models.modelDir(spec), spec, samples, languageCode)
            }
            val latency: Long = SystemClock.elapsedRealtime() - startedAtMs
            whisperJob = null
            onResult(
                when (result) {
                    is NovaResult.Success ->
                        GoogleRecognizerBridge.Outcome(result.value.takeIf { it.isNotBlank() }, null, latency)
                    is NovaResult.Failure ->
                        GoogleRecognizerBridge.Outcome(null, result.error, latency)
                }
            )
        }
    }

    // "" lets Whisper detect the language itself (used for mixed Bangla and English).
    private fun languageCodeOf(language: AppLanguage): String = when (language) {
        AppLanguage.BANGLA -> "bn"
        AppLanguage.ENGLISH -> "en"
        AppLanguage.MIXED -> ""
    }

    private fun failure(code: ErrorCode, message: String): GoogleRecognizerBridge.Outcome =
        GoogleRecognizerBridge.Outcome(text = null, error = NovaError(code, message), latencyMs = 0L)

    private companion object {
        const val MSG_MODEL_MISSING: String =
            "Whisper মডেল ফোনে নেই। \"অফলাইন মডেল\" কার্ড থেকে নামাও।"
    }
}
EOF

# ---------- 9. WhisperEngineSection.kt ----------
cat > "$BASE/ui/components/WhisperEngineSection.kt" <<'EOF'
package com.nova.ai.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.audio.RecognitionRouting
import com.nova.ai.models.FileModelManager
import com.nova.ai.models.ModelCatalog
import com.nova.ai.models.ModelDownloadHub
import com.nova.ai.models.WhisperModelSpec

/**
 * The offline Whisper part of the recognition settings: the on/off switch and
 * the choice of model. Shown inside the test card.
 */
@Composable
fun ColumnScope.WhisperEngineSection() {
    val context = LocalContext.current
    val manager: FileModelManager = remember { FileModelManager(context) }

    // Reading this makes the labels refresh after a download ends or a model is deleted.
    val refreshTick: Int = ModelDownloadHub.revision
    val selected: WhisperModelSpec =
        ModelCatalog.find(RecognitionRouting.whisperModelId) ?: ModelCatalog.whisperModels.first()

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = stringResource(R.string.whisper_use_label),
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f)
        )
        Switch(
            checked = RecognitionRouting.useWhisper,
            onCheckedChange = { RecognitionRouting.useWhisper = it }
        )
    }
    Text(
        text = stringResource(R.string.whisper_note),
        style = MaterialTheme.typography.bodySmall
    )

    NovaChoiceGroup(
        title = stringResource(R.string.whisper_model_title),
        options = ModelCatalog.whisperModels,
        selected = selected,
        labelOf = { spec -> whisperModelLabel(spec, manager.isInstalled(spec), refreshTick) },
        onSelected = { RecognitionRouting.whisperModelId = it.id }
    )

    if (RecognitionRouting.useWhisper && !manager.isInstalled(selected)) {
        Text(
            text = stringResource(R.string.whisper_missing),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error
        )
    }
}

@Composable
private fun whisperModelLabel(spec: WhisperModelSpec, installed: Boolean, refreshTick: Int): String {
    // refreshTick only forces this label to be rebuilt; it is not shown.
    check(refreshTick >= 0)
    return stringResource(spec.titleRes) + if (installed) " ✓" else ""
}
EOF

# ---------- 10. ModelManagerCard.kt ----------
cat > "$BASE/ui/components/ModelManagerCard.kt" <<'EOF'
package com.nova.ai.ui.components

import android.content.Context
import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.models.FileModelManager
import com.nova.ai.models.ModelCatalog
import com.nova.ai.models.ModelDownloadHub
import com.nova.ai.models.ModelDownloadState
import com.nova.ai.models.WhisperModelSpec

/**
 * Model manager: download, stop and delete the offline Whisper models.
 * Downloads continue even if the user leaves this tab.
 */
@Composable
fun ModelManagerCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val manager: FileModelManager = remember { FileModelManager(context) }

    // Reading this makes the card refresh after a download ends or a model is deleted.
    val refreshTick: Int = ModelDownloadHub.revision

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.models_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.models_note),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.models_wifi_note),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(
                    R.string.models_free_space,
                    Formatter.formatShortFileSize(context, manager.freeSpaceBytes())
                ),
                style = MaterialTheme.typography.bodySmall
            )

            ModelCatalog.whisperModels.forEach { spec ->
                key(spec.id) { ModelRow(context, manager, spec, refreshTick) }
            }
        }
    }
}

@Composable
private fun ModelRow(
    context: Context,
    manager: FileModelManager,
    spec: WhisperModelSpec,
    refreshTick: Int
) {
    // refreshTick only forces this row to be rebuilt; it is not shown.
    check(refreshTick >= 0)

    val installed: Boolean = manager.isInstalled(spec)
    val state: ModelDownloadState = ModelDownloadHub.stateOf(spec.id)

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = stringResource(spec.titleRes),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )

        when {
            installed -> {
                Text(
                    text = stringResource(
                        R.string.model_installed,
                        Formatter.formatShortFileSize(context, manager.installedSizeBytes(spec))
                    ),
                    style = MaterialTheme.typography.bodySmall
                )
                OutlinedButton(onClick = { ModelDownloadHub.delete(context, spec) }) {
                    Text(stringResource(R.string.model_delete))
                }
            }

            state is ModelDownloadState.Downloading -> {
                LinearProgressIndicator(
                    progress = { state.percent / 100f },
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    text = stringResource(
                        R.string.model_downloading,
                        state.percent,
                        state.downloadedMegabytes
                    ),
                    style = MaterialTheme.typography.bodySmall
                )
                OutlinedButton(onClick = { ModelDownloadHub.cancel(spec.id) }) {
                    Text(stringResource(R.string.model_cancel))
                }
            }

            else -> {
                Text(
                    text = stringResource(R.string.model_size, spec.approxMegabytes),
                    style = MaterialTheme.typography.bodySmall
                )
                if (state is ModelDownloadState.Failed) {
                    Text(
                        text = stringResource(R.string.model_failed, state.message),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
                Button(onClick = { ModelDownloadHub.start(context, spec) }) {
                    Text(
                        stringResource(
                            if (state is ModelDownloadState.Failed) R.string.model_resume else R.string.model_download
                        )
                    )
                }
            }
        }
    }
}
EOF

# ---------- F. Connect the new parts to the existing screens (additive, idempotent) ----------

# F1. The test card talks to the recognition gateway instead of the Google bridge directly.
if ! grep -q "RecognitionGateway" "$CONTROLLER_FILE"; then
  grep -q 'private val bridge = GoogleRecognizerBridge(appContext, scope)' "$CONTROLLER_FILE" \
    || { echo "ERROR: MicLabController anchor not found" >&2; exit 1; }
  sed -i 's|private val bridge = GoogleRecognizerBridge(appContext, scope)|private val bridge = RecognitionGateway(appContext, scope)|' "$CONTROLLER_FILE"
fi
grep -q "private val bridge = RecognitionGateway(appContext, scope)" "$CONTROLLER_FILE" \
  || { echo "ERROR: MicLabController edit failed" >&2; exit 1; }

# F2. The Whisper switch and model choice appear in the recognition part of the test card.
if ! grep -q "WhisperEngineSection()" "$CARD_FILE"; then
  grep -q 'onSelected = { controller.selectRecognitionService(it) }' "$CARD_FILE" \
    || { echo "ERROR: MicLabCard anchor not found" >&2; exit 1; }
  cat > "$TMP_DIR/card_add.txt" <<'EOF'

    WhisperEngineSection()
EOF
  sed -i -e "/onSelected = { controller.selectRecognitionService(it) }/{n;r $TMP_DIR/card_add.txt" -e "}" "$CARD_FILE"
fi
grep -q "^    WhisperEngineSection()$" "$CARD_FILE" || { echo "ERROR: MicLabCard edit failed" >&2; exit 1; }

# F3. The model manager card appears in the AI Brain tab, right after the test card.
if ! grep -q "ModelManagerCard()" "$BRAIN_FILE"; then
  grep -q '^import com.nova.ai.ui.components.MicLabCard$' "$BRAIN_FILE" \
    || { echo "ERROR: AiBrainScreen anchor (import) not found" >&2; exit 1; }
  grep -q '^        MicLabCard()$' "$BRAIN_FILE" \
    || { echo "ERROR: AiBrainScreen anchor (card) not found" >&2; exit 1; }
  cat > "$TMP_DIR/brain_import.txt" <<'EOF'
import com.nova.ai.ui.components.ModelManagerCard
EOF
  cat > "$TMP_DIR/brain_card.txt" <<'EOF'

        ModelManagerCard()
EOF
  sed -i "/^import com.nova.ai.ui.components.MicLabCard$/r $TMP_DIR/brain_import.txt" "$BRAIN_FILE"
  sed -i "/^        MicLabCard()$/r $TMP_DIR/brain_card.txt" "$BRAIN_FILE"
fi
grep -q "^import com.nova.ai.ui.components.ModelManagerCard$" "$BRAIN_FILE" || { echo "ERROR: AiBrainScreen edit failed (import)" >&2; exit 1; }
grep -q "^        ModelManagerCard()$" "$BRAIN_FILE" || { echo "ERROR: AiBrainScreen edit failed (card)" >&2; exit 1; }

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "E3: offline Whisper speech recognition (sherpa-onnx) and model manager"
git push

echo "E3 files created and pushed."
