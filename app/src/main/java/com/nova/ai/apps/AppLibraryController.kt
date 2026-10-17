package com.nova.ai.apps

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.core.NovaResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Screen-side holder for the app library. Screens read [registered], [installed],
 * [isLoading] and [errorMessage]; the functions below change the library and reload.
 */
class AppLibraryController(
    context: Context,
    private val scope: CoroutineScope
) {

    private val registry = AppRegistry(context)
    private val scanner = InstalledAppScanner(context)

    var registered: List<RegisteredApp> by mutableStateOf<List<RegisteredApp>>(emptyList())
        private set

    var installed: List<InstalledApp> by mutableStateOf<List<InstalledApp>>(emptyList())
        private set

    var isLoading: Boolean by mutableStateOf(false)
        private set

    var errorMessage: String? by mutableStateOf<String?>(null)
        private set

    /** Reloads the library and the phone's app list. */
    fun refresh() {
        scope.launch {
            isLoading = true
            errorMessage = null
            load()
            isLoading = false
        }
    }

    /** Adds the chosen apps to the library. */
    fun addApps(apps: List<InstalledApp>) {
        if (apps.isEmpty()) return
        scope.launch {
            report(registry.addAll(apps))
            load()
        }
    }

    /** Removes an app from the library. */
    fun removeApp(packageName: String) {
        scope.launch {
            report(registry.remove(packageName))
            load()
        }
    }

    /** Saves the nicknames typed by the user. */
    fun saveAliases(packageName: String, rawAliases: List<String>) {
        scope.launch {
            report(registry.setAliases(packageName, rawAliases))
            load()
        }
    }

    private suspend fun load() {
        when (val result: NovaResult<List<RegisteredApp>> = registry.getAll()) {
            is NovaResult.Success -> registered = result.value
            is NovaResult.Failure -> errorMessage = result.error.message
        }
        when (val result: NovaResult<List<InstalledApp>> = scanner.scan()) {
            is NovaResult.Success -> installed = result.value
            is NovaResult.Failure -> errorMessage = result.error.message
        }
    }

    private fun report(result: NovaResult<*>) {
        if (result is NovaResult.Failure) errorMessage = result.error.message
    }
}
