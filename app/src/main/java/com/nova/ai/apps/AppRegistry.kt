package com.nova.ai.apps

import android.content.Context
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.data.dao.AppDao
import com.nova.ai.data.db.NovaDatabase
import com.nova.ai.data.entity.AppEntity
import com.nova.ai.logging.NovaLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The user's app library: which apps NOVA may control, and their nicknames.
 * Saved only on this phone. Every call runs on a background thread and
 * reports problems as a failure result instead of crashing.
 */
class AppRegistry(context: Context) {

    private val dao: AppDao = NovaDatabase.getInstance(context).appDao()

    /** Every app in the library, sorted by name. */
    suspend fun getAll(): NovaResult<List<RegisteredApp>> = io("read apps") {
        dao.getAll().map { entity ->
            RegisteredApp(entity.packageName, entity.label, AliasCodec.decode(entity.aliases))
        }
    }

    /** Adds one app (and optional nicknames). An app already in the library stays as it is. */
    suspend fun add(app: InstalledApp, aliases: List<String> = emptyList()): NovaResult<Unit> =
        io("add app") {
            dao.insertIfAbsent(
                AppEntity(app.packageName, app.label, "", System.currentTimeMillis())
            )
            if (aliases.isNotEmpty()) mergeAliases(app.packageName, aliases)
            Unit
        }

    /** Adds many apps at once. Returns how many were new. */
    suspend fun addAll(apps: List<InstalledApp>): NovaResult<Int> = io("add apps") {
        val now: Long = System.currentTimeMillis()
        var added = 0
        for (app in apps) {
            val rowId: Long = dao.insertIfAbsent(AppEntity(app.packageName, app.label, "", now))
            if (rowId != INSERT_IGNORED) added += 1
        }
        added
    }

    /** Removes an app from the library. */
    suspend fun remove(packageName: String): NovaResult<Unit> = io("remove app") {
        dao.delete(packageName)
        Unit
    }

    /** Replaces all nicknames of an app. */
    suspend fun setAliases(packageName: String, aliases: List<String>): NovaResult<Unit> =
        io("save nicknames") {
            val entity: AppEntity? = dao.get(packageName)
            if (entity != null) {
                val clean: List<String> = AliasCodec.sanitize(aliases, entity.label)
                dao.updateAliases(packageName, AliasCodec.encode(clean))
            }
            Unit
        }

    /** Adds one nickname to an app, keeping the existing ones. */
    suspend fun addAlias(packageName: String, alias: String): NovaResult<Unit> =
        io("add nickname") {
            mergeAliases(packageName, listOf(alias))
            Unit
        }

    private fun mergeAliases(packageName: String, newAliases: List<String>) {
        val entity: AppEntity = dao.get(packageName) ?: return
        val merged: List<String> = AliasCodec.sanitize(
            AliasCodec.decode(entity.aliases) + newAliases,
            entity.label
        )
        dao.updateAliases(packageName, AliasCodec.encode(merged))
    }

    private suspend fun <T> io(action: String, block: () -> T): NovaResult<T> =
        withContext(Dispatchers.IO) {
            try {
                NovaResult.Success(block())
            } catch (e: Exception) {
                NovaLogger.e(TAG, "Failed to $action", e)
                NovaResult.failure(ErrorCode.EXECUTION_FAILED, "অ্যাপ তালিকা সংরক্ষণে সমস্যা হয়েছে।", e)
            }
        }

    private companion object {
        const val TAG: String = "AppRegistry"
        const val INSERT_IGNORED: Long = -1L
    }
}
