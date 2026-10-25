package com.nova.ai.accessibility

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * NOVA's accessibility service. It learns which app is in front and can read what is
 * visible on the screen. Clicking, typing and scrolling are added in the next phase.
 * It never logs or stores anything that appears on the screen.
 */
class NovaAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        AccessibilityBridge.attach(this)
        NovaLogger.i(TAG, "Accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val eventPackage: String = event.packageName?.toString() ?: return
        AccessibilityBridge.onForegroundPackage(eventPackage, packageName)
    }

    override fun onInterrupt() {
        NovaLogger.i(TAG, "Accessibility service interrupted")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        AccessibilityBridge.detach(this)
        NovaLogger.i(TAG, "Accessibility service disconnected")
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        AccessibilityBridge.detach(this)
        super.onDestroy()
    }

    /** Reads what is visible in the window the user is looking at now. */
    fun readActiveScreen(): NovaResult<ScreenCapture> = ScreenReader.read(rootInActiveWindow)

    private companion object {
        const val TAG: String = "NovaAccessibility"
    }
}
