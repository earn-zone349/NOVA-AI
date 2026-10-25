#!/usr/bin/env bash
# NOVA AI - Phase 19 setup script: click, type, scroll, Back/Home and the real AccessibilityEngine.
# Additive: new action classes and a test card; AccessibilityBridge is rewritten with every
# P17 and P18 feature kept; PermissionsScreen gets two additive lines.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
PERMISSIONS_FILE="$BASE/ui/screens/PermissionsScreen.kt"

for required in \
  "$BASE/accessibility/AccessibilityBridge.kt" \
  "$BASE/accessibility/ScreenReader.kt" \
  "$BASE/accessibility/SensitiveNodePolicy.kt" \
  "$BASE/accessibility/AccessibilityEngine.kt" \
  "$BASE/apps/PhoneticKey.kt" \
  "$BASE/ui/components/ScreenReadLabCard.kt" \
  "$PERMISSIONS_FILE"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after P18 is installed." >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"

# ---------- A. New strings file ----------
cat > app/src/main/res/values/strings_p19.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="act_title">ক্লিক, লেখা ও স্ক্রল পরীক্ষা (P19)</string>
    <string name="act_note">নোভা স্ক্রিন পড়ে নাম মিলিয়ে বাটন খুঁজে ক্লিক করে, লেখার ঘরে লেখে, স্ক্রল করে এবং Back বা Home চাপে। পাসওয়ার্ড ও পিন ঘরে কখনো লেখে না।</string>
    <string name="act_need_service">আগে ওপরের সেটআপে Accessibility চালু করো।</string>
    <string name="act_query_label">বাটন বা ঘরের নাম (স্ক্রিনে যেমন লেখা)</string>
    <string name="act_text_label">যা লিখব</string>
    <string name="act_delay_label">৫ সেকেন্ড পরে করো (এরপর অন্য অ্যাপ খোলো)</string>
    <string name="act_waiting">%1$d সেকেন্ড পরে কাজ হবে। এখন অন্য অ্যাপ খোলো।</string>
    <string name="act_cancel">থামাও</string>
    <string name="act_click">ক্লিক করো</string>
    <string name="act_type">লেখো</string>
    <string name="act_scroll_up">↑ উপরে স্ক্রল</string>
    <string name="act_scroll_down">↓ নিচে স্ক্রল</string>
    <string name="act_back">Back</string>
    <string name="act_home">Home</string>
    <string name="act_recents">সাম্প্রতিক অ্যাপ</string>

    <string name="act_stop_title">জরুরি Stop পরীক্ষা</string>
    <string name="act_stop_on">জরুরি Stop চালু: নোভা কোনো কাজ করবে না।</string>
    <string name="act_stop_off">জরুরি Stop বন্ধ: নোভা কাজ করতে পারে।</string>
    <string name="act_stop_enable">জরুরি Stop চালু করো</string>
    <string name="act_stop_disable">জরুরি Stop ছাড়ো</string>

    <string name="act_ok_click">ক্লিক করেছি: %1$s</string>
    <string name="act_ok_type">লিখেছি: ঘর \"%1$s\"</string>
    <string name="act_ok_type_first">লিখেছি: প্রথম লেখার ঘরে</string>
    <string name="act_ok_scroll_up">উপরে স্ক্রল করেছি।</string>
    <string name="act_ok_scroll_down">নিচে স্ক্রল করেছি।</string>
    <string name="act_ok_back">Back চেপেছি।</string>
    <string name="act_ok_home">Home চেপেছি।</string>
    <string name="act_ok_recents">সাম্প্রতিক অ্যাপের তালিকা খুলেছি।</string>
    <string name="act_need_name">আগে বাটনের নাম লেখো।</string>
    <string name="act_need_text">আগে যা লিখবে তা লেখো।</string>
    <string name="act_not_found">\"%1$s\" নামে কিছু স্ক্রিনে পাইনি। স্ক্রিন পড়ার পরীক্ষা চালিয়ে ঠিক নাম দেখো।</string>
    <string name="act_no_field">লেখার ঘর পাওয়া যায়নি।</string>
    <string name="act_failed">কাজ হয়নি: %1$s</string>
