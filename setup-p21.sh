#!/usr/bin/env bash
# NOVA AI - Phase 21 setup script: the verification engine (did the step really work?).
# Additive: new verification classes; ActionLab and ActionLabCard are rewritten with every
# P19 and P20 feature kept; ScreenNode gets one optional field (isChecked) and the engine fills it.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
MODELS_FILE="$BASE/core/Models.kt"
ENGINE_FILE="$BASE/accessibility/NovaAccessibilityEngine.kt"

for required in \
  "$BASE/verification/VerificationEngine.kt" \
  "$BASE/accessibility/AccessibilityEngine.kt" \
  "$BASE/accessibility/SensitiveNodePolicy.kt" \
  "$BASE/accessibility/GestureActions.kt" \
  "$BASE/accessibility/ActionLab.kt" \
  "$BASE/ui/components/ActionLabCard.kt" \
  "$MODELS_FILE" "$ENGINE_FILE"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after P20 is installed." >&2
    exit 1
  fi
done

# Stop early if the two small edits below cannot be placed.
if ! grep -q "val isChecked: Boolean = false" "$MODELS_FILE"; then
  [ "$(grep -c '^    val bounds: ScreenBounds$' "$MODELS_FILE")" = "1" ] \
    || { echo "ERROR: Models.kt anchor not found" >&2; exit 1; }
fi
if ! grep -q "isChecked = item.isChecked" "$ENGINE_FILE"; then
  [ "$(grep -c '^                bounds = item.bounds$' "$ENGINE_FILE")" = "1" ] \
    || { echo "ERROR: NovaAccessibilityEngine anchor not found" >&2; exit 1; }
fi

# ---------- A. New strings file ----------
cat > app/src/main/res/values/strings_p21.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="ver_label">কাজের পর স্ক্রিন দেখে যাচাই করো (ক্লিক, লেখা, স্ক্রল, Back, Home)</string>
    <string name="ver_ok">%1$s (যাচাই: %2$s)</string>
</resources>
EOF

# ---------- 1. ScreenDiff.kt ----------
cat > "$BASE/verification/ScreenDiff.kt" <<'EOF'
package com.nova.ai.verification

import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot

/**
 * Compares two screen snapshots. Plain logic with no Android classes, so it can be tested
 * without a phone. A node is described by its class, texts, place and checked state; clocks
 * and timers are left out, because they change by themselves and would hide a failed click.
 */
internal object ScreenDiff {

    // Times such as 10:52, 7:05 PM or 01:02:03, in English or Bangla digits.
    private val CLOCK_TEXT: Regex =
        Regex("^\\p{Nd}{1,2}[:.]\\p{Nd}{2}([:.]\\p{Nd}{2})?\\s*([AaPp][Mm])?$")

    /** How many nodes appear in only one of the two snapshots (0 means the screens look the same). */
    fun changedNodeCount(before: ScreenSnapshot, after: ScreenSnapshot): Int {
        val beforeCounts: Map<String, Int> = countsOf(before)
        val afterCounts: Map<String, Int> = countsOf(after)
        var changed = 0
        for (key in beforeCounts.keys + afterCounts.keys) {
            val left: Int = beforeCounts[key] ?: 0
            val right: Int = afterCounts[key] ?: 0
            changed += if (left > right) left - right else right - left
        }
        return changed
    }

    /** True if the app in front is a different one. Unknown packages are never called different. */
    fun packageChanged(before: ScreenSnapshot, after: ScreenSnapshot): Boolean {
        val oldPackage: String = before.packageName ?: return false
        val newPackage: String = after.packageName ?: return false
        return oldPackage != newPackage
    }

    private fun countsOf(snapshot: ScreenSnapshot): Map<String, Int> {
        val counts = HashMap<String, Int>()
        for (node in snapshot.nodes) {
            if (isVolatile(node)) continue
            val key: String = signatureOf(node)
            counts[key] = (counts[key] ?: 0) + 1
        }
        return counts
    }

    private fun signatureOf(node: ScreenNode): String = buildString {
        append(node.className.orEmpty()).append('|')
        append(node.text.orEmpty()).append('|')
        append(node.contentDescription.orEmpty()).append('|')
        append(node.bounds.left).append(',').append(node.bounds.top).append(',')
        append(node.bounds.right).append(',').append(node.bounds.bottom).append('|')
        append(node.isChecked)
    }

    private fun isVolatile(node: ScreenNode): Boolean {
        val label: String = (node.text ?: node.contentDescription).orEmpty().trim()
        return label.isNotEmpty() && CLOCK_TEXT.matches(label)
    }
}
EOF

