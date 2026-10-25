#!/usr/bin/env bash
# NOVA AI - Phase 18 setup script: screen reader (reads what is visible on the screen).
# Additive: new reader classes and a test card; AccessibilityBridge and the service are
# rewritten with every P17 feature kept; PermissionsScreen gets two additive lines.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
PERMISSIONS_FILE="$BASE/ui/screens/PermissionsScreen.kt"

for required in \
  "$BASE/accessibility/AccessibilityBridge.kt" \
  "$BASE/accessibility/NovaAccessibilityService.kt" \
  "$BASE/ui/components/SetupWizardCard.kt" \
  "$BASE/core/Models.kt" \
  "$PERMISSIONS_FILE"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after P17 is installed." >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"

# ---------- A. New strings file ----------
cat > app/src/main/res/values/strings_p18.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="scr_title">স্ক্রিন পড়ার পরীক্ষা (P18)</string>
    <string name="scr_note">নোভা স্ক্রিনে যা যা দেখা যায় তা পড়ে তালিকা বানায়। পাসওয়ার্ড, পিন ও OTP-জাতীয় ঘরের লেখা লুকানো থাকে। পড়া তথ্য ফোনেই থাকে, কোথাও সংরক্ষণ বা পাঠানো হয় না।</string>
    <string name="scr_need_service">আগে ওপরের সেটআপে Accessibility চালু করো।</string>
    <string name="scr_read_now">এখনকার স্ক্রিন পড়ো (নোভার নিজের)</string>
    <string name="scr_read_later">৫ সেকেন্ড পরে পড়ো (এরপর অন্য অ্যাপ খোলো)</string>
    <string name="scr_waiting">%1$d সেকেন্ড পরে স্ক্রিন পড়া হবে। এখন অন্য একটি অ্যাপ খোলো, তারপর নোভায় ফিরে এসো।</string>
    <string name="scr_cancel">থামাও</string>
    <string name="scr_header">অ্যাপ: %1$s</string>
    <string name="scr_stats">দেখা গেছে: %1$d টি উপাদান, সময়: %2$d মিলিসেকেন্ড</string>
    <string name="scr_truncated">স্ক্রিন বড় হওয়ায় শুধু প্রথম অংশ পড়া হয়েছে।</string>
    <string name="scr_hidden">লুকানো সংবেদনশীল ঘর: %1$d টি</string>
    <string name="scr_texts_title">দেখা লেখা (%1$d)</string>
    <string name="scr_actions_title">ক্লিকযোগ্য (%1$d)</string>
    <string name="scr_fields_title">লেখার ঘর (%1$d)</string>
    <string name="scr_none">কিছু নেই</string>
    <string name="scr_field_empty">(নামহীন ঘর)</string>
    <string name="scr_error">পড়া যায়নি: %1$s</string>
</resources>
EOF

# ---------- 1. UiNode.kt ----------
cat > "$BASE/accessibility/UiNode.kt" <<'EOF'
package com.nova.ai.accessibility

import com.nova.ai.core.ScreenBounds

/**
 * One item on the screen (a text, button, input field...) as read by the accessibility service.
 * [path] lists the child positions from the top of the screen tree down to this item,
 * so the same item can be found again later (used for clicking in the next phase).
 * Sensitive fields have empty [text] and [description].
 */
data class UiNode(
    val id: Int,
    val depth: Int,
    val path: List<Int>,
    val text: String,
    val description: String,
    val hint: String,
    val viewId: String,
    val className: String,
    val bounds: ScreenBounds,
    val isClickable: Boolean,
    val isLongClickable: Boolean,
    val isEditable: Boolean,
    val isScrollable: Boolean,
    val isCheckable: Boolean,
    val isChecked: Boolean,
    val isEnabled: Boolean,
    val isFocused: Boolean,
    val isSensitive: Boolean
) {
    /** The best name for this item: its text, else its description, hint, or short id. */
    fun label(): String =
        listOf(text, description, hint).firstOrNull { it.isNotBlank() }
            ?: viewId.substringAfterLast('/')
}

/** Everything visible on the screen at one moment. */
data class ScreenCapture(
    val packageName: String?,
    val nodes: List<UiNode>,
    val visitedCount: Int,
    val truncated: Boolean,
    val hiddenSensitiveCount: Int,
    val capturedAtMs: Long,
    val durationMs: Long
)
EOF

# ---------- 2. SensitiveNodePolicy.kt ----------
cat > "$BASE/accessibility/SensitiveNodePolicy.kt" <<'EOF'
package com.nova.ai.accessibility

