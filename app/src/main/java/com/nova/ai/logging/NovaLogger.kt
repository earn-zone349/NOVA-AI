package com.nova.ai.logging

import android.content.Context
import android.util.Log
import com.nova.ai.data.dao.LogDao
import com.nova.ai.data.db.NovaDatabase
import com.nova.ai.data.entity.LogEntity
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Severity of a log line. */
enum class LogLevel { DEBUG, INFO, WARN, ERROR, FATAL }

/**
 * App-wide logger. Writes to Android logcat and to the local database.
 * It never throws: a logging problem must not crash the app.
 */
object NovaLogger {

    private const val TAG: String = "NovaLogger"
    private const val RETENTION_DAYS: Long = 14L
    private const val MAX_MESSAGE_LENGTH: Int = 1000
    private const val MAX_STACK_LENGTH: Int = 4000
    private const val BLOCKING_TIMEOUT_MS: Long = 2000L

    // Single background thread keeps database writes ordered and off the UI thread.
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "nova-logger").apply { isDaemon = true }
    }

    @Volatile
    private var logDao: LogDao? = null

    /** Connects the logger to the database and removes old entries. Call once at startup. */
    fun init(context: Context) {
        try {
            logDao = NovaDatabase.getInstance(context).logDao()
            executor.execute {
                try {
                    val cutoff: Long = System.currentTimeMillis() -
                        TimeUnit.DAYS.toMillis(RETENTION_DAYS)
                    logDao?.deleteOlderThan(cutoff)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to prune old logs", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Logger init failed", e)
        }
    }

    fun d(tag: String, message: String) = log(LogLevel.DEBUG, tag, message)
    fun i(tag: String, message: String) = log(LogLevel.INFO, tag, message)
    fun w(tag: String, message: String, throwable: Throwable? = null) =
        log(LogLevel.WARN, tag, message, throwable)
    fun e(tag: String, message: String, throwable: Throwable? = null) =
        log(LogLevel.ERROR, tag, message, throwable)

    /** Logs a line without waiting for the database write. */
    fun log(level: LogLevel, tag: String, message: String, throwable: Throwable? = null) {
        writeToLogcat(level, tag, message, throwable)
        val entry: LogEntity = buildEntry(level, tag, message, throwable)
        try {
            executor.execute { insertSafely(entry) }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to queue log entry", e)
        }
    }

    /**
     * Logs a line and waits (up to 2 seconds) until it is saved.
     * Used by the crash handler, because the process may die right after.
     */
    fun logBlocking(level: LogLevel, tag: String, message: String, throwable: Throwable? = null) {
        writeToLogcat(level, tag, message, throwable)
        val entry: LogEntity = buildEntry(level, tag, message, throwable)
        try {
            executor.submit { insertSafely(entry) }.get(BLOCKING_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        } catch (e: Exception) {
            Log.e(TAG, "Blocking log write failed", e)
        }
    }

    /** Returns the newest [limit] entries. Blocking: call from a background thread. */
    fun getRecent(limit: Int): List<LogEntity> = try {
        logDao?.getRecent(limit) ?: emptyList()
    } catch (e: Exception) {
        Log.e(TAG, "Failed to read logs", e)
        emptyList()
    }

    /** Returns the number of saved entries. Blocking: call from a background thread. */
    fun count(): Int = try {
        logDao?.count() ?: 0
    } catch (e: Exception) {
        Log.e(TAG, "Failed to count logs", e)
        0
    }

    /** Deletes every saved entry. Blocking: call from a background thread. */
    fun clear() {
        try {
            logDao?.clearAll()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear logs", e)
        }
    }

    private fun buildEntry(
        level: LogLevel,
        tag: String,
        message: String,
        throwable: Throwable?
    ): LogEntity = LogEntity(
        timestampMs = System.currentTimeMillis(),
        level = level.name,
        tag = tag,
        message = message.take(MAX_MESSAGE_LENGTH),
        stackTrace = throwable?.let { Log.getStackTraceString(it).take(MAX_STACK_LENGTH) }
    )

    private fun insertSafely(entry: LogEntity) {
        try {
            logDao?.insert(entry)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save log entry", e)
        }
    }

    private fun writeToLogcat(level: LogLevel, tag: String, message: String, throwable: Throwable?) {
        when (level) {
            LogLevel.DEBUG -> Log.d(tag, message, throwable)
            LogLevel.INFO -> Log.i(tag, message, throwable)
            LogLevel.WARN -> Log.w(tag, message, throwable)
            LogLevel.ERROR, LogLevel.FATAL -> Log.e(tag, message, throwable)
        }
    }
}
