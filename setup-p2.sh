#!/usr/bin/env bash
# NOVA AI - Phase 2 setup script: 12-module architecture skeleton.
# Additive only: creates new files, never modifies existing ones.
set -euo pipefail

# Safety check: Phase 1 must already exist.
if [ ! -f settings.gradle.kts ]; then
  echo "ERROR: Run this from the repo root (P1 files not found)." >&2
  exit 1
fi

BASE="app/src/main/java/com/nova/ai"
for pkg in core voice brain planner controller accessibility vision memory security verification automation models; do
  mkdir -p "$BASE/$pkg"
done

# ---------- 1. core/NovaResult.kt ----------
cat > "$BASE/core/NovaResult.kt" <<'EOF'
package com.nova.ai.core

/** Machine-readable error categories used across all modules. */
enum class ErrorCode {
    UNKNOWN,
    PERMISSION_DENIED,
    NOT_AVAILABLE,
    NOT_FOUND,
    INVALID_INPUT,
    TIMEOUT,
    CANCELLED,
    SECURITY_BLOCKED,
    EXECUTION_FAILED
}

/** Structured error carried by [NovaResult.Failure]. */
data class NovaError(
    val code: ErrorCode,
    val message: String,
    val cause: Throwable? = null
)

/**
 * Uniform result type for every module call.
 * Modules return this instead of throwing, so callers always handle failure explicitly.
 */
sealed class NovaResult<out T> {

    /** Successful outcome carrying [value]. */
    data class Success<out T>(val value: T) : NovaResult<T>()

    /** Failed outcome carrying a structured [error]. */
    data class Failure(val error: NovaError) : NovaResult<Nothing>()

    /** Returns the value on success, or null on failure. */
    fun getOrNull(): T? = when (this) {
        is Success -> value
        is Failure -> null
    }

    /** Transforms the value on success; passes failure through unchanged. */
    fun <R> map(transform: (T) -> R): NovaResult<R> = when (this) {
        is Success -> Success(transform(value))
        is Failure -> this
    }

    companion object {
        /** Convenience factory for a failure result. */
        fun failure(
            code: ErrorCode,
            message: String,
            cause: Throwable? = null
        ): Failure = Failure(NovaError(code, message, cause))
    }
}
EOF

# ---------- 2. core/Models.kt ----------
cat > "$BASE/core/Models.kt" <<'EOF'
package com.nova.ai.core

/** Language detected in a spoken or typed command. */
enum class Language { BANGLA, ENGLISH, MIXED, UNKNOWN }

/** A single user command from voice or text input. */
data class VoiceCommand(
    val rawText: String,
    val language: Language,
    val timestampMs: Long
)

/** Categories of things the user can ask the agent to do. */
enum class IntentType {
    OPEN_APP,
    SEND_MESSAGE,
    MAKE_CALL,
    WEB_SEARCH,
    SYSTEM_ACTION,
    SET_ALARM,
    MEDIA_CONTROL,
    UNKNOWN
}

/** Understood meaning of a command (named NovaIntent to avoid clashing with android.content.Intent). */
data class NovaIntent(
    val type: IntentType,
    val entities: Map<String, String>,
    val confidence: Float
)

/** Primitive actions a task step can perform. */
enum class StepAction {
    OPEN_APP,
    CLICK,
    TYPE_TEXT,
    SCROLL,
    BACK,
    HOME,
    WAIT,
    CONFIRM,
    SPEAK
}

/** One executable step inside a [TaskPlan]. */
data class TaskStep(
    val id: String,
    val action: StepAction,
    val target: String? = null,
    val value: String? = null,
    val requiresConfirmation: Boolean = false
)

/** Ordered list of steps that fulfils one intent. */
data class TaskPlan(
    val id: String,
    val title: String,
    val steps: List<TaskStep>
)

/** Lifecycle state of a submitted task. */
enum class TaskStatus { PENDING, RUNNING, PAUSED, COMPLETED, FAILED, CANCELLED }

/** Scroll direction for screen scrolling. */
enum class ScrollDirection { UP, DOWN, LEFT, RIGHT }

/** Screen rectangle in pixels. */
data class ScreenBounds(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int
)

/** One visible UI element read from the screen. */
data class ScreenNode(
    val text: String?,
    val contentDescription: String?,
    val className: String?,
    val packageName: String?,
    val isClickable: Boolean,
    val isEditable: Boolean,
    val isScrollable: Boolean,
    val bounds: ScreenBounds
)

/** Snapshot of everything currently visible on screen. */
data class ScreenSnapshot(
    val packageName: String?,
    val nodes: List<ScreenNode>,
    val capturedAtMs: Long
)

