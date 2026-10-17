package com.nova.ai.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.nova.ai.data.entity.AppEntity

/** Database access for the app library. Blocking: call from a background thread. */
@Dao
interface AppDao {

    /** Adds the app unless it already exists. Returns -1 when it already existed. */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    fun insertIfAbsent(app: AppEntity): Long

    @Query("SELECT * FROM nova_apps ORDER BY label COLLATE NOCASE ASC")
    fun getAll(): List<AppEntity>

    @Query("SELECT * FROM nova_apps WHERE package_name = :packageName LIMIT 1")
    fun get(packageName: String): AppEntity?

    @Query("UPDATE nova_apps SET aliases = :aliases WHERE package_name = :packageName")
    fun updateAliases(packageName: String, aliases: String): Int

    @Query("DELETE FROM nova_apps WHERE package_name = :packageName")
    fun delete(packageName: String): Int

    @Query("SELECT COUNT(*) FROM nova_apps")
    fun count(): Int
}
