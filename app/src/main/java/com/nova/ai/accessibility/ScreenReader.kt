package com.nova.ai.accessibility

import android.graphics.Rect
import android.os.Build
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenBounds
import com.nova.ai.logging.NovaLogger

/**
 * Reads the screen tree given by the accessibility service and turns it into a list
 * of [UiNode]. Only items the user can see are read. Plain layout boxes without
 * text or actions are skipped. Reading is limited in size and depth so it stays fast.
 *
 * Privacy rules:
 *  - Password, PIN, OTP and CVV fields give out nothing.
 *  - Text typed into any input field is never read; only the field's label is kept.
 *  - Code numbers inside other texts are masked.
 *  - Nothing that is read is logged or stored.
 *
 * Heavy: call from a background thread.
 */
object ScreenReader {

    private const val TAG: String = "ScreenReader"
    private const val MAX_KEPT_NODES: Int = 600
    private const val MAX_VISITED_NODES: Int = 3000
    private const val MAX_DEPTH: Int = 60
    private const val MAX_TEXT_LENGTH: Int = 200

    private const val MSG_NOT_CONNECTED: String = "Accessibility সার্ভিস সংযুক্ত নেই। Access ট্যাবে গিয়ে চালু করো।"
    private const val MSG_UNAVAILABLE: String =
        "স্ক্রিনের তথ্য পাওয়া যায়নি। অ্যাপটি পড়তে দিচ্ছে না, বা স্ক্রিন বদলাচ্ছে। আবার চেষ্টা করো।"
    private const val MSG_FAILED: String = "স্ক্রিন পড়তে সমস্যা হয়েছে।"

    /** Collects the nodes found while walking the tree. */
    private class WalkState {
        val nodes: MutableList<UiNode> = ArrayList()
        var visited: Int = 0
        var truncated: Boolean = false
        var hiddenSensitive: Int = 0
    }

    /** Reads the window that is in front at this moment, through the running service. */
    fun capture(): NovaResult<ScreenCapture> {
        val service = AccessibilityBridge.service()
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_NOT_CONNECTED)
        val root: AccessibilityNodeInfo? = try {
            service.rootInActiveWindow
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not get the active window", e)
            null
        }
        return read(root)
    }

    /** Reads the screen below [root]. The root is released when reading is done. */
    fun read(root: AccessibilityNodeInfo?): NovaResult<ScreenCapture> {
        if (root == null) return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_UNAVAILABLE)

        val startedAtMs: Long = SystemClock.elapsedRealtime()
        val state = WalkState()
        return try {
            val packageName: String? = root.packageName?.toString()
            walk(root, depth = 0, path = emptyList(), state = state)
            NovaResult.Success(
                ScreenCapture(
                    packageName = packageName,
                    nodes = state.nodes,
                    visitedCount = state.visited,
                    truncated = state.truncated,
                    hiddenSensitiveCount = state.hiddenSensitive,
                    capturedAtMs = System.currentTimeMillis(),
                    durationMs = SystemClock.elapsedRealtime() - startedAtMs
                )
            )
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to read the screen", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_FAILED, e)
        } finally {
            recycleQuietly(root)
        }
    }

    private fun walk(node: AccessibilityNodeInfo, depth: Int, path: List<Int>, state: WalkState) {
        state.visited += 1

        // Hidden parts (scrolled out of view, covered) are neither read nor entered.
        if (depth > 0 && !node.isVisibleToUser) return

        keepIfMeaningful(node, depth, path, state)

        if (depth >= MAX_DEPTH) {
            state.truncated = true
            return
        }
        for (index in 0 until node.childCount) {
            if (state.visited >= MAX_VISITED_NODES || state.nodes.size >= MAX_KEPT_NODES) {
                state.truncated = true
                return
            }
            val child: AccessibilityNodeInfo = node.getChild(index) ?: continue
            try {
                walk(child, depth + 1, path + index, state)
            } finally {
                recycleQuietly(child)
            }
        }
    }

    private fun keepIfMeaningful(
        node: AccessibilityNodeInfo,
        depth: Int,
        path: List<Int>,
        state: WalkState
    ) {
        val editable: Boolean = node.isEditable
        // For input fields the node text is what the user typed, so it is never even looked at.
        val rawText: String = if (editable) "" else node.text?.toString().orEmpty()
        val rawDescription: String = node.contentDescription?.toString().orEmpty()
        val hint: String = node.hintText?.toString().orEmpty()
        val viewId: String = node.viewIdResourceName.orEmpty()
        val clickable: Boolean = node.isClickable
        val longClickable: Boolean = node.isLongClickable
        val scrollable: Boolean = node.isScrollable
        val checkable: Boolean = node.isCheckable

        val meaningful: Boolean = rawText.isNotBlank() || rawDescription.isNotBlank() ||
            hint.isNotBlank() || clickable || longClickable || editable || scrollable || checkable
        if (!meaningful) return

        val rect = Rect()
        node.getBoundsInScreen(rect)
        if (rect.isEmpty) return

        val sensitive: Boolean = SensitiveNodePolicy.isSensitiveField(
            isPassword = node.isPassword,
            isEditable = editable,
            viewId = viewId,
            hint = hint,
            description = rawDescription
        )
        if (sensitive) state.hiddenSensitive += 1

        val text: String = if (sensitive) "" else limit(SensitiveNodePolicy.maskCodes(rawText))
        val description: String = if (sensitive) "" else limit(SensitiveNodePolicy.maskCodes(rawDescription))

        state.nodes.add(
            UiNode(
                id = state.nodes.size,
                depth = depth,
                path = path,
                text = text,
                description = description,
                hint = limit(hint),
                viewId = viewId,
                className = node.className?.toString().orEmpty(),
                bounds = ScreenBounds(rect.left, rect.top, rect.right, rect.bottom),
                isClickable = clickable,
                isLongClickable = longClickable,
                isEditable = editable,
                isScrollable = scrollable,
                isCheckable = checkable,
                isChecked = node.isChecked,
                isEnabled = node.isEnabled,
                isFocused = node.isFocused,
                isSensitive = sensitive
            )
        )
    }

    private fun limit(text: String): String =
        if (text.length > MAX_TEXT_LENGTH) text.take(MAX_TEXT_LENGTH) + "…" else text

    // Android 13 and newer recycle nodes by themselves; older versions need this call.
    @Suppress("DEPRECATION")
    private fun recycleQuietly(node: AccessibilityNodeInfo) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
        try {
            node.recycle()
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Failed to recycle a node", e)
        }
    }
}