</resources>
EOF

# ---------- 1. ActionGate.kt ----------
cat > "$BASE/accessibility/ActionGate.kt" <<'EOF'
package com.nova.ai.accessibility

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult

/**
 * The emergency stop. While it is on, every action of the accessibility service
 * (clicks, typing, scrolling, Back, Home, gestures) is refused. Reading is not affected.
 * The floating stop button of a later phase switches it on.
 */
object ActionGate {

    private const val MSG_STOPPED: String =
        "জরুরি Stop চালু আছে। ছাড়া না পর্যন্ত নোভা কোনো কাজ করবে না।"

    /** True while the emergency stop is on. */
    var isStopped: Boolean by mutableStateOf(false)
        private set

    /** Switches the emergency stop on. */
    fun stop() {
        isStopped = true
    }

    /** Switches the emergency stop off. */
    fun resume() {
        isStopped = false
    }

    /** Returns a failure to hand back to the caller while stopped, or null when actions are allowed. */
    fun check(): NovaResult.Failure? =
        if (isStopped) NovaResult.failure(ErrorCode.SECURITY_BLOCKED, MSG_STOPPED) else null
}
EOF

# ---------- 2. NodeTarget.kt ----------
cat > "$BASE/accessibility/NodeTarget.kt" <<'EOF'
package com.nova.ai.accessibility

import com.nova.ai.core.ScreenBounds

/**
 * Describes the item an action is meant for, so it can be found again on the live screen.
 * [path] is the position in the screen tree (when known); [bounds], [className] and
 * [viewId] are used to check that the right item was found, or to search for it.
 */
data class NodeTarget(
    val path: List<Int>?,
    val bounds: ScreenBounds,
    val className: String,
    val viewId: String
)

/** The target that points at this item. */
fun UiNode.toTarget(): NodeTarget =
    NodeTarget(path = path, bounds = bounds, className = className, viewId = viewId)
EOF

# ---------- 3. NodeResolver.kt ----------
cat > "$BASE/accessibility/NodeResolver.kt" <<'EOF'
package com.nova.ai.accessibility

import android.graphics.Rect
import android.os.Build
import android.view.accessibility.AccessibilityNodeInfo
import com.nova.ai.logging.NovaLogger

/**
 * Finds the live screen item that belongs to a [NodeTarget]. It follows the saved
 * path and checks the item is the right one; if the screen changed, it searches by
 * position, class and id. Every node handed back must be released with [recycleQuietly].
 */
internal object NodeResolver {

    private const val TAG: String = "NodeResolver"
    private const val MAX_SEARCH_VISITS: Int = 3000
    private const val MAX_SEARCH_DEPTH: Int = 60

    /** The live node for [target] under [root], or null. The caller keeps ownership of [root]. */
    fun resolve(root: AccessibilityNodeInfo, target: NodeTarget): AccessibilityNodeInfo? {
        val path: List<Int>? = target.path
        if (path != null && path.isNotEmpty()) {
            val found: AccessibilityNodeInfo? = byPath(root, path)
            if (found != null) {
                if (matches(found, target)) return found
                recycleQuietly(found)
            }
        }
        return search(root, target, depth = 0, budget = IntArray(1) { MAX_SEARCH_VISITS })
    }

    /** Follows [path] (child positions) down from [root]. An empty path gives null. */
    fun byPath(root: AccessibilityNodeInfo, path: List<Int>): AccessibilityNodeInfo? {
        if (path.isEmpty()) return null
        var current: AccessibilityNodeInfo = root
        var ownsCurrent = false
        for (index in path) {
            val child: AccessibilityNodeInfo? = current.getChild(index)
            if (ownsCurrent) recycleQuietly(current)
            if (child == null) return null
            current = child
            ownsCurrent = true
        }
        return current
    }

