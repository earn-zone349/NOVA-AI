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
