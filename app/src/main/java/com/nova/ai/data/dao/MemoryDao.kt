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
