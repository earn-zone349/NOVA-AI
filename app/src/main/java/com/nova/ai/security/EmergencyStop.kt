package com.nova.ai.security

import com.nova.ai.accessibility.ActionGate
import com.nova.ai.logging.NovaLogger
import com.nova.ai.voice.VoiceFocus
import java.util.concurrent.CopyOnWriteArrayList

/**
 * The logic of the emergency stop, free of Android classes so it can be tested without a phone.
 * Triggering it switches the stop on, then runs every registered hook (each one on its own, so a
 * failing hook cannot block the others), and tells the listeners when the state really changed.
 * Hooks and listeners run on the thread that triggers the stop: they must be quick, and a hook
 * that needs the main thread must switch to it by itself.
 */
class EmergencyStopController(
    private val readStopped: () -> Boolean,
    private val writeStopped: (Boolean) -> Unit,
    private val onHookError: (key: String, error: Throwable) -> Unit = { _, _ -> },
    private val onEvent: (String) -> Unit = {}
) {

    private val lock = Any()
    private val hooks: LinkedHashMap<String, () -> Unit> = LinkedHashMap()
    private val listeners: CopyOnWriteArrayList<(Boolean) -> Unit> = CopyOnWriteArrayList()

    /** True while the emergency stop is on. */
    val isActive: Boolean get() = readStopped()

    /**
     * Switches the stop on and runs the hooks. The hooks also run when the stop is already on,
     * so one more tap still stops anything that started in the meantime.
     * Returns true if the stop was off before.
     */
    fun trigger(source: String): Boolean {
        val changed: Boolean = !readStopped()
        writeStopped(true)
        onEvent("Emergency stop on (from $source)")
        runHooks()
        if (changed) notifyListeners(true)
        return changed
    }

    /** Switches the stop off. Returns true if it was on before. */
    fun release(source: String): Boolean {
        val changed: Boolean = readStopped()
        writeStopped(false)
        if (changed) {
            onEvent("Emergency stop off (from $source)")
            notifyListeners(false)
        }
        return changed
    }

    /** Registers (or replaces) the hook with the given [key]. It runs every time the stop is triggered. */
    fun registerHook(key: String, hook: () -> Unit) {
        synchronized(lock) { hooks[key] = hook }
    }

    /** Removes the hook with the given [key]. */
    fun unregisterHook(key: String) {
        synchronized(lock) { hooks.remove(key) }
    }

    /** Calls [listener] with true when the stop goes on and with false when it goes off. */
    fun addListener(listener: (Boolean) -> Unit) {
        listeners.addIfAbsent(listener)
    }

    /** Stops calling [listener]. */
    fun removeListener(listener: (Boolean) -> Unit) {
        listeners.remove(listener)
    }

    private fun runHooks() {
        val snapshot: List<Pair<String, () -> Unit>> =
            synchronized(lock) { hooks.entries.map { it.key to it.value } }
        for ((key, hook) in snapshot) {
            try {
                hook()
            } catch (e: Exception) {
                onHookError(key, e)
            }
        }
    }

    private fun notifyListeners(active: Boolean) {
        for (listener in listeners) {
            try {
                listener(active)
            } catch (e: Exception) {
                onHookError("listener", e)
            }
        }
    }
}

/**
 * The app-wide emergency stop. One tap (the floating bubble, the quick settings tile or the
 * notification button) switches off everything NOVA does by itself: the accessibility actions
 * ([ActionGate]), listening and speaking ([VoiceFocus]), and whatever later parts register as
 * a hook (the task planner cancels its queue this way).
 */
object EmergencyStop {

    /** The message shown to the user while the stop is on. */
    const val MESSAGE: String = "জরুরি Stop চালু আছে। ছাড়া না পর্যন্ত নোভা কোনো কাজ করবে না।"

    private const val TAG: String = "EmergencyStop"
    private const val VOICE_HOOK: String = "voice"

    private val controller = EmergencyStopController(
        readStopped = { ActionGate.isStopped },
        writeStopped = { stopped -> if (stopped) ActionGate.stop() else ActionGate.resume() },
        onHookError = { key, error -> NovaLogger.e(TAG, "Stop hook \"$key\" failed", error) },
        onEvent = { line -> NovaLogger.w(TAG, line) }
    )

    init {
        controller.registerHook(VOICE_HOOK) { VoiceFocus.stopAll() }
    }

    /** True while the emergency stop is on. */
    val isActive: Boolean get() = controller.isActive

    /** Switches the emergency stop on and stops everything. [source] says who asked (for the log). */
    fun trigger(source: String): Boolean = controller.trigger(source)

    /** Switches the emergency stop off. */
    fun release(source: String): Boolean = controller.release(source)

    /** Registers a hook that runs on every stop. See [EmergencyStopController.registerHook]. */
    fun registerHook(key: String, hook: () -> Unit) = controller.registerHook(key, hook)

    /** Removes a hook. */
    fun unregisterHook(key: String) = controller.unregisterHook(key)

    /** Calls [listener] when the stop goes on or off. */
    fun addListener(listener: (Boolean) -> Unit) = controller.addListener(listener)

    /** Stops calling [listener]. */
    fun removeListener(listener: (Boolean) -> Unit) = controller.removeListener(listener)
}
