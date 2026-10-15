package com.nova.ai.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/** History record of one task. [status] holds a TaskStatus name. */
@Entity(tableName = "tasks", indices = [Index(value = ["updatedAtMs"])])
data class TaskEntity(
    @PrimaryKey val id: String,
    val title: String,
    val status: String,
    val stepCount: Int,
    val createdAtMs: Long,
    val updatedAtMs: Long,
    val detail: String? = null
)
