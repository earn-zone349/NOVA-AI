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
