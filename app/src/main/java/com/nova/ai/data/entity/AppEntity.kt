package com.nova.ai.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/** One app the user allowed NOVA to control. [aliases] holds nicknames, one per line. */
@Entity(tableName = "nova_apps")
data class AppEntity(
    @PrimaryKey
    @ColumnInfo(name = "package_name") val packageName: String,
    @ColumnInfo(name = "label") val label: String,
    @ColumnInfo(name = "aliases") val aliases: String,
    @ColumnInfo(name = "added_at_ms") val addedAtMs: Long
)