/** UI element found by the vision model. */
data class DetectedElement(
    val label: String,
    val bounds: ScreenBounds,
    val confidence: Float
)

/** How risky a step is. */
enum class RiskLevel { LOW, MEDIUM, HIGH }

/** Security verdict for a step. */
data class SecurityDecision(
    val allowed: Boolean,
    val requiresConfirmation: Boolean,
    val risk: RiskLevel,
    val reason: String
)

/** Outcome of checking whether a step really worked. */
data class VerificationReport(
    val stepId: String,
    val passed: Boolean,
    val detail: String
)

/** One saved user fact or preference. */
data class MemoryItem(
    val key: String,
    val value: String,
    val updatedAtMs: Long
)

/** Kinds of local AI models the app can manage. */
enum class ModelType { SPEECH, LANGUAGE, VISION }

/** Description of a local AI model. */
data class ModelInfo(
    val id: String,
    val name: String,
    val type: ModelType,
    val sizeBytes: Long,
    val isInstalled: Boolean
)

/** System settings screens the controller can open. */
enum class SettingsSection { MAIN, WIFI, BLUETOOTH, SOUND, DISPLAY, APPS, ACCESSIBILITY }
EOF

# ---------- 3. voice/VoiceEngine.kt ----------
cat > "$BASE/voice/VoiceEngine.kt" <<'EOF'
package com.nova.ai.voice

import com.nova.ai.core.Language
import com.nova.ai.core.NovaError
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand

/** Receives events from the [VoiceEngine]. */
interface VoiceListener {
    fun onListeningStarted()
    fun onPartialText(text: String)
    fun onFinalCommand(command: VoiceCommand)
    fun onError(error: NovaError)
}

/** Voice input (speech to text) and output (text to speech). */
interface VoiceEngine {
    /** Starts listening; results arrive through [listener]. */
    fun startListening(listener: VoiceListener): NovaResult<Unit>

    /** Stops listening immediately. */
    fun stopListening()

    /** Speaks [text] aloud in the given [language]. */
    fun speak(text: String, language: Language): NovaResult<Unit>

    /** True while the microphone is active. */
    fun isListening(): Boolean

    /** Releases microphone and speech resources. */
    fun shutdown()
}
EOF

# ---------- 4. brain/AiBrain.kt ----------
cat > "$BASE/brain/AiBrain.kt" <<'EOF'
package com.nova.ai.brain

import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand

/** Understands user commands and turns them into structured intents. */
interface AiBrain {
    /**
     * Analyzes [command] using [recentContext] (previous commands, oldest first)
     * so follow-up commands like "now search that" can be understood.
     */
    fun analyze(
        command: VoiceCommand,
        recentContext: List<VoiceCommand>
    ): NovaResult<NovaIntent>
}
EOF

# ---------- 5. planner/TaskPlanner.kt ----------
cat > "$BASE/planner/TaskPlanner.kt" <<'EOF'
package com.nova.ai.planner

import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.TaskPlan

/** Breaks an intent into an ordered, executable list of steps. */
interface TaskPlanner {
    /** Builds a plan for [intent], or fails if the intent cannot be planned. */
    fun createPlan(intent: NovaIntent): NovaResult<TaskPlan>
}
EOF

# ---------- 6. controller/AndroidController.kt ----------
cat > "$BASE/controller/AndroidController.kt" <<'EOF'
package com.nova.ai.controller

import com.nova.ai.core.NovaResult
import com.nova.ai.core.SettingsSection

/** Performs permitted system-level actions (apps, settings, dialer). */
interface AndroidController {
    /** True if an app matching [appName] is installed. */
    fun isAppInstalled(appName: String): Boolean

    /** Opens the installed app best matching [appName]. */
    fun openApp(appName: String): NovaResult<Unit>

    /** Opens the given system settings screen. */
    fun openSystemSettings(section: SettingsSection): NovaResult<Unit>

    /** Opens the dialer with [phoneNumber] filled in (does not place the call). */
    fun openDialer(phoneNumber: String): NovaResult<Unit>
}
EOF

# ---------- 7. accessibility/AccessibilityEngine.kt ----------
cat > "$BASE/accessibility/AccessibilityEngine.kt" <<'EOF'
package com.nova.ai.accessibility

import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.ScrollDirection

/** Reads and controls the screen through the Android Accessibility Service. */
interface AccessibilityEngine {
    /** True if the user has enabled the accessibility service. */
    fun isServiceEnabled(): Boolean

    /** Captures the visible UI elements. */
    fun captureScreen(): NovaResult<ScreenSnapshot>

    /** Taps the given [node]. */
    fun click(node: ScreenNode): NovaResult<Unit>

