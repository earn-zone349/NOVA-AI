#!/usr/bin/env bash
# NOVA AI - Phase 5 setup script: Room database, local logger, crash handler.
# Additive: build files only get new lines; NovaApp and PrivacySecurityScreen are
# rewritten with every previous element kept, plus the new parts.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"

if [ ! -f "$BASE/settings/SettingsRepository.kt" ]; then
  echo "ERROR: Run from repo root after P1 to P4 are installed." >&2
  exit 1
fi

mkdir -p "$BASE/data/entity" "$BASE/data/dao" "$BASE/data/db" "$BASE/logging"

# ---------- A. Build configuration (additive, safe to re-run) ----------
TMP_DIR="$(mktemp -d)"

if ! grep -q "^room = " gradle/libs.versions.toml; then
  echo 'room = "2.6.1"' > "$TMP_DIR/ver_room.txt"
  sed -i "/^kotlin = /r $TMP_DIR/ver_room.txt" gradle/libs.versions.toml
fi
if ! grep -q "^ksp = " gradle/libs.versions.toml; then
  echo 'ksp = "1.9.24-1.0.20"' > "$TMP_DIR/ver_ksp.txt"
  sed -i "/^kotlin = /r $TMP_DIR/ver_ksp.txt" gradle/libs.versions.toml
fi
if ! grep -q "^androidx-room-runtime = " gradle/libs.versions.toml; then
  cat > "$TMP_DIR/libs_room.txt" <<'EOF'
androidx-room-runtime = { group = "androidx.room", name = "room-runtime", version.ref = "room" }
androidx-room-ktx = { group = "androidx.room", name = "room-ktx", version.ref = "room" }
androidx-room-compiler = { group = "androidx.room", name = "room-compiler", version.ref = "room" }
EOF
  sed -i "/^androidx-compose-material3 = /r $TMP_DIR/libs_room.txt" gradle/libs.versions.toml
fi
if ! grep -q '^ksp = { id' gradle/libs.versions.toml; then
  echo 'ksp = { id = "com.google.devtools.ksp", version.ref = "ksp" }' > "$TMP_DIR/plugin_ksp.txt"
  sed -i "/^kotlin-android = /r $TMP_DIR/plugin_ksp.txt" gradle/libs.versions.toml
fi

if ! grep -q "libs.plugins.ksp" build.gradle.kts; then
  sed -i '/alias(libs.plugins.kotlin.android) apply false/a\    alias(libs.plugins.ksp) apply false' build.gradle.kts
fi
if ! grep -q "libs.plugins.ksp" app/build.gradle.kts; then
  sed -i '/^    alias(libs.plugins.kotlin.android)$/a\    alias(libs.plugins.ksp)' app/build.gradle.kts
fi
if ! grep -q "androidx.room.compiler" app/build.gradle.kts; then
  cat > "$TMP_DIR/deps_room.txt" <<'EOF'
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)
EOF
  sed -i "/implementation(libs.androidx.navigation.compose)/r $TMP_DIR/deps_room.txt" app/build.gradle.kts
fi

# Verify the build edits landed before continuing.
grep -q '^ksp = { id' gradle/libs.versions.toml || { echo "ERROR: toml edit failed" >&2; exit 1; }
grep -q "androidx.room.compiler" app/build.gradle.kts || { echo "ERROR: app gradle edit failed" >&2; exit 1; }
grep -q "libs.plugins.ksp" app/build.gradle.kts || { echo "ERROR: app plugin edit failed" >&2; exit 1; }
grep -q "libs.plugins.ksp" build.gradle.kts || { echo "ERROR: root plugin edit failed" >&2; exit 1; }

# ---------- B. New strings file ----------
cat > app/src/main/res/values/strings_p5.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="privacy_logs_title">অ্যাপ লগ</string>
    <string name="privacy_logs_count">মোট লগ: %1$d</string>
    <string name="privacy_logs_empty">কোনো লগ নেই।</string>
    <string name="privacy_logs_refresh">রিফ্রেশ</string>
    <string name="privacy_test_crash_title">ক্র্যাশ পরীক্ষা (শুধু ডিবাগ বিল্ডে)</string>
    <string name="privacy_test_crash_note">বাটন চাপলে অ্যাপ ইচ্ছাকৃতভাবে বন্ধ হবে। আবার খুলে Privacy ট্যাবে রিফ্রেশ দিলে FATAL লগ দেখা যাবে।</string>
    <string name="privacy_test_crash_button">টেস্ট ক্র্যাশ</string>