import java.util.Locale

/**
 * Rules that keep secrets out of what NOVA reads: password fields, PIN and OTP
 * fields, and code numbers inside messages. These are best-effort rules based on
 * field names and nearby words; they are tightened in the security phase.
 */
object SensitiveNodePolicy {

    private const val MASK: String = "••••"

    // Whole words only, so "spinner" or "pinterest" do not count as "pin".
    private val FIELD_KEYWORDS: Set<String> = setOf(
        "password", "passcode", "passwd", "pwd", "pin", "otp", "cvv", "cvc", "secret",
        "পাসওয়ার্ড", "পিন", "ওটিপি", "পাসকোড"
    )

    private val WORD_SPLIT: Regex = Regex("[^\\p{L}\\p{N}\\p{M}]+")
    private val CODE_WORDS: Regex = Regex("(?i)(otp|pin|passcode|verification|code|ওটিপি|পিন|কোড|পাসকোড)")
    private val DIGIT_RUN: Regex = Regex("[0-9০-৯]{4,8}")

    /** True if an input field should never be read: password fields and PIN, OTP, CVV style fields. */
    fun isSensitiveField(
        isPassword: Boolean,
        isEditable: Boolean,
        viewId: String,
        hint: String,
        description: String
    ): Boolean {
        if (isPassword) return true
        if (!isEditable) return false
        return listOf(viewId, hint, description).any { source ->
            WORD_SPLIT.split(source.lowercase(Locale.ROOT)).any { word -> word in FIELD_KEYWORDS }
        }
    }

    /** Hides number groups of 4 to 8 digits when the text talks about a code, OTP or PIN. */
    fun maskCodes(text: String): String {
        if (text.isEmpty() || !CODE_WORDS.containsMatchIn(text)) return text
        return DIGIT_RUN.replace(text, MASK)
    }
}
EOF

# ---------- 3. ScreenReader.kt ----------
cat > "$BASE/accessibility/ScreenReader.kt" <<'EOF'
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
 * Nothing that is read is logged or stored.
 */
object ScreenReader {

    private const val TAG: String = "ScreenReader"
    private const val MAX_KEPT_NODES: Int = 600
    private const val MAX_VISITED_NODES: Int = 3000
    private const val MAX_DEPTH: Int = 60
    private const val MAX_TEXT_LENGTH: Int = 200

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
        val rawText: String = node.text?.toString().orEmpty()
        val rawDescription: String = node.contentDescription?.toString().orEmpty()
        val hint: String = node.hintText?.toString().orEmpty()
        val viewId: String = node.viewIdResourceName.orEmpty()
        val editable: Boolean = node.isEditable
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
EOF

# ---------- 4. ScreenSummarizer.kt ----------
cat > "$BASE/accessibility/ScreenSummarizer.kt" <<'EOF'
package com.nova.ai.accessibility

/**
 * A short, readable summary of a screen: the texts, the things that can be clicked,
 * and the input fields, each in top-to-bottom, left-to-right order.
 * A blank entry in [fields] means a field without a name.
 */
data class ScreenSummary(
    val texts: List<String>,
    val actions: List<String>,
    val fields: List<String>
)

/** Builds a [ScreenSummary] from a [ScreenCapture]. Pure logic. */
object ScreenSummarizer {

    fun summarize(capture: ScreenCapture): ScreenSummary {
        val ordered: List<UiNode> = capture.nodes.sortedWith(
            compareBy<UiNode>({ it.bounds.top }, { it.bounds.left })
        )

        val texts: List<String> = ordered
            .filter { !it.isEditable }
            .map { it.text.ifBlank { it.description } }
            .filter { it.isNotBlank() }
            .distinct()

        val actions: List<String> = ordered
            .filter { it.isClickable && it.isEnabled }
            .map { it.label() }
            .filter { it.isNotBlank() }
            .distinct()

        val fields: List<String> = ordered
            .filter { it.isEditable }
            .map { it.label() }

        return ScreenSummary(texts = texts, actions = actions, fields = fields)
    }
}
EOF

# ---------- 5. ScreenReadLab.kt ----------
cat > "$BASE/accessibility/ScreenReadLab.kt" <<'EOF'
package com.nova.ai.accessibility

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.core.NovaResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The result shown in the test card: the raw capture and its summary. */
data class ScreenReadResult(val capture: ScreenCapture, val summary: ScreenSummary)

/**
 * Runs the screen-reading test independently of any screen, so the countdown keeps
 * going while the user opens another app. The test card reads [waitingSeconds],
 * [result] and [errorMessage]. Use from the main thread.
 */
object ScreenReadLab {

