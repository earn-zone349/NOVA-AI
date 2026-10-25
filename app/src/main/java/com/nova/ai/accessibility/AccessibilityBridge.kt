package com.nova.ai.accessibility

import android.accessibilityservice.AccessibilityService
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScrollDirection
import java.lang.ref.WeakReference

/**
 * Connects the screens and engines of the app with the running accessibility service.
 * The service registers itself here; everything else asks here instead of holding the service.
 */
object AccessibilityBridge {

    // Windows of the system itself are not "apps the user switched to".
    private val IGNORED_PACKAGES: Set<String> = setOf("com.android.systemui")

    private const val MSG_NOT_CONNECTED: String = "Accessibility সার্ভিস সংযুক্ত নেই।"

    @Volatile
    private var serviceRef: WeakReference<NovaAccessibilityService>? = null

    /** True while the service is running and connected. */
    var isConnected: Boolean by mutableStateOf(false)
        private set

    /** The package of the last app, other than NOVA, that came to the front. */
    var lastOtherPackage: String? by mutableStateOf<String?>(null)
        private set

    /** Called by the service when it connects. */
    fun attach(service: NovaAccessibilityService) {
        serviceRef = WeakReference(service)
        isConnected = true
    }

    /** Called by the service when it stops. */
    fun detach(service: NovaAccessibilityService) {
        if (serviceRef?.get() === service) {
            serviceRef = null
            isConnected = false
        }
    }

    /** Called by the service whenever a window comes to the front. */
    fun onForegroundPackage(foregroundPackage: String, ownPackage: String) {
        if (foregroundPackage == ownPackage || foregroundPackage in IGNORED_PACKAGES) return
        lastOtherPackage = foregroundPackage
    }

    /** The running service, or null if it is not connected. */
    fun service(): NovaAccessibilityService? = serviceRef?.get()

    // ---------------------------------------------------------------- reading

    /** Reads everything visible on the screen now. Blocking: call from a background thread. */
    fun readScreen(): NovaResult<ScreenCapture> {
        val current: NovaAccessibilityService = serviceRef?.get()
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_NOT_CONNECTED)
        return current.readActiveScreen()
    }

    // ---------------------------------------------------------------- acting (blocking: use a background thread)

    /** Performs a global action such as Home or Back (see AccessibilityService.GLOBAL_ACTION_*). */
    fun performGlobal(action: Int): NovaResult<Unit> =
        withService { service -> ScreenActions.performGlobal(service, action) }

    /** Clicks the item described by [target]. */
    fun click(target: NodeTarget): NovaResult<Unit> =
        withService { service -> ScreenActions.click(service, target) }

    /** Types [text] into the field described by [target]. Sensitive fields are refused. */
    fun typeText(target: NodeTarget, text: String, append: Boolean = false): NovaResult<Unit> =
        withService { service -> ScreenActions.typeText(service, target, text, append) }

    /** Scrolls the screen in [direction]. */
    fun scroll(direction: ScrollDirection): NovaResult<Unit> =
        withService { service -> ScreenActions.scroll(service, direction) }

    /** Presses the Back button. */
    fun pressBack(): NovaResult<Unit> = performGlobal(AccessibilityService.GLOBAL_ACTION_BACK)

    /** Goes to the Home screen. */
    fun pressHome(): NovaResult<Unit> = performGlobal(AccessibilityService.GLOBAL_ACTION_HOME)

    /** Opens the list of recent apps. */
    fun openRecents(): NovaResult<Unit> = performGlobal(AccessibilityService.GLOBAL_ACTION_RECENTS)

    /** Opens the notification shade. */
    fun openNotifications(): NovaResult<Unit> =
        performGlobal(AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS)

    /** Opens the quick settings panel. */
    fun openQuickSettings(): NovaResult<Unit> =
        performGlobal(AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS)

    private inline fun withService(
        block: (NovaAccessibilityService) -> NovaResult<Unit>
    ): NovaResult<Unit> {
        val current: NovaAccessibilityService = serviceRef?.get()
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_NOT_CONNECTED)
        return block(current)
    }
}
