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