    private fun search(
        node: AccessibilityNodeInfo,
        target: NodeTarget,
        depth: Int,
        budget: IntArray
    ): AccessibilityNodeInfo? {
        if (depth > MAX_SEARCH_DEPTH) return null
        for (index in 0 until node.childCount) {
            if (budget[0] <= 0) return null
            budget[0] -= 1
            val child: AccessibilityNodeInfo = node.getChild(index) ?: continue
            if (matches(child, target)) return child
            val deeper: AccessibilityNodeInfo? = search(child, target, depth + 1, budget)
            recycleQuietly(child)
            if (deeper != null) return deeper
        }
        return null
    }

    private fun matches(node: AccessibilityNodeInfo, target: NodeTarget): Boolean {
        val rect = Rect()
        node.getBoundsInScreen(rect)
        val bounds = target.bounds
        if (rect.left != bounds.left || rect.top != bounds.top ||
            rect.right != bounds.right || rect.bottom != bounds.bottom
        ) {
            return false
        }
        if (target.className.isNotEmpty() && node.className?.toString() != target.className) return false
        if (target.viewId.isNotEmpty() && node.viewIdResourceName != target.viewId) return false
        return true
    }

    /** Releases a node. Android 13 and newer do this by themselves. */
    @Suppress("DEPRECATION")
    fun recycleQuietly(node: AccessibilityNodeInfo) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
        try {
            node.recycle()
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Failed to recycle a node", e)
        }
    }
}
EOF

# ---------- 4. GestureRunner.kt ----------
cat > "$BASE/accessibility/GestureRunner.kt" <<'EOF'
package com.nova.ai.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Handler
import android.os.HandlerThread
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Performs touch gestures (a tap, a swipe) through the accessibility service and
 * waits until the phone says the gesture finished. Results come on a helper thread,
 * so waiting never blocks the screen thread.
 */
internal object GestureRunner {

    private const val TAG: String = "GestureRunner"
    private const val TAP_DURATION_MS: Long = 60L
    private const val WAIT_MARGIN_MS: Long = 1500L

    private const val MSG_REFUSED: String = "ফোন এই ইশারা নিতে রাজি হয়নি।"
    private const val MSG_NOT_DONE: String = "ইশারা সম্পন্ন হয়নি। স্ক্রিন এটা আটকে থাকতে পারে।"
    private const val MSG_FAILED: String = "ইশারা দিতে সমস্যা হয়েছে।"

    private val workerThread: HandlerThread = HandlerThread("nova-gesture").apply { start() }
    private val workerHandler: Handler = Handler(workerThread.looper)

    /** Taps the screen at ([x], [y]) in pixels. */
    fun tap(service: AccessibilityService, x: Float, y: Float): NovaResult<Unit> {
        val path = Path().apply { moveTo(x, y) }
        return dispatch(service, path, TAP_DURATION_MS)
    }

    /** Swipes from the start point to the end point over [durationMs]. */
    fun swipe(
        service: AccessibilityService,
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float,
        durationMs: Long
    ): NovaResult<Unit> {
        val path = Path().apply {
            moveTo(startX, startY)
            lineTo(endX, endY)
        }
        return dispatch(service, path, durationMs)
    }

    private fun dispatch(service: AccessibilityService, path: Path, durationMs: Long): NovaResult<Unit> {
        ActionGate.check()?.let { return it }

        return try {
            val gesture: GestureDescription = GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0L, durationMs))
                .build()
            val finished = CountDownLatch(1)
            val completed = AtomicBoolean(false)
            val callback = object : AccessibilityService.GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    completed.set(true)
                    finished.countDown()
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    finished.countDown()
                }
            }

            if (!service.dispatchGesture(gesture, callback, workerHandler)) {
                return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_REFUSED)
            }
            finished.await(durationMs + WAIT_MARGIN_MS, TimeUnit.MILLISECONDS)
            if (completed.get()) {
                NovaResult.Success(Unit)
            } else {
                NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_NOT_DONE)
            }
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            NovaResult.failure(ErrorCode.CANCELLED, MSG_NOT_DONE, e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Gesture failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_FAILED, e)
        }
    }
}
EOF