    private const val COUNTDOWN_SECONDS: Int = 5
    private const val ONE_SECOND_MS: Long = 1000L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null

    /** Seconds left before the screen is read; 0 when no countdown is running. */
    var waitingSeconds: Int by mutableStateOf(0)
        private set

    /** The last successful reading. */
    var result: ScreenReadResult? by mutableStateOf<ScreenReadResult?>(null)
        private set

    /** The problem of the last reading, if any. */
    var errorMessage: String? by mutableStateOf<String?>(null)
        private set

    /** Reads the screen now. */
    fun readNow() {
        cancel()
        job = scope.launch { readOnce() }
    }

    /** Reads the screen after a short countdown, so the user can open another app first. */
    fun readAfterCountdown() {
        cancel()
        job = scope.launch {
            for (second in COUNTDOWN_SECONDS downTo 1) {
                waitingSeconds = second
                delay(ONE_SECOND_MS)
            }
            waitingSeconds = 0
            readOnce()
        }
    }

    /** Stops a running countdown. */
    fun cancel() {
        job?.cancel()
        job = null
        waitingSeconds = 0
    }

    private suspend fun readOnce() {
        errorMessage = null
        // Reading talks to the system many times, so it runs off the main thread.
        val outcome: NovaResult<ScreenCapture> = withContext(Dispatchers.Default) {
            AccessibilityBridge.readScreen()
        }
        when (outcome) {
            is NovaResult.Success ->
                result = ScreenReadResult(outcome.value, ScreenSummarizer.summarize(outcome.value))
            is NovaResult.Failure -> errorMessage = outcome.error.message
        }
    }
}
EOF

# ---------- 6. AccessibilityBridge.kt (all P17 features kept; screen reading added) ----------
cat > "$BASE/accessibility/AccessibilityBridge.kt" <<'EOF'
package com.nova.ai.accessibility

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
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

    /** Performs a global action such as Home or Back (see AccessibilityService.GLOBAL_ACTION_*). */
    fun performGlobal(action: Int): NovaResult<Unit> {
        val current: NovaAccessibilityService = serviceRef?.get()
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_NOT_CONNECTED)
        return if (current.performGlobalAction(action)) {
            NovaResult.Success(Unit)
        } else {
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "কাজটি করা যায়নি।")
        }
    }

    /** Reads everything visible on the screen now. Blocking: call from a background thread. */
    fun readScreen(): NovaResult<ScreenCapture> {
        val current: NovaAccessibilityService = serviceRef?.get()
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_NOT_CONNECTED)
        return current.readActiveScreen()
    }
}
EOF

# ---------- 7. NovaAccessibilityService.kt (all P17 features kept; screen reading added) ----------
cat > "$BASE/accessibility/NovaAccessibilityService.kt" <<'EOF'
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
EOF

# ---------- 8. ScreenReadLabCard.kt ----------
cat > "$BASE/ui/components/ScreenReadLabCard.kt" <<'EOF'
package com.nova.ai.ui.components

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.accessibility.AccessibilityBridge
import com.nova.ai.accessibility.ScreenReadLab
import com.nova.ai.accessibility.ScreenReadResult

private const val SHOWN_TEXTS: Int = 20
private const val SHOWN_ACTIONS: Int = 12
private const val SHOWN_FIELDS: Int = 8

/**
 * Test card for the screen reader: read NOVA's own screen at once, or read the
 * screen of another app after a 5-second countdown, then see what was found.
 */
@Composable
fun ScreenReadLabCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val connected: Boolean = AccessibilityBridge.isConnected
    val waitingSeconds: Int = ScreenReadLab.waitingSeconds
    val result: ScreenReadResult? = ScreenReadLab.result
    val error: String? = ScreenReadLab.errorMessage

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.scr_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.scr_note),
                style = MaterialTheme.typography.bodySmall
            )

            if (!connected) {
                Text(
                    text = stringResource(R.string.scr_need_service),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }

            Button(
                onClick = { ScreenReadLab.readNow() },
                enabled = connected,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.scr_read_now))
            }

            if (waitingSeconds > 0) {
                Text(text = stringResource(R.string.scr_waiting, waitingSeconds))
                OutlinedButton(
                    onClick = { ScreenReadLab.cancel() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.scr_cancel))
                }
            } else {
                OutlinedButton(
                    onClick = { ScreenReadLab.readAfterCountdown() },
                    enabled = connected,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.scr_read_later))
                }
            }

            error?.let { message ->
                Text(
                    text = stringResource(R.string.scr_error, message),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }

            result?.let { shown -> ScreenReadResultBlock(context, shown) }
        }
    }
}

