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
