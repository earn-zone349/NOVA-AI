package com.nova.ai.tasks

import android.content.Context
import com.nova.ai.data.dao.TaskDao
import com.nova.ai.data.db.NovaDatabase
import com.nova.ai.data.entity.TaskEntity
import com.nova.ai.logging.NovaLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Keeps the task history in the phone's database (the existing "tasks" table). Every call runs on a
 * background thread and never throws: a database problem is logged and the call gives an empty or
 * false result, so a task is never stopped because the history could not be saved.
 */
class TaskHistoryRepository(context: Context) {

    private val dao: TaskDao = NovaDatabase.getInstance(context.applicationContext).taskDao()

    /** Saves [item] and keeps only the newest [HISTORY_LIMIT] records. */
    suspend fun save(item: HistoryItem): Boolean = withContext(Dispatchers.IO) {
        try {
            val row: HistoryRow = HistoryRow.from(item)
            dao.upsert(
                TaskEntity(row.id, row.title, row.status, row.stepCount, row.createdAtMs, row.updatedAtMs, row.detail)
            )
            dao.trimTo(HISTORY_LIMIT)
            true
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not save the task history", e)
            false
        }
    }

    /** The newest records, newest first. */
    suspend fun recent(limit: Int = HISTORY_LIMIT): List<HistoryItem> = withContext(Dispatchers.IO) {
        try {
            dao.getRecent(limit).mapNotNull { e ->
                HistoryRow(e.id, e.title, e.status, e.stepCount, e.createdAtMs, e.updatedAtMs, e.detail).toItem()
            }
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not read the task history", e)
            emptyList()
        }
    }

    /** Deletes the whole history. */
    suspend fun clear(): Boolean = withContext(Dispatchers.IO) {
        try {
            dao.clearAll()
            true
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not clear the task history", e)
            false
        }
    }

    companion object {
        private const val TAG: String = "TaskHistory"

        /** How many finished tasks are kept. */
        const val HISTORY_LIMIT: Int = 50
    }
}
