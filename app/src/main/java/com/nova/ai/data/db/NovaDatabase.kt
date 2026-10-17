package com.nova.ai.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.nova.ai.data.dao.AppDao
import com.nova.ai.data.dao.LogDao
import com.nova.ai.data.dao.MemoryDao
import com.nova.ai.data.dao.TaskDao
import com.nova.ai.data.entity.AppEntity
import com.nova.ai.data.entity.LogEntity
import com.nova.ai.data.entity.MemoryEntity
import com.nova.ai.data.entity.TaskEntity

/**
 * Local on-device database (logs, task history, personal memory, app library).
 * Nothing here leaves the phone.
 *
 * Version 2 adds the app library table. The migration keeps all existing data.
 */
@Database(
    entities = [
        LogEntity::class,
        TaskEntity::class,
        MemoryEntity::class,
        AppEntity::class
    ],
    version = 2,
    exportSchema = false
)
abstract class NovaDatabase : RoomDatabase() {

    abstract fun logDao(): LogDao
    abstract fun taskDao(): TaskDao
    abstract fun memoryDao(): MemoryDao
    abstract fun appDao(): AppDao

    companion object {
        private const val DB_NAME: String = "nova_ai.db"

        /** Version 1 to 2: create the app library table. */
        private val MIGRATION_1_2: Migration = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `nova_apps` (" +
                        "`package_name` TEXT NOT NULL, " +
                        "`label` TEXT NOT NULL, " +
                        "`aliases` TEXT NOT NULL, " +
                        "`added_at_ms` INTEGER NOT NULL, " +
                        "PRIMARY KEY(`package_name`))"
                )
            }
        }

        @Volatile
        private var instance: NovaDatabase? = null

        /** Returns the single shared database instance, creating it if needed. */
        fun getInstance(context: Context): NovaDatabase {
            return instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    NovaDatabase::class.java,
                    DB_NAME
                ).addMigrations(MIGRATION_1_2).build().also { instance = it }
            }
        }
    }
}