# ---------- 5. ScreenActions.kt ----------
cat > "$BASE/accessibility/ScreenActions.kt" <<'EOF'
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
EOF

# ---------- 6. NodeFinder.kt ----------
cat > "$BASE/accessibility/NodeFinder.kt" <<'EOF'
package com.nova.ai.accessibility

import com.nova.ai.apps.PhoneticKey

/**
 * Finds the item on a captured screen that best fits a name the user said or typed.
 * It tries exact names first, then partial matches, then names that sound alike
 * (so Bangla and English spellings of the same word can meet). Pure logic.
 */
object NodeFinder {

    /** Which kind of item may be returned. */
    enum class Filter { ANY, CLICKABLE, EDITABLE }

    private const val SCORE_EXACT: Float = 1.0f
    private const val SCORE_STARTS_WITH: Float = 0.9f
    private const val SCORE_CONTAINS: Float = 0.8f
    private const val SCORE_SAME_SOUND: Float = 0.75f
    private const val SCORE_INSIDE_QUERY: Float = 0.6f
    private const val MIN_SCORE: Float = 0.6f
    private const val MIN_CONTAINED_LENGTH: Int = 3

    /** The best item for [query], or null if nothing fits well enough. */
    fun findBest(capture: ScreenCapture, query: String, filter: Filter): UiNode? {
        val queryKey: String = PhoneticKey.nameKey(query)
        if (queryKey.isEmpty()) return null
        val queryPhonetic: String = PhoneticKey.phonetic(query)

        return capture.nodes
            .asSequence()
            .filter { passes(it, filter) }
            .map { node -> node to scoreOf(node, queryKey, queryPhonetic) }
            .filter { it.second >= MIN_SCORE }
            // Best name first; among equals the smaller item (more specific) wins.
            .sortedWith(compareByDescending<Pair<UiNode, Float>> { it.second }.thenBy { areaOf(it.first) })
            .firstOrNull()
            ?.first
    }

    /** The input field to type into when no name was given: the focused one, else the top-most. */
    fun firstEditable(capture: ScreenCapture): UiNode? {
        val fields: List<UiNode> = capture.nodes.filter { it.isEditable && it.isEnabled && !it.isSensitive }
        return fields.firstOrNull { it.isFocused }
            ?: fields.minWithOrNull(compareBy<UiNode>({ it.bounds.top }, { it.bounds.left }))
    }

    private fun passes(node: UiNode, filter: Filter): Boolean = when (filter) {
        Filter.ANY -> true
        Filter.CLICKABLE -> node.isClickable && node.isEnabled
        Filter.EDITABLE -> node.isEditable && node.isEnabled && !node.isSensitive
    }

    private fun scoreOf(node: UiNode, queryKey: String, queryPhonetic: String): Float {
        val labels: List<String> = listOf(node.text, node.description, node.hint)
            .filter { it.isNotBlank() }
            .ifEmpty { listOf(node.viewId.substringAfterLast('/')).filter { it.isNotBlank() } }

        var best = 0f
        for (label in labels) {
            val key: String = PhoneticKey.nameKey(label)
            if (key.isEmpty()) continue
            val score: Float = when {
                key == queryKey -> SCORE_EXACT
                key.startsWith(queryKey) -> SCORE_STARTS_WITH
                key.contains(queryKey) -> SCORE_CONTAINS
                queryPhonetic.isNotEmpty() && PhoneticKey.phonetic(label) == queryPhonetic -> SCORE_SAME_SOUND
                key.length >= MIN_CONTAINED_LENGTH && queryKey.contains(key) -> SCORE_INSIDE_QUERY
                else -> 0f
            }
            if (score > best) best = score
        }
        return best
    }

    private fun areaOf(node: UiNode): Long {
        val width: Long = (node.bounds.right - node.bounds.left).toLong()
        val height: Long = (node.bounds.bottom - node.bounds.top).toLong()
        return width * height
    }
}
EOF