</resources>
EOF

# ---------- 1. LogEntity.kt ----------
cat > "$BASE/data/entity/LogEntity.kt" <<'EOF'
package com.nova.ai.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/** One saved log line (app event or error), stored only on this device. */
@Entity(tableName = "logs", indices = [Index(value = ["timestampMs"])])
data class LogEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0L,
    val timestampMs: Long,
    val level: String,
    val tag: String,
    val message: String,
    val stackTrace: String? = null
)
EOF

# ---------- 2. TaskEntity.kt ----------
cat > "$BASE/data/entity/TaskEntity.kt" <<'EOF'
package com.nova.ai.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/** History record of one task. [status] holds a TaskStatus name. */
@Entity(tableName = "tasks", indices = [Index(value = ["updatedAtMs"])])
data class TaskEntity(
    @PrimaryKey val id: String,
    val title: String,
    val status: String,
    val stepCount: Int,
    val createdAtMs: Long,
    val updatedAtMs: Long,
    val detail: String? = null
)
EOF

# ---------- 3. MemoryEntity.kt ----------
cat > "$BASE/data/entity/MemoryEntity.kt" <<'EOF'
package com.nova.ai.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/** One saved personal fact or preference. Column names avoid SQL keywords. */
@Entity(tableName = "memory_items")
data class MemoryEntity(
    @PrimaryKey
    @ColumnInfo(name = "item_key") val key: String,
    @ColumnInfo(name = "item_value") val value: String,
    @ColumnInfo(name = "updated_at_ms") val updatedAtMs: Long
)
EOF

# ---------- 4. LogDao.kt ----------
cat > "$BASE/data/dao/LogDao.kt" <<'EOF'
package com.nova.ai.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import com.nova.ai.data.entity.LogEntity

/**
 * Database access for logs. Methods are blocking, so always call them
 * from a background thread (NovaLogger does this for you).
 */
@Dao
interface LogDao {

    @Insert
    fun insert(entry: LogEntity): Long

    @Query("SELECT * FROM logs ORDER BY timestampMs DESC, id DESC LIMIT :limit")
    fun getRecent(limit: Int): List<LogEntity>

    @Query("SELECT COUNT(*) FROM logs")
    fun count(): Int

    @Query("DELETE FROM logs WHERE timestampMs < :cutoffMs")
    fun deleteOlderThan(cutoffMs: Long): Int

    @Query("DELETE FROM logs")
    fun clearAll(): Int
}
EOF

# ---------- 5. TaskDao.kt ----------
cat > "$BASE/data/dao/TaskDao.kt" <<'EOF'
package com.nova.ai.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.nova.ai.data.entity.TaskEntity

/** Database access for task history. Blocking: call from a background thread. */
@Dao
interface TaskDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    fun upsert(task: TaskEntity)

    @Query("SELECT * FROM tasks ORDER BY updatedAtMs DESC LIMIT :limit")
    fun getRecent(limit: Int): List<TaskEntity>

    @Query("SELECT * FROM tasks WHERE id = :taskId LIMIT 1")
    fun getById(taskId: String): TaskEntity?

    @Query("UPDATE tasks SET status = :status, updatedAtMs = :updatedAtMs WHERE id = :taskId")
    fun updateStatus(taskId: String, status: String, updatedAtMs: Long): Int

    @Query("DELETE FROM tasks")
    fun clearAll(): Int
}
EOF

# ---------- 6. MemoryDao.kt ----------
cat > "$BASE/data/dao/MemoryDao.kt" <<'EOF'
package com.nova.ai.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.nova.ai.data.entity.MemoryEntity

/** Database access for personal memory. Blocking: call from a background thread. */
@Dao
interface MemoryDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    fun upsert(item: MemoryEntity)

    @Query("SELECT * FROM memory_items WHERE item_key = :key LIMIT 1")
    fun get(key: String): MemoryEntity?

    @Query("SELECT * FROM memory_items ORDER BY updated_at_ms DESC")
    fun getAll(): List<MemoryEntity>

    @Query("DELETE FROM memory_items WHERE item_key = :key")
    fun delete(key: String): Int

    @Query("DELETE FROM memory_items")
    fun clearAll(): Int
}
EOF

