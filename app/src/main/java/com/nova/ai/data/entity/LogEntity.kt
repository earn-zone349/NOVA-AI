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