# ---------- 7. NovaAccessibilityEngine.kt ----------
cat > "$BASE/accessibility/NovaAccessibilityEngine.kt" <<'EOF'
package com.nova.ai.accessibility

import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.ScrollDirection

/**
 * The real [AccessibilityEngine] of the app (the "hands and eyes"). The task planner
 * of a later phase uses this class to read the screen and act on it.
 */
class NovaAccessibilityEngine : AccessibilityEngine {

    override fun isServiceEnabled(): Boolean = AccessibilityBridge.isConnected

    override fun captureScreen(): NovaResult<ScreenSnapshot> =
        AccessibilityBridge.readScreen().map { capture -> toSnapshot(capture) }

    override fun click(node: ScreenNode): NovaResult<Unit> =
        AccessibilityBridge.click(targetOf(node))

    override fun typeText(node: ScreenNode, text: String): NovaResult<Unit> =
        AccessibilityBridge.typeText(targetOf(node), text, append = false)

    override fun scroll(direction: ScrollDirection): NovaResult<Unit> =
        AccessibilityBridge.scroll(direction)

    override fun pressBack(): NovaResult<Unit> = AccessibilityBridge.pressBack()

    override fun pressHome(): NovaResult<Unit> = AccessibilityBridge.pressHome()

    // A snapshot item has no saved path, so the live screen is searched by position and class.
    private fun targetOf(node: ScreenNode): NodeTarget =
        NodeTarget(path = null, bounds = node.bounds, className = node.className.orEmpty(), viewId = "")

    private fun toSnapshot(capture: ScreenCapture): ScreenSnapshot = ScreenSnapshot(
        packageName = capture.packageName,
        nodes = capture.nodes.map { item ->
            ScreenNode(
                text = item.text.ifBlank { null },
                contentDescription = item.description.ifBlank { null },
                className = item.className.ifBlank { null },
                packageName = capture.packageName,
                isClickable = item.isClickable,
                isEditable = item.isEditable,
                isScrollable = item.isScrollable,
                bounds = item.bounds
            )
        },
        capturedAtMs = capture.capturedAtMs
    )
}
EOF

# ---------- 8. AccessibilityBridge.kt (all P17 and P18 features kept; actions added) ----------
cat > "$BASE/accessibility/AccessibilityBridge.kt" <<'EOF'
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
EOF

# ---------- 9. ActionLab.kt ----------
cat > "$BASE/accessibility/ActionLab.kt" <<'EOF'
package com.nova.ai.accessibility

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.R
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScrollDirection
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The actions the test card can run. */
enum class LabAction { CLICK, TYPE, SCROLL_UP, SCROLL_DOWN, BACK, HOME, RECENTS }

/** The result line shown in the test card. */
data class ActionLabMessage(val text: String, val success: Boolean)

/**
 * Runs the action test independently of any screen, so the countdown keeps going while
 * the user opens another app. The test card reads [waitingSeconds] and [message].
 * Use from the main thread.
 */
object ActionLab {

    private const val COUNTDOWN_SECONDS: Int = 5
    private const val ONE_SECOND_MS: Long = 1000L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null

    /** Seconds left before the action runs; 0 when no countdown is running. */
    var waitingSeconds: Int by mutableStateOf(0)
        private set

    /** The result of the last action. */
    var message: ActionLabMessage? by mutableStateOf<ActionLabMessage?>(null)
        private set

    /** Runs [action]; with [delayed] it first waits 5 seconds so the user can open another app. */
    fun run(context: Context, action: LabAction, query: String, text: String, delayed: Boolean) {
        cancel()
        val appContext: Context = context.applicationContext
        job = scope.launch {
            if (delayed) {
                for (second in COUNTDOWN_SECONDS downTo 1) {
                    waitingSeconds = second
                    delay(ONE_SECOND_MS)
                }
                waitingSeconds = 0
            }
            // Reading and acting talk to the system many times, so they run off the main thread.
            val outcome: NovaResult<String> = withContext(Dispatchers.Default) {
                perform(appContext, action, query.trim(), text)
            }
            message = when (outcome) {
                is NovaResult.Success -> ActionLabMessage(outcome.value, true)
                is NovaResult.Failure -> ActionLabMessage(
                    appContext.getString(R.string.act_failed, outcome.error.message),
                    false
                )
            }
        }
    }