# ---------- 2. ScreenVerificationEngine.kt ----------
cat > "$BASE/verification/ScreenVerificationEngine.kt" <<'EOF'
package com.nova.ai.verification

import com.nova.ai.accessibility.SensitiveNodePolicy
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.StepAction
import com.nova.ai.core.TaskStep
import com.nova.ai.core.VerificationReport
import com.nova.ai.logging.NovaLogger

/**
 * The real [VerificationEngine]. After a step it looks at the screen again and decides whether
 * the step really did something: a click, scroll, Back, Home or app start must change the screen,
 * and typed text must show up in a text field. Texts of the screen are never logged.
 *
 * Limit: a step that changes nothing visible (for example a click on a button that only
 * plays a sound) is reported as not verified. The caller decides what to do with that.
 */
class ScreenVerificationEngine : VerificationEngine {

    override fun verify(
        step: TaskStep,
        before: ScreenSnapshot?,
        after: ScreenSnapshot?
    ): NovaResult<VerificationReport> = try {
        NovaResult.Success(decide(step, before, after))
    } catch (e: Exception) {
        NovaLogger.e(TAG, "Verification failed", e)
        NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_UNEXPECTED, e)
    }

    private fun decide(step: TaskStep, before: ScreenSnapshot?, after: ScreenSnapshot?): VerificationReport {
        if (after == null) return report(step, false, MSG_NO_AFTER)
        return when (step.action) {
            StepAction.CLICK, StepAction.SCROLL, StepAction.BACK, StepAction.HOME ->
                expectChange(step, before, after, MSG_SCREEN_CHANGED, MSG_SCREEN_SAME)
            StepAction.OPEN_APP -> expectChange(step, before, after, MSG_APP_OPENED, MSG_APP_SAME)
            StepAction.TYPE_TEXT -> expectText(step, after)
            StepAction.WAIT, StepAction.CONFIRM, StepAction.SPEAK ->
                report(step, true, MSG_NOTHING_TO_CHECK)
        }
    }

    private fun expectChange(
        step: TaskStep,
        before: ScreenSnapshot?,
        after: ScreenSnapshot,
        passedMessage: String,
        failedMessage: String
    ): VerificationReport {
        if (before == null) return report(step, false, MSG_NO_BEFORE)
        val changed: Boolean = ScreenDiff.packageChanged(before, after) ||
            ScreenDiff.changedNodeCount(before, after) >= MIN_CHANGED_NODES
        return if (changed) report(step, true, passedMessage) else report(step, false, failedMessage)
    }

    private fun expectText(step: TaskStep, after: ScreenSnapshot): VerificationReport {
        val value: String = step.value.orEmpty()
        if (value.isBlank()) return report(step, false, MSG_NO_TEXT)
        // The screen reader hides code-like digits, so the expected text is hidden the same way.
        val expected: String = tidy(SensitiveNodePolicy.maskCodes(value))
        val found: Boolean = after.nodes.any { node -> isFieldWith(node, expected) }
        return if (found) report(step, true, MSG_TEXT_FOUND) else report(step, false, MSG_TEXT_MISSING)
    }

    private fun isFieldWith(node: ScreenNode, expected: String): Boolean =
        node.isEditable && tidy(node.text.orEmpty()).contains(expected)

    private fun tidy(text: String): String = text.trim().replace(WHITESPACE, " ")

    private fun report(step: TaskStep, passed: Boolean, detail: String): VerificationReport =
        VerificationReport(stepId = step.id, passed = passed, detail = detail)

    private companion object {
        const val TAG: String = "ScreenVerification"
        const val MIN_CHANGED_NODES: Int = 1
        val WHITESPACE: Regex = Regex("\\s+")

        const val MSG_NO_AFTER: String = "কাজের পরের স্ক্রিন পড়া যায়নি, তাই যাচাই করা গেল না।"
        const val MSG_NO_BEFORE: String = "কাজের আগের স্ক্রিন পড়া যায়নি, তাই যাচাই করা গেল না।"
        const val MSG_SCREEN_CHANGED: String = "স্ক্রিন বদলেছে।"
        const val MSG_SCREEN_SAME: String = "স্ক্রিন বদলায়নি। কাজটা হয়নি বলে মনে হচ্ছে।"
        const val MSG_APP_OPENED: String = "অ্যাপ খুলেছে।"
        const val MSG_APP_SAME: String = "অ্যাপ খোলার কোনো চিহ্ন দেখা যায়নি।"
        const val MSG_TEXT_FOUND: String = "লেখাটা ঘরে দেখা যাচ্ছে।"
        const val MSG_TEXT_MISSING: String = "লেখাটা কোনো ঘরে দেখা গেল না।"
        const val MSG_NO_TEXT: String = "কী লেখার কথা তা জানা নেই।"
        const val MSG_NOTHING_TO_CHECK: String = "এই ধাপে যাচাই করার কিছু নেই।"
        const val MSG_UNEXPECTED: String = "যাচাই করতে সমস্যা হয়েছে।"
    }
}
EOF

