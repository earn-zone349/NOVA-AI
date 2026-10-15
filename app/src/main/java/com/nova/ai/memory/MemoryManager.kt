package com.nova.ai.memory

import com.nova.ai.core.MemoryItem
import com.nova.ai.core.NovaResult

/** User-controlled personal memory: view, edit, delete, and turn off. */
interface MemoryManager {
    /** Whether memory is currently switched on. */
    fun isEnabled(): Boolean

    /** Switches memory on or off. */
    fun setEnabled(enabled: Boolean)

    /** Saves or updates a memory entry. */
    fun save(key: String, value: String): NovaResult<Unit>

    /** Reads one entry, or null if it does not exist. */
    fun get(key: String): NovaResult<MemoryItem?>

    /** Lists every saved entry. */
    fun listAll(): NovaResult<List<MemoryItem>>

    /** Deletes one entry. */
    fun delete(key: String): NovaResult<Unit>

    /** Deletes everything. */
    fun clearAll(): NovaResult<Unit>
}
