package com.nova.ai.accessibility

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenBounds
import com.nova.ai.core.ScrollDirection
import com.nova.ai.logging.NovaLogger

/**
 * The things NOVA can do on the screen: click, type, scroll, and press Back, Home and the
 * like. Every action first checks the emergency stop. Typing is refused in password, PIN
 * and OTP fields. Clicking prefers the app's own click action and falls back to a tap.
 * Texts that are typed or read are never logged.
 */
object ScreenActions {

    private const val TAG: String = "ScreenActions"
    private const val MAX_CLICK_ANCESTORS: Int = 6
    private const val MAX_TYPED_LENGTH: Int = 500
    private const val MAX_SCROLL_VISITS: Int = 2000
    private const val SWIPE_DURATION_MS: Long = 350L

    private const val MSG_NO_SCREEN: String =
        "স্ক্রিনের তথ্য পাওয়া যায়নি। অ্যাপটি পড়তে দিচ্ছে না, বা স্ক্রিন বদলাচ্ছে।"
    private const val MSG_FIELD_NOT_FOUND: String = "লেখার ঘর স্ক্রিনে পাওয়া যায়নি।"
    private const val MSG_NOT_EDITABLE: String = "এটা লেখার ঘর নয়।"
    private const val MSG_SENSITIVE_FIELD: String =
        "এটা পাসওয়ার্ড বা পিন-জাতীয় ঘর। নিরাপত্তার জন্য নোভা এখানে লেখে না, তুমি নিজে লেখো।"
    private const val MSG_FIELD_REFUSED: String = "এই ঘর লেখা নিতে রাজি হয়নি।"
    private const val MSG_TEXT_EMPTY: String = "লেখার মতো কিছু নেই।"
    private const val MSG_TEXT_TOO_LONG: String = "লেখাটা অনেক বড়। ছোট করে বলো।"
    private const val MSG_ACTION_FAILED: String = "কাজটি করা যায়নি।"
    private const val MSG_UNEXPECTED: String = "কাজ করতে সমস্যা হয়েছে।"

    // ---------------------------------------------------------------- click

    /** Clicks the item described by [target]. */
    fun click(service: AccessibilityService, target: NodeTarget): NovaResult<Unit> {
        ActionGate.check()?.let { return it }

        val root: AccessibilityNodeInfo = service.rootInActiveWindow
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_NO_SCREEN)

        var clicked = false
        try {
            val resolved: AccessibilityNodeInfo? = NodeResolver.resolve(root, target)
            if (resolved != null) {
                try {
                    clicked = performClickOn(resolved)
                } finally {
                    NodeResolver.recycleQuietly(resolved)
                }
            }
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Click failed", e)
        } finally {
            NodeResolver.recycleQuietly(root)
        }