# ---------- 3. VerifiedStepRunner.kt ----------
cat > "$BASE/verification/VerifiedStepRunner.kt" <<'EOF'
package com.nova.ai.verification

import com.nova.ai.accessibility.AccessibilityEngine
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenSnapshot
import com.nova.ai.core.TaskStep
import com.nova.ai.core.VerificationReport
import com.nova.ai.logging.NovaLogger

/**
 * Runs one step and then checks that it worked: it reads the screen before, performs the
 * action, and keeps looking at the screen (a screen can take a moment to change) until the
 * [verifier] is satisfied or the time is up. Blocking: call from a background thread.
 *
 * If the action itself fails, that failure is handed back unchanged. If the action went
 * through but the screen did not show it, a [VerificationReport] with `passed = false` is returned.
 */
class VerifiedStepRunner(
    private val screen: AccessibilityEngine,
    private val verifier: VerificationEngine = ScreenVerificationEngine(),
    private val sleep: (Long) -> Unit = { millis -> Thread.sleep(millis) }
) {

    /** Performs [action] for [step] and verifies the result. */
    fun run(step: TaskStep, action: () -> NovaResult<Unit>): NovaResult<VerificationReport> {
        return try {
            val before: ScreenSnapshot? = screen.captureScreen().getOrNull()

            val outcome: NovaResult<Unit> = action()
            if (outcome is NovaResult.Failure) return outcome

            var last: VerificationReport = verifyOnce(step, before)
            var attempt = 1
            while (!last.passed && attempt < MAX_ATTEMPTS) {
                sleep(RETRY_DELAY_MS)
                last = verifyOnce(step, before)
                attempt += 1
            }
            NovaResult.Success(last)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            NovaResult.failure(ErrorCode.CANCELLED, MSG_CANCELLED, e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Verified step failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_UNEXPECTED, e)
        }
    }

    // Looks at the screen now and asks the verifier. A screen that cannot be read counts as unknown.
    private fun verifyOnce(step: TaskStep, before: ScreenSnapshot?): VerificationReport {
        val after: ScreenSnapshot? = screen.captureScreen().getOrNull()
        return when (val verdict = verifier.verify(step, before, after)) {
            is NovaResult.Success -> verdict.value
            is NovaResult.Failure -> VerificationReport(step.id, false, verdict.error.message)
        }
    }

    private companion object {
        const val TAG: String = "VerifiedStepRunner"
        // The first look comes right after the action, then up to 7 more, 400 ms apart (about 3 seconds).
        const val MAX_ATTEMPTS: Int = 8
        const val RETRY_DELAY_MS: Long = 400L

        const val MSG_CANCELLED: String = "যাচাই থামানো হয়েছে।"
        const val MSG_UNEXPECTED: String = "কাজ ও যাচাই করতে সমস্যা হয়েছে।"
    }
}
EOF