# ---------- 7. NovaDatabase.kt ----------
cat > "$BASE/data/db/NovaDatabase.kt" <<'EOF'
package com.nova.ai.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.nova.ai.data.dao.LogDao
import com.nova.ai.data.dao.MemoryDao
import com.nova.ai.data.dao.TaskDao
import com.nova.ai.data.entity.LogEntity
import com.nova.ai.data.entity.MemoryEntity
import com.nova.ai.data.entity.TaskEntity

/**
 * Local on-device database (logs, task history, personal memory).
 * Nothing here leaves the phone.
 */
@Database(
    entities = [LogEntity::class, TaskEntity::class, MemoryEntity::class],
    version = 1,
    exportSchema = false
)
abstract class NovaDatabase : RoomDatabase() {

    abstract fun logDao(): LogDao
    abstract fun taskDao(): TaskDao
    abstract fun memoryDao(): MemoryDao

    companion object {
        private const val DB_NAME: String = "nova_ai.db"

        @Volatile
        private var instance: NovaDatabase? = null

        /** Returns the single shared database instance, creating it if needed. */
        fun getInstance(context: Context): NovaDatabase {
            return instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    NovaDatabase::class.java,
                    DB_NAME
                ).build().also { instance = it }
            }
        }
    }
}
EOF

# ---------- 8. NovaLogger.kt ----------
cat > "$BASE/logging/NovaLogger.kt" <<'EOF'
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
EOF

# ---------- 9. GlobalCrashHandler.kt ----------
cat > "$BASE/logging/GlobalCrashHandler.kt" <<'EOF'
package com.nova.ai.logging

import android.os.Process
import android.util.Log
import kotlin.system.exitProcess

/**
 * Saves every uncaught crash to the local log before the app closes,
 * then hands over to the previous system handler so Android behaves normally.
 */
class GlobalCrashHandler private constructor(
    private val previous: Thread.UncaughtExceptionHandler?
) : Thread.UncaughtExceptionHandler {

    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        try {
            NovaLogger.logBlocking(
                level = LogLevel.FATAL,
                tag = TAG,
                message = "Uncaught exception on thread ${thread.name}",
                throwable = throwable
            )
        } catch (e: Throwable) {
            Log.e(TAG, "Crash logging failed", e)
        } finally {
            if (previous != null) {
                previous.uncaughtException(thread, throwable)
            } else {
                Process.killProcess(Process.myPid())
                exitProcess(CRASH_EXIT_CODE)
            }
        }
    }

    companion object {
        private const val TAG: String = "CrashHandler"
        private const val CRASH_EXIT_CODE: Int = 10

        @Volatile
        private var installed: Boolean = false

        /** Installs the handler once. Safe to call more than once. */
        fun install() {
            synchronized(this) {
                if (installed) return
                Thread.setDefaultUncaughtExceptionHandler(
                    GlobalCrashHandler(Thread.getDefaultUncaughtExceptionHandler())
                )
                installed = true
            }
        }
    }
}
EOF

# ---------- C. NovaApp.kt (previous behavior kept; logger and crash handler added) ----------
cat > "$BASE/NovaApp.kt" <<'EOF'
package com.nova.ai

import android.app.Application
import android.util.Log
import com.nova.ai.logging.GlobalCrashHandler
import com.nova.ai.logging.NovaLogger

/**
 * Application entry point. Global, app-wide initialization lives here:
 * the local logger and the crash handler start before anything else.
 */
class NovaApp : Application() {

    override fun onCreate() {
        super.onCreate()
        try {
            NovaLogger.init(this)
            GlobalCrashHandler.install()
            NovaLogger.i(TAG, "NOVA AI started")
        } catch (e: Exception) {
            // Initialization must never crash the app at startup.
            Log.e(TAG, "Application init failed", e)
        }
    }

    companion object {
        private const val TAG: String = "NovaApp"
    }
}
EOF

# ---------- D. PrivacySecurityScreen.kt (3 original cards kept + log card) ----------
cat > "$BASE/ui/screens/PrivacySecurityScreen.kt" <<'EOF'
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
EOF

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "P5: Room database, local logger, crash handler"
git push

echo "P5 files created and pushed."
