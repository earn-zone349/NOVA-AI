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
