package com.nova.ai.voice

import com.nova.ai.logging.NovaLogger

/**
 * Keeps the microphone to one user at a time. The Home screen and the floating bubble both
 * listen; each registers a stop action here. When one of them starts listening it calls
 * [VoiceFocusRegistry.claim], which stops the other, so two voice sessions never fight.
 * The emergency stop calls [VoiceFocusRegistry.stopAll].
 * A stop action must be quick and must switch to the main thread by itself if it needs it.
 */
class VoiceFocusRegistry(
    private val onError: (owner: String, error: Throwable) -> Unit = { _, _ -> }
) {

    private val lock = Any()
    private val owners: LinkedHashMap<String, () -> Unit> = LinkedHashMap()

    /** Registers (or replaces) the stop action of [owner]. */
    fun register(owner: String, stop: () -> Unit) {
        synchronized(lock) { owners[owner] = stop }
    }

    /** Removes [owner]. */
    fun unregister(owner: String) {
        synchronized(lock) { owners.remove(owner) }
    }

    /** [owner] starts to listen: every other owner is stopped. */
    fun claim(owner: String) = stopMatching { key -> key != owner }

    /** Stops every owner. */
    fun stopAll() = stopMatching { true }

    private fun stopMatching(selector: (String) -> Boolean) {
        val targets: List<Pair<String, () -> Unit>> =
            synchronized(lock) { owners.entries.filter { selector(it.key) }.map { it.key to it.value } }
        for ((owner, stop) in targets) {
            try {
                stop()
            } catch (e: Exception) {
                onError(owner, e)
            }
        }
    }
}

/** The app-wide [VoiceFocusRegistry]. */
object VoiceFocus {

    private const val TAG: String = "VoiceFocus"

    private val registry = VoiceFocusRegistry { owner, error ->
        NovaLogger.e(TAG, "Stopping \"$owner\" failed", error)
    }

    /** Registers (or replaces) the stop action of [owner]. */
    fun register(owner: String, stop: () -> Unit) = registry.register(owner, stop)

    /** Removes [owner]. */
    fun unregister(owner: String) = registry.unregister(owner)

    /** [owner] starts to listen: every other owner is stopped. */
    fun claim(owner: String) = registry.claim(owner)

    /** Stops every owner. */
    fun stopAll() = registry.stopAll()
}