        if (clicked) return NovaResult.Success(Unit)
        // No click action worked: tap the middle of the item instead.
        return tapCenter(service, target.bounds)
    }

    // The item itself or its nearest clickable parent receives the click.
    private fun performClickOn(start: AccessibilityNodeInfo): Boolean {
        var current: AccessibilityNodeInfo = start
        var ownsCurrent = false
        try {
            for (step in 0..MAX_CLICK_ANCESTORS) {
                if (current.isClickable && current.isEnabled) {
                    return current.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                }
                val parent: AccessibilityNodeInfo = current.parent ?: return false
                if (ownsCurrent) NodeResolver.recycleQuietly(current)
                current = parent
                ownsCurrent = true
            }
            return false
        } finally {
            if (ownsCurrent) NodeResolver.recycleQuietly(current)
        }
    }

    private fun tapCenter(service: AccessibilityService, bounds: ScreenBounds): NovaResult<Unit> {
        val centerX: Float = (bounds.left + bounds.right) / 2f
        val centerY: Float = (bounds.top + bounds.bottom) / 2f
        return GestureRunner.tap(service, centerX, centerY)
    }

    // ---------------------------------------------------------------- type

    /**
     * Types [text] into the field described by [target]. With [append] the text is added
     * after what is already there; otherwise it replaces it. Sensitive fields are refused.
     */
    fun typeText(
        service: AccessibilityService,
        target: NodeTarget,
        text: String,
        append: Boolean
    ): NovaResult<Unit> {
        ActionGate.check()?.let { return it }
        if (text.isEmpty()) return NovaResult.failure(ErrorCode.INVALID_INPUT, MSG_TEXT_EMPTY)
        if (text.length > MAX_TYPED_LENGTH) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, MSG_TEXT_TOO_LONG)
        }

        val root: AccessibilityNodeInfo = service.rootInActiveWindow
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_NO_SCREEN)

        try {
            val node: AccessibilityNodeInfo = NodeResolver.resolve(root, target)
                ?: return NovaResult.failure(ErrorCode.NOT_FOUND, MSG_FIELD_NOT_FOUND)
            try {
                return setTextOn(node, text, append)
            } finally {
                NodeResolver.recycleQuietly(node)
            }
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Typing failed", e)
            return NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_UNEXPECTED, e)
        } finally {
            NodeResolver.recycleQuietly(root)
        }
    }

    private fun setTextOn(node: AccessibilityNodeInfo, text: String, append: Boolean): NovaResult<Unit> {
        if (!node.isEditable) return NovaResult.failure(ErrorCode.INVALID_INPUT, MSG_NOT_EDITABLE)

        // Decided on the live field, so a changed screen can never lead to a secret field.
        val sensitive: Boolean = SensitiveNodePolicy.isSensitiveField(
            isPassword = node.isPassword,
            isEditable = true,
            viewId = node.viewIdResourceName.orEmpty(),
            hint = node.hintText?.toString().orEmpty(),
            description = node.contentDescription?.toString().orEmpty()
        )
        if (sensitive) return NovaResult.failure(ErrorCode.SECURITY_BLOCKED, MSG_SENSITIVE_FIELD)

        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        val existing: String =
            if (append && !node.isShowingHintText) node.text?.toString().orEmpty() else ""
        val arguments = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, existing + text)
        }
        return if (node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)) {
            NovaResult.Success(Unit)
        } else {
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_FIELD_REFUSED)
        }
    }

    // ---------------------------------------------------------------- scroll

    /** Scrolls the biggest scrollable part of the screen, or swipes if there is none. */
    fun scroll(service: AccessibilityService, direction: ScrollDirection): NovaResult<Unit> {
        ActionGate.check()?.let { return it }

        val root: AccessibilityNodeInfo = service.rootInActiveWindow
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_NO_SCREEN)

        var scrolled = false
        try {
            val path: List<Int>? = largestScrollablePath(root)
            if (path != null) {
                val node: AccessibilityNodeInfo? = NodeResolver.byPath(root, path)
                if (node != null) {
                    try {
                        scrolled = performScroll(node, direction)
                    } finally {
                        NodeResolver.recycleQuietly(node)
                    }
                }
            }
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Scroll failed", e)
        } finally {
            NodeResolver.recycleQuietly(root)
        }

        if (scrolled) return NovaResult.Success(Unit)
        return swipeToScroll(service, direction)
    }

    private fun performScroll(node: AccessibilityNodeInfo, direction: ScrollDirection): Boolean {
        val specific: AccessibilityNodeInfo.AccessibilityAction = when (direction) {
            ScrollDirection.UP -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_UP
            ScrollDirection.DOWN -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_DOWN
            ScrollDirection.LEFT -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_LEFT
            ScrollDirection.RIGHT -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_RIGHT
        }
        if (node.actionList.any { it.id == specific.id }) return node.performAction(specific.id)

        val legacy: Int = when (direction) {
            ScrollDirection.DOWN, ScrollDirection.RIGHT -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            ScrollDirection.UP, ScrollDirection.LEFT -> AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        }
        return node.performAction(legacy)
    }

    private fun swipeToScroll(service: AccessibilityService, direction: ScrollDirection): NovaResult<Unit> {
        val metrics = service.resources.displayMetrics
        val width: Float = metrics.widthPixels.toFloat()
        val height: Float = metrics.heightPixels.toFloat()
        val centerX: Float = width / 2f
        val centerY: Float = height / 2f
        return when (direction) {
            ScrollDirection.DOWN ->
                GestureRunner.swipe(service, centerX, height * 0.72f, centerX, height * 0.28f, SWIPE_DURATION_MS)
            ScrollDirection.UP ->
                GestureRunner.swipe(service, centerX, height * 0.28f, centerX, height * 0.72f, SWIPE_DURATION_MS)
            ScrollDirection.RIGHT ->
                GestureRunner.swipe(service, width * 0.75f, centerY, width * 0.25f, centerY, SWIPE_DURATION_MS)
            ScrollDirection.LEFT ->
                GestureRunner.swipe(service, width * 0.25f, centerY, width * 0.75f, centerY, SWIPE_DURATION_MS)
        }
    }

    /** What the search for the biggest scrollable part has found so far. */
    private class ScrollSearch {
        var bestPath: List<Int>? = null
        var bestArea: Long = 0L
        var visits: Int = 0
    }

    private fun largestScrollablePath(root: AccessibilityNodeInfo): List<Int>? {
        val state = ScrollSearch()
        searchScrollable(root, emptyList(), state)
        return state.bestPath
    }

    private fun searchScrollable(node: AccessibilityNodeInfo, path: List<Int>, state: ScrollSearch) {
        state.visits += 1
        if (path.isNotEmpty() && !node.isVisibleToUser) return

        if (path.isNotEmpty() && node.isScrollable) {
            val rect = Rect()
            node.getBoundsInScreen(rect)
            val area: Long = rect.width().toLong() * rect.height().toLong()
            if (area > state.bestArea) {
                state.bestArea = area
                state.bestPath = path
            }
        }
        for (index in 0 until node.childCount) {
            if (state.visits >= MAX_SCROLL_VISITS) return
            val child: AccessibilityNodeInfo = node.getChild(index) ?: continue
            try {
                searchScrollable(child, path + index, state)
            } finally {
                NodeResolver.recycleQuietly(child)
            }
        }
    }

    // ---------------------------------------------------------------- Back, Home and the like

    /** Performs a global action (Back, Home, recent apps, notifications, quick settings). */
    fun performGlobal(service: AccessibilityService, action: Int): NovaResult<Unit> {
        ActionGate.check()?.let { return it }
        return if (service.performGlobalAction(action)) {
            NovaResult.Success(Unit)
        } else {
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_ACTION_FAILED)
        }
    }
}
