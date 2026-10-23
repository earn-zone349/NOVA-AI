package com.nova.ai.accessibility

import android.view.accessibility.AccessibilityNodeInfo
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.logging.NovaLogger

/**
 * Captures what is on the screen right now. Needs the accessibility service to be
 * connected. Never throws; every problem comes back as a [NovaResult.Failure].
 * Heavy: call from a background thread.
 */
object ScreenReader {

    private const val TAG: String = "ScreenReader"

    /** Reads the window that is in front at this moment. */
    fun capture(): NovaResult<ScreenSnapshot> {
        val service: NovaAccessibilityService = AccessibilityBridge.service()
            ?: return NovaResult.failure(
                ErrorCode.NOT_AVAILABLE,
                "Accessibility সার্ভিস সংযুক্ত নেই। Access ট্যাবে গিয়ে চালু করো।"
            )

        val root: AccessibilityNodeInfo? = fetchRoot(service)
        if (root == null) {
            return NovaResult.failure(
                ErrorCode.TEMPORARY_FAILURE,
                "স্ক্রিন এখন পড়া যাচ্ছে না। একটু পরে আবার চেষ্টা করো।"
            )
        }

        return try {
            NovaResult.Success(ScreenTreeReader.read(root, System.currentTimeMillis()))
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Reading the screen failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "স্ক্রিন পড়তে সমস্যা হয়েছে।", e)
        } finally {
            recycleQuietly(root)
        }
    }

    private fun fetchRoot(service: NovaAccessibilityService): AccessibilityNodeInfo? {
        return try {
            service.rootInActiveWindow
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not get the active window", e)
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun recycleQuietly(node: AccessibilityNodeInfo) {
        try {
            node.recycle()
        } catch (e: Exception) {
            // Harmless: recycling only returns memory to a pool.
        }
    }
}