    /** Types [text] into the given editable [node]. */
    fun typeText(node: ScreenNode, text: String): NovaResult<Unit>

    /** Scrolls the screen in [direction]. */
    fun scroll(direction: ScrollDirection): NovaResult<Unit>

    /** Presses the system Back button. */
    fun pressBack(): NovaResult<Unit>

    /** Goes to the Home screen. */
    fun pressHome(): NovaResult<Unit>
}
EOF

# ---------- 8. vision/VisionEngine.kt ----------
cat > "$BASE/vision/VisionEngine.kt" <<'EOF'
package com.nova.ai.vision

import com.nova.ai.core.DetectedElement
import com.nova.ai.core.NovaResult

/** Local computer vision, used only when the accessibility tree is not enough. */
interface VisionEngine {
    /** True if a vision model is installed and ready. */
    fun isAvailable(): Boolean

    /** Finds UI elements in an encoded screenshot ([screenshot] as PNG/JPEG bytes). */
    fun detectElements(screenshot: ByteArray): NovaResult<List<DetectedElement>>
}
EOF

# ---------- 9. memory/MemoryManager.kt ----------
cat > "$BASE/memory/MemoryManager.kt" <<'EOF'
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
EOF

# ---------- 10. security/SecurityManager.kt ----------
cat > "$BASE/security/SecurityManager.kt" <<'EOF'
package com.nova.ai.security

import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.SecurityDecision
import com.nova.ai.core.TaskStep

/** Decides whether a step is safe and whether it needs user confirmation. */
interface SecurityManager {
    /** Evaluates [step] against the current [screen] (if known). */
    fun evaluate(step: TaskStep, screen: ScreenSnapshot?): SecurityDecision

    /** True if [text] looks like a password, OTP, or similar secret. */
    fun isSensitiveText(text: String): Boolean

    /** Immediately halts all automation. */
    fun triggerEmergencyStop()

    /** True while an emergency stop is active. */
    fun isEmergencyStopped(): Boolean

    /** Clears the emergency stop after the user confirms. */
    fun resetEmergencyStop()
}
EOF

# ---------- 11. verification/VerificationEngine.kt ----------
cat > "$BASE/verification/VerificationEngine.kt" <<'EOF'
package com.nova.ai.verification

import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.TaskStep
import com.nova.ai.core.VerificationReport

/** Checks whether a step really achieved its goal. */
interface VerificationEngine {
    /** Compares the screen [before] and [after] a [step] to confirm success. */
    fun verify(
        step: TaskStep,
        before: ScreenSnapshot?,
        after: ScreenSnapshot?
    ): NovaResult<VerificationReport>
}
EOF

# ---------- 12. automation/AutomationManager.kt ----------
cat > "$BASE/automation/AutomationManager.kt" <<'EOF'
package com.nova.ai.automation

import com.nova.ai.core.NovaResult
import com.nova.ai.core.TaskPlan
import com.nova.ai.core.TaskStatus

/** Receives progress updates for running tasks. */
interface AutomationListener {
    fun onStatusChanged(taskId: String, status: TaskStatus)
    fun onStepCompleted(taskId: String, stepId: String)
}

/** Queues and runs task plans with pause, resume, and cancel support. */
interface AutomationManager {
    /** Registers the progress listener (null to remove). */
    fun setListener(listener: AutomationListener?)

    /** Adds [plan] to the queue and returns its task id. */
    fun submit(plan: TaskPlan): NovaResult<String>

    fun pause(taskId: String): NovaResult<Unit>
    fun resume(taskId: String): NovaResult<Unit>
    fun cancel(taskId: String): NovaResult<Unit>

    /** Stops every queued and running task. */
    fun cancelAll()

    /** Current status of a task, or null if unknown. */
    fun getStatus(taskId: String): TaskStatus?
}
EOF

# ---------- 13. models/LocalModelManager.kt ----------
cat > "$BASE/models/LocalModelManager.kt" <<'EOF'
package com.nova.ai.models

import com.nova.ai.core.ModelInfo
import com.nova.ai.core.ModelType
import com.nova.ai.core.NovaResult

/** Manages local AI models stored on the device. */
interface LocalModelManager {
    /** Lists all known models, installed or not. */
    fun listModels(): NovaResult<List<ModelInfo>>

    /** Lists models of one [type]. */
    fun listModels(type: ModelType): NovaResult<List<ModelInfo>>

    /** True if the model with [modelId] is installed. */
    fun isInstalled(modelId: String): Boolean

    /** Removes an installed model to free storage. */
    fun delete(modelId: String): NovaResult<Unit>
}
EOF

# ---------- Commit and push ----------
git add -A
git commit -m "P2: 12-module architecture interfaces and core models"
git push

echo "P2 files created and pushed."
