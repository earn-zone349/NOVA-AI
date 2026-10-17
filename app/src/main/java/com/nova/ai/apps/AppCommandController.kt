package com.nova.ai.apps

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.nlp.IntentEntity
import com.nova.ai.voice.LanguageDetector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** What the Home screen shows about the last "open app" command. */
sealed class AppActionUi {
    object Idle : AppActionUi()
    data class Opened(val appLabel: String) : AppActionUi()
    data class Confirm(val spoken: String, val app: RegisteredApp) : AppActionUi()
    data class Choose(val spoken: String, val apps: List<RegisteredApp>) : AppActionUi()
    data class Suggest(val spoken: String, val apps: List<InstalledApp>) : AppActionUi()
    data class NotFound(val spoken: String) : AppActionUi()
    data class Failed(val message: String) : AppActionUi()
}

/**
 * Turns an "open app" command into a real app launch.
 * Only apps in the user's library are opened directly. Unsure names are
 * confirmed with the user, and the confirmed name is saved as a nickname.
 * Use from the main thread.
 */
class AppCommandController(
    context: Context,
    private val scope: CoroutineScope
) {

    private val registry = AppRegistry(context)
    private val scanner = InstalledAppScanner(context)
    private val launcher = AppLauncher(context)
    private val brain = RuleBasedBrain()

    var state: AppActionUi by mutableStateOf<AppActionUi>(AppActionUi.Idle)
        private set

    /** Looks at [text]; if it asks to open an app, finds and opens it. */
    fun handleCommand(text: String) {
        val spoken: String? = extractAppName(text)
        if (spoken == null) {
            state = AppActionUi.Idle
            return
        }
        resolveAndAct(spoken)
    }

    /** The user said "yes" to the suggested app. */
    fun confirm() {
        val current: AppActionUi.Confirm = state as? AppActionUi.Confirm ?: return
        learnAndOpen(current.spoken, current.app)
    }

    /** The user picked one app from a list. */
    fun choose(app: RegisteredApp) {
        val spoken: String = when (val current: AppActionUi = state) {
            is AppActionUi.Choose -> current.spoken
            is AppActionUi.Confirm -> current.spoken
            else -> return
        }
        learnAndOpen(spoken, app)
    }

    /** The user picked an installed app that was not in the library yet. */
    fun addAndOpen(app: InstalledApp) {
        val current: AppActionUi.Suggest = state as? AppActionUi.Suggest ?: return
        scope.launch {
            val added: NovaResult<Unit> = registry.add(app, listOf(current.spoken))
            if (added is NovaResult.Failure) {
                state = AppActionUi.Failed(added.error.message)
                return@launch
            }
            open(app.packageName, app.label)
        }
    }

    /** Hides the card. */
    fun dismiss() {
        state = AppActionUi.Idle
    }

    private fun extractAppName(text: String): String? {
        if (text.isBlank()) return null
        val command = VoiceCommand(
            rawText = text,
            language = LanguageDetector.detect(text),
            timestampMs = System.currentTimeMillis()
        )
        val intent: NovaIntent = (brain.analyze(command, emptyList()) as? NovaResult.Success)
            ?.value
            ?: return null
        if (intent.type != IntentType.OPEN_APP) return null
        return intent.entities[IntentEntity.APP]
    }

    private fun resolveAndAct(spoken: String) {
        scope.launch {
            val registeredApps: List<RegisteredApp> = when (val result = registry.getAll()) {
                is NovaResult.Success -> result.value
                is NovaResult.Failure -> {
                    state = AppActionUi.Failed(result.error.message)
                    return@launch
                }
            }
            val installedApps: List<InstalledApp> = when (val result = scanner.scan()) {
                is NovaResult.Success -> result.value
                is NovaResult.Failure -> {
                    state = AppActionUi.Failed(result.error.message)
                    return@launch
                }
            }

            // Only apps that are still on the phone can be opened.
            val installedPackages: Set<String> = installedApps.map { it.packageName }.toSet()
            val usable: List<RegisteredApp> =
                registeredApps.filter { it.packageName in installedPackages }

            when (val outcome: MatchOutcome = AppNameMatcher.match(spoken, usable)) {
                is MatchOutcome.Single -> open(outcome.app.packageName, outcome.app.label)
                is MatchOutcome.Confirm -> state = AppActionUi.Confirm(spoken, outcome.app)
                is MatchOutcome.Ambiguous -> state = AppActionUi.Choose(spoken, outcome.apps)
                is MatchOutcome.None -> suggestFromInstalled(spoken, installedApps, registeredApps)
            }
        }
    }

    /** Not in the library: look for it among the other apps on the phone. */
    private fun suggestFromInstalled(
        spoken: String,
        installedApps: List<InstalledApp>,
        registeredApps: List<RegisteredApp>
    ) {
        val registeredPackages: Set<String> = registeredApps.map { it.packageName }.toSet()
        val candidates: List<RegisteredApp> = installedApps
            .filter { it.packageName !in registeredPackages }
            .map { RegisteredApp(it.packageName, it.label) }

        val ranked: List<AppMatch> = AppNameMatcher.rank(spoken, candidates).take(MAX_SUGGESTIONS)
        state = if (ranked.isEmpty()) {
            AppActionUi.NotFound(spoken)
        } else {
            AppActionUi.Suggest(
                spoken,
                ranked.map { InstalledApp(it.app.packageName, it.app.label) }
            )
        }
    }

    private fun learnAndOpen(spoken: String, app: RegisteredApp) {
        scope.launch {
            val learned: NovaResult<Unit> = registry.addAlias(app.packageName, spoken)
            if (learned is NovaResult.Failure) {
                NovaLogger.w(TAG, "Could not save nickname: ${learned.error.message}")
            }
            open(app.packageName, app.label)
        }
    }

    private fun open(packageName: String, label: String) {
        state = when (val result: NovaResult<Unit> = launcher.launch(packageName)) {
            is NovaResult.Success -> AppActionUi.Opened(label)
            is NovaResult.Failure -> AppActionUi.Failed(result.error.message)
        }
    }

    private companion object {
        const val TAG: String = "AppCommandController"
        const val MAX_SUGGESTIONS: Int = 3
    }
}