@Composable
private fun ScreenReadResultBlock(context: Context, shown: ScreenReadResult) {
    val capture = shown.capture
    val summary = shown.summary
    val appName: String = remember(capture.packageName) {
        capture.packageName?.let { appLabelOf(context, it) } ?: ""
    }
    val emptyFieldLabel: String = stringResource(R.string.scr_field_empty)

    Text(
        text = stringResource(R.string.scr_header, appName),
        style = MaterialTheme.typography.titleMedium
    )
    Text(
        text = stringResource(R.string.scr_stats, capture.nodes.size, capture.durationMs.toInt()),
        style = MaterialTheme.typography.bodySmall
    )
    if (capture.truncated) {
        Text(
            text = stringResource(R.string.scr_truncated),
            style = MaterialTheme.typography.bodySmall
        )
    }
    if (capture.hiddenSensitiveCount > 0) {
        Text(
            text = stringResource(R.string.scr_hidden, capture.hiddenSensitiveCount),
            style = MaterialTheme.typography.bodySmall
        )
    }

    ListBlock(
        title = stringResource(R.string.scr_texts_title, summary.texts.size),
        items = summary.texts,
        limit = SHOWN_TEXTS,
        blankLabel = emptyFieldLabel
    )
    ListBlock(
        title = stringResource(R.string.scr_actions_title, summary.actions.size),
        items = summary.actions,
        limit = SHOWN_ACTIONS,
        blankLabel = emptyFieldLabel
    )
    ListBlock(
        title = stringResource(R.string.scr_fields_title, summary.fields.size),
        items = summary.fields,
        limit = SHOWN_FIELDS,
        blankLabel = emptyFieldLabel
    )
}

@Composable
private fun ListBlock(title: String, items: List<String>, limit: Int, blankLabel: String) {
    Text(text = title, style = MaterialTheme.typography.titleMedium)
    if (items.isEmpty()) {
        Text(
            text = stringResource(R.string.scr_none),
            style = MaterialTheme.typography.bodySmall
        )
        return
    }
    items.take(limit).forEach { item ->
        Text(
            text = "• " + item.ifBlank { blankLabel },
            style = MaterialTheme.typography.bodySmall
        )
    }
    if (items.size > limit) {
        Text(
            text = "… +${items.size - limit}",
            style = MaterialTheme.typography.bodySmall
        )
    }
}

/** The name of an installed app, or its package name if the name cannot be read. */
@Suppress("DEPRECATION")
private fun appLabelOf(context: Context, packageName: String): String = try {
    val manager = context.packageManager
    manager.getApplicationLabel(manager.getApplicationInfo(packageName, 0)).toString()
} catch (e: Exception) {
    packageName
}
EOF

# ---------- B. PermissionsScreen.kt: two additive lines (idempotent) ----------
if ! grep -q "ScreenReadLabCard" "$PERMISSIONS_FILE"; then
  grep -q '^import com.nova.ai.ui.components.SetupWizardCard$' "$PERMISSIONS_FILE" \
    || { echo "ERROR: PermissionsScreen anchor (import) not found" >&2; exit 1; }
  grep -q '^        SetupWizardCard()$' "$PERMISSIONS_FILE" \
    || { echo "ERROR: PermissionsScreen anchor (card) not found" >&2; exit 1; }

  cat > "$TMP_DIR/perm_import.txt" <<'EOF'
import com.nova.ai.ui.components.ScreenReadLabCard
EOF
  cat > "$TMP_DIR/perm_card.txt" <<'EOF'
        ScreenReadLabCard()
EOF
  sed -i "/^import com.nova.ai.ui.components.SetupWizardCard$/r $TMP_DIR/perm_import.txt" "$PERMISSIONS_FILE"
  sed -i "/^        SetupWizardCard()$/r $TMP_DIR/perm_card.txt" "$PERMISSIONS_FILE"
fi
grep -q "^import com.nova.ai.ui.components.ScreenReadLabCard$" "$PERMISSIONS_FILE" || { echo "ERROR: PermissionsScreen edit failed (import)" >&2; exit 1; }
grep -q "^        ScreenReadLabCard()$" "$PERMISSIONS_FILE" || { echo "ERROR: PermissionsScreen edit failed (card)" >&2; exit 1; }

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "P18: screen reader (visible items, sensitive fields hidden) and test card"
git push

echo "P18 files created and pushed."