# ---------- 4. ActionLab.kt (all P19 and P20 actions kept; optional check added) ----------
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
import com.nova.ai.core.StepAction
import com.nova.ai.core.TaskStep
import com.nova.ai.verification.VerifiedStepRunner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The actions the test card can run. */
enum class LabAction {
    CLICK, TYPE, SCROLL_UP, SCROLL_DOWN, BACK, HOME, RECENTS,
    SWIPE_UP, SWIPE_DOWN, SWIPE_LEFT, SWIPE_RIGHT,
    LONG_PRESS, DOUBLE_TAP, PINCH_OUT, PINCH_IN, TWO_FINGER_UP, TWO_FINGER_DOWN
}

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

    /**
     * Runs [action]; with [delayed] it first waits 5 seconds so the user can open another app.
     * With [verify] a click, typing, scroll, Back or Home is checked afterwards: the screen must
     * show that it worked, otherwise the result line says it failed.
     */
    fun run(
        context: Context,
        action: LabAction,
        query: String,
        text: String,
        delayed: Boolean,
        verify: Boolean = false
    ) {
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
                perform(appContext, action, query.trim(), text, verify)
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

    private fun perform(
        context: Context,
        action: LabAction,
        query: String,
        text: String,
        verify: Boolean
    ): NovaResult<String> =
        when (action) {
            LabAction.CLICK -> clickByName(context, query, verify)
            LabAction.TYPE -> typeByName(context, query, text, verify)
            LabAction.SCROLL_UP -> checked(
                context, verify, TaskStep("lab-scroll-up", StepAction.SCROLL, value = "UP"),
                context.getString(R.string.act_ok_scroll_up)
            ) { AccessibilityBridge.scroll(ScrollDirection.UP) }
            LabAction.SCROLL_DOWN -> checked(
                context, verify, TaskStep("lab-scroll-down", StepAction.SCROLL, value = "DOWN"),
                context.getString(R.string.act_ok_scroll_down)
            ) { AccessibilityBridge.scroll(ScrollDirection.DOWN) }
            LabAction.BACK -> checked(
                context, verify, TaskStep("lab-back", StepAction.BACK),
                context.getString(R.string.act_ok_back)
            ) { AccessibilityBridge.pressBack() }
            LabAction.HOME -> checked(
                context, verify, TaskStep("lab-home", StepAction.HOME),
                context.getString(R.string.act_ok_home)
            ) { AccessibilityBridge.pressHome() }
            LabAction.RECENTS -> AccessibilityBridge.openRecents().map { context.getString(R.string.act_ok_recents) }
            LabAction.SWIPE_UP ->
                AccessibilityBridge.swipe(SwipeDirection.UP).map { context.getString(R.string.gst_ok_swipe_up) }
            LabAction.SWIPE_DOWN ->
                AccessibilityBridge.swipe(SwipeDirection.DOWN).map { context.getString(R.string.gst_ok_swipe_down) }
            LabAction.SWIPE_LEFT ->
                AccessibilityBridge.swipe(SwipeDirection.LEFT).map { context.getString(R.string.gst_ok_swipe_left) }
            LabAction.SWIPE_RIGHT ->
                AccessibilityBridge.swipe(SwipeDirection.RIGHT).map { context.getString(R.string.gst_ok_swipe_right) }
            LabAction.LONG_PRESS -> longPressByName(context, query)
            LabAction.DOUBLE_TAP -> doubleTapByName(context, query)
            LabAction.PINCH_OUT ->
                AccessibilityBridge.pinch(PinchMode.OUT).map { context.getString(R.string.gst_ok_pinch_out) }
            LabAction.PINCH_IN ->
                AccessibilityBridge.pinch(PinchMode.IN).map { context.getString(R.string.gst_ok_pinch_in) }
            LabAction.TWO_FINGER_UP ->
                AccessibilityBridge.twoFingerSwipe(SwipeDirection.UP).map { context.getString(R.string.gst_ok_two_up) }
            LabAction.TWO_FINGER_DOWN ->
                AccessibilityBridge.twoFingerSwipe(SwipeDirection.DOWN).map { context.getString(R.string.gst_ok_two_down) }
        }

    // Reads the screen and finds the item that best matches [query] (clickable ones first).
    private fun findNodeByName(context: Context, query: String): NovaResult<UiNode> {
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
        return NovaResult.Success(node)
    }

    private fun clickByName(context: Context, query: String, verify: Boolean): NovaResult<String> {
        val node: UiNode = when (val found = findNodeByName(context, query)) {
            is NovaResult.Success -> found.value
            is NovaResult.Failure -> return found
        }
        return checked(
            context, verify, TaskStep("lab-click", StepAction.CLICK, target = node.label()),
            context.getString(R.string.act_ok_click, node.label())
        ) { AccessibilityBridge.click(node.toTarget()) }
    }

    // Runs [action]. With [verify] the screen is checked afterwards and a step that did not show
    // any effect becomes a failure that says so; without it the action result is used as it is.
    private fun checked(
        context: Context,
        verify: Boolean,
        step: TaskStep,
        okMessage: String,
        action: () -> NovaResult<Unit>
    ): NovaResult<String> {
        if (!verify) return action().map { okMessage }
        return when (val outcome = VerifiedStepRunner(NovaAccessibilityEngine()).run(step, action)) {
            is NovaResult.Failure -> outcome
            is NovaResult.Success ->
                if (outcome.value.passed) {
                    NovaResult.Success(context.getString(R.string.ver_ok, okMessage, outcome.value.detail))
                } else {
                    NovaResult.failure(ErrorCode.EXECUTION_FAILED, outcome.value.detail)
                }
        }
    }

    private fun longPressByName(context: Context, query: String): NovaResult<String> {
        val node: UiNode = when (val found = findNodeByName(context, query)) {
            is NovaResult.Success -> found.value
            is NovaResult.Failure -> return found
        }
        return AccessibilityBridge.longPress(node.toTarget())
            .map { context.getString(R.string.gst_ok_long_press, node.label()) }
    }

    private fun doubleTapByName(context: Context, query: String): NovaResult<String> {
        val node: UiNode = when (val found = findNodeByName(context, query)) {
            is NovaResult.Success -> found.value
            is NovaResult.Failure -> return found
        }
        return AccessibilityBridge.doubleTap(node.toTarget())
            .map { context.getString(R.string.gst_ok_double_tap, node.label()) }
    }

    private fun typeByName(context: Context, query: String, text: String, verify: Boolean): NovaResult<String> {
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
        return checked(
            context, verify, TaskStep("lab-type", StepAction.TYPE_TEXT, target = node.label(), value = text),
            message
        ) { AccessibilityBridge.typeText(node.toTarget(), text, append = false) }
    }
}
EOF