    /** Stops a running countdown. */
    fun cancel() {
        job?.cancel()
        job = null
        waitingSeconds = 0
    }

    private fun perform(context: Context, action: LabAction, query: String, text: String): NovaResult<String> =
        when (action) {
            LabAction.CLICK -> clickByName(context, query)
            LabAction.TYPE -> typeByName(context, query, text)
            LabAction.SCROLL_UP ->
                AccessibilityBridge.scroll(ScrollDirection.UP).map { context.getString(R.string.act_ok_scroll_up) }
            LabAction.SCROLL_DOWN ->
                AccessibilityBridge.scroll(ScrollDirection.DOWN).map { context.getString(R.string.act_ok_scroll_down) }
            LabAction.BACK -> AccessibilityBridge.pressBack().map { context.getString(R.string.act_ok_back) }
            LabAction.HOME -> AccessibilityBridge.pressHome().map { context.getString(R.string.act_ok_home) }
            LabAction.RECENTS -> AccessibilityBridge.openRecents().map { context.getString(R.string.act_ok_recents) }
        }

    private fun clickByName(context: Context, query: String): NovaResult<String> {
        if (query.isEmpty()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, context.getString(R.string.act_need_name))
        }
        val capture: ScreenCapture = when (val read = AccessibilityBridge.readScreen()) {
            is NovaResult.Success -> read.value
            is NovaResult.Failure -> return read
        }
        val node: UiNode = NodeFinder.findBest(capture, query, NodeFinder.Filter.CLICKABLE)
            ?: NodeFinder.findBest(capture, query, NodeFinder.Filter.ANY)
            ?: return NovaResult.failure(ErrorCode.NOT_FOUND, context.getString(R.string.act_not_found, query))

        return AccessibilityBridge.click(node.toTarget())
            .map { context.getString(R.string.act_ok_click, node.label()) }
    }

    private fun typeByName(context: Context, query: String, text: String): NovaResult<String> {
        if (text.isEmpty()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, context.getString(R.string.act_need_text))
        }
        val capture: ScreenCapture = when (val read = AccessibilityBridge.readScreen()) {
            is NovaResult.Success -> read.value
            is NovaResult.Failure -> return read
        }
        val node: UiNode = (
            if (query.isEmpty()) {
                NodeFinder.firstEditable(capture)
            } else {
                NodeFinder.findBest(capture, query, NodeFinder.Filter.EDITABLE)
            }
            ) ?: return NovaResult.failure(ErrorCode.NOT_FOUND, context.getString(R.string.act_no_field))

        val message: String = if (query.isEmpty()) {
            context.getString(R.string.act_ok_type_first)
        } else {
            context.getString(R.string.act_ok_type, node.label())
        }
        return AccessibilityBridge.typeText(node.toTarget(), text, append = false).map { message }
    }
}
EOF

# ---------- 10. ActionLabCard.kt ----------
cat > "$BASE/ui/components/ActionLabCard.kt" <<'EOF'
package com.nova.ai.ui.components

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.accessibility.AccessibilityBridge
import com.nova.ai.accessibility.ActionGate
import com.nova.ai.accessibility.ActionLab
import com.nova.ai.accessibility.ActionLabMessage
import com.nova.ai.accessibility.LabAction

/**
 * Test card for NOVA's hands: click a button by its name, type into a field, scroll,
 * and press Back, Home or recent apps. With the 5-second option the action runs
 * after a countdown, so it can be tested on another app. Also tests the emergency stop.
 */
