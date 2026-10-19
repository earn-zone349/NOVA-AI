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