# ---------- 5. ActionLabCard.kt (all buttons kept; check switch added) ----------
cat > "$BASE/ui/components/ActionLabCard.kt" <<'EOF'
package com.nova.ai.ui.components

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
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
 * press Back, Home or recent apps, and make finger gestures (swipe, long press, double tap,
 * pinch, two-finger swipe). With the 5-second option the action runs after a countdown,
 * so it can be tested on another app. With the check option, a click, typing, scroll, Back or
 * Home is verified on the screen afterwards. Also tests the emergency stop.
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
    var verify: Boolean by rememberSaveable { mutableStateOf(false) }

    fun run(action: LabAction) {
        ActionLab.run(context, action, query, typed, delayed, verify)
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

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.ver_label),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f)
                )
                Switch(checked = verify, onCheckedChange = { verify = it })
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

            Text(
                text = stringResource(R.string.gst_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.gst_note),
                style = MaterialTheme.typography.bodySmall
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_swipe_up, connected) { run(LabAction.SWIPE_UP) }
                GestureButton(R.string.gst_swipe_down, connected) { run(LabAction.SWIPE_DOWN) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_swipe_left, connected) { run(LabAction.SWIPE_LEFT) }
                GestureButton(R.string.gst_swipe_right, connected) { run(LabAction.SWIPE_RIGHT) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_long_press, connected) { run(LabAction.LONG_PRESS) }
                GestureButton(R.string.gst_double_tap, connected) { run(LabAction.DOUBLE_TAP) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_pinch_out, connected) { run(LabAction.PINCH_OUT) }
                GestureButton(R.string.gst_pinch_in, connected) { run(LabAction.PINCH_IN) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GestureButton(R.string.gst_two_up, connected) { run(LabAction.TWO_FINGER_UP) }
                GestureButton(R.string.gst_two_down, connected) { run(LabAction.TWO_FINGER_DOWN) }
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

// One equally wide gesture button inside a row of the test card.
@Composable
private fun RowScope.GestureButton(label: Int, enabled: Boolean, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.weight(1f)
    ) {
        Text(stringResource(label))
    }
}
EOF

# ---------- B. Models.kt: ScreenNode gets an optional isChecked field (idempotent) ----------
# A switch that is turned on or off changes only this flag, so a toggle click can be verified.
if ! grep -q "val isChecked: Boolean = false" "$MODELS_FILE"; then
  sed -i 's/^    val bounds: ScreenBounds$/    val bounds: ScreenBounds,\n    val isChecked: Boolean = false/' "$MODELS_FILE"
fi
grep -q "val isChecked: Boolean = false" "$MODELS_FILE" || { echo "ERROR: Models.kt edit failed" >&2; exit 1; }

# ---------- C. NovaAccessibilityEngine.kt: fill isChecked (idempotent) ----------
if ! grep -q "isChecked = item.isChecked" "$ENGINE_FILE"; then
  sed -i 's/^                bounds = item.bounds$/                bounds = item.bounds,\n                isChecked = item.isChecked/' "$ENGINE_FILE"
fi
grep -q "isChecked = item.isChecked" "$ENGINE_FILE" || { echo "ERROR: NovaAccessibilityEngine edit failed" >&2; exit 1; }

# ---------- Commit and push ----------
git add -A
if git diff --cached --quiet; then
  echo "Nothing new to commit."
else
  git commit -m "P21: verification engine (screen change and typed-text checks) with an optional check in the test card"
  git push
fi

echo "P21 files created and pushed."