@Composable
fun ActionLabCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val connected: Boolean = AccessibilityBridge.isConnected
    val waitingSeconds: Int = ActionLab.waitingSeconds
    val message: ActionLabMessage? = ActionLab.message
    val stopped: Boolean = ActionGate.isStopped

    var query: String by rememberSaveable { mutableStateOf("") }
    var typed: String by rememberSaveable { mutableStateOf("") }
    var delayed: Boolean by rememberSaveable { mutableStateOf(false) }

    fun run(action: LabAction) {
        ActionLab.run(context, action, query, typed, delayed)
    }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.act_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.act_note),
                style = MaterialTheme.typography.bodySmall
            )
            if (!connected) {
                Text(
                    text = stringResource(R.string.act_need_service),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }

            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text(stringResource(R.string.act_query_label)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedTextField(
                value = typed,
                onValueChange = { typed = it },
                label = { Text(stringResource(R.string.act_text_label)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.act_delay_label),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f)
                )
                Switch(checked = delayed, onCheckedChange = { delayed = it })
            }

            if (waitingSeconds > 0) {
                Text(text = stringResource(R.string.act_waiting, waitingSeconds))
                OutlinedButton(
                    onClick = { ActionLab.cancel() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.act_cancel))
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = { run(LabAction.CLICK) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_click))
                }
                Button(
                    onClick = { run(LabAction.TYPE) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_type))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { run(LabAction.SCROLL_UP) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_scroll_up))
                }
                OutlinedButton(
                    onClick = { run(LabAction.SCROLL_DOWN) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_scroll_down))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { run(LabAction.BACK) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_back))
                }
                OutlinedButton(
                    onClick = { run(LabAction.HOME) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_home))
                }
                OutlinedButton(
                    onClick = { run(LabAction.RECENTS) },
                    enabled = connected,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.act_recents))
                }
            }

            message?.let { shown ->
                Text(
                    text = (if (shown.success) "✅ " else "⚠️ ") + shown.text,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (shown.success) {
                        MaterialTheme.colorScheme.onSurface
                    } else {
                        MaterialTheme.colorScheme.error
                    }
                )
            }

            Text(
                text = stringResource(R.string.act_stop_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(if (stopped) R.string.act_stop_on else R.string.act_stop_off),
                style = MaterialTheme.typography.bodySmall
            )
            OutlinedButton(
                onClick = { if (stopped) ActionGate.resume() else ActionGate.stop() },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    stringResource(if (stopped) R.string.act_stop_disable else R.string.act_stop_enable)
                )
            }
        }
    }
}
EOF

# ---------- B. PermissionsScreen.kt: two additive lines (idempotent) ----------
if ! grep -q "ActionLabCard" "$PERMISSIONS_FILE"; then
  grep -q '^import com.nova.ai.ui.components.ScreenReadLabCard$' "$PERMISSIONS_FILE" \
    || { echo "ERROR: PermissionsScreen anchor (import) not found" >&2; exit 1; }
  grep -q '^        ScreenReadLabCard()$' "$PERMISSIONS_FILE" \
    || { echo "ERROR: PermissionsScreen anchor (card) not found" >&2; exit 1; }

  cat > "$TMP_DIR/perm_import.txt" <<'EOF'
import com.nova.ai.ui.components.ActionLabCard
EOF
  cat > "$TMP_DIR/perm_card.txt" <<'EOF'
        ActionLabCard()
EOF
  sed -i "/^import com.nova.ai.ui.components.ScreenReadLabCard$/r $TMP_DIR/perm_import.txt" "$PERMISSIONS_FILE"
  sed -i "/^        ScreenReadLabCard()$/r $TMP_DIR/perm_card.txt" "$PERMISSIONS_FILE"
fi
grep -q "^import com.nova.ai.ui.components.ActionLabCard$" "$PERMISSIONS_FILE" || { echo "ERROR: PermissionsScreen edit failed (import)" >&2; exit 1; }
grep -q "^        ActionLabCard()$" "$PERMISSIONS_FILE" || { echo "ERROR: PermissionsScreen edit failed (card)" >&2; exit 1; }

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "P19: click, type, scroll, Back/Home with emergency-stop gate and the real AccessibilityEngine"
git push

echo "P19 files created and pushed."
