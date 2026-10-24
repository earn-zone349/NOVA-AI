#!/usr/bin/env bash
# NOVA AI - Phase 18 FINAL setup script: screen reader.
# Safe to run on a fresh P17 repo, on a repo where an earlier P18 script was already run,
# and safe to run again. All checks happen BEFORE any file is changed.
#
# What it does:
#  - Screen reader with sensitive-field rules (password, PIN, OTP hidden; codes in texts masked).
#  - Text typed by the user in ANY input field is never read (only the field's label is kept).
#  - Reads the screen aloud (Bangla / English) with the app's existing voice engine.
#  - Home card: "read after 5 seconds", "read now", "stop".
#  - Does NOT rewrite AccessibilityBridge or NovaAccessibilityService (nothing from P17 can be lost).
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
HOME_FILE="$BASE/ui/screens/HomeScreen.kt"
PERMISSIONS_FILE="$BASE/ui/screens/PermissionsScreen.kt"

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

# ======================= PREFLIGHT (nothing is changed here) =======================

[ -d ".git" ] || fail "Run this from the repo root (the folder that contains .git)."

for required in \
  "$BASE/accessibility/AccessibilityBridge.kt" \
  "$BASE/accessibility/NovaAccessibilityService.kt" \
  "$BASE/voice/LanguageDetector.kt" \
  "$BASE/core/Models.kt" \
  "$HOME_FILE"; do
  [ -f "$required" ] || fail "$required not found. Run from repo root after P17 is installed."
done

grep -q "fun service()" "$BASE/accessibility/AccessibilityBridge.kt" \
  || fail "AccessibilityBridge has no service() function."
grep -q "isConnected" "$BASE/accessibility/AccessibilityBridge.kt" \
  || fail "AccessibilityBridge has no isConnected value."
grep -rq "NOT_AVAILABLE" "$BASE/core" || fail "ErrorCode.NOT_AVAILABLE not found in core."
grep -rq "EXECUTION_FAILED" "$BASE/core" || fail "ErrorCode.EXECUTION_FAILED not found in core."
grep -rq "class ScreenBounds" "$BASE/core" || fail "ScreenBounds not found in core."
grep -rqE "class Language( |\()" "$BASE/core" || fail "Language enum not found in core."

# Old P18 pieces that this script replaces: PermissionsScreen test card lines.
if [ -f "$PERMISSIONS_FILE" ] && grep -q "ScreenReadLabCard" "$PERMISSIONS_FILE"; then
  grep -q '^import com.nova.ai.ui.components.ScreenReadLabCard$' "$PERMISSIONS_FILE" \
    || fail "PermissionsScreen has an unexpected ScreenReadLabCard import. Send me the file."
  grep -q '^        ScreenReadLabCard()$' "$PERMISSIONS_FILE" \
    || fail "PermissionsScreen has an unexpected ScreenReadLabCard call. Send me the file."
  [ "$(grep -c "ScreenReadLabCard" "$PERMISSIONS_FILE")" = "2" ] \
    || fail "PermissionsScreen has extra ScreenReadLabCard lines. Send me the file."
fi

# HomeScreen: either an earlier P18 wiring is already there (kept as is, it matches),
# or the four anchor lines must exist so the wiring can be added.
if ! grep -q "ScreenReadCard" "$HOME_FILE"; then
  grep -q '^import com.nova.ai.ui.components.MediaActionCard$' "$HOME_FILE" \
    || fail "HomeScreen anchor (import MediaActionCard) not found."
  grep -q '^    val mediaController: MediaCommandController = remember { MediaCommandController(context) }$' "$HOME_FILE" \
    || fail "HomeScreen anchor (mediaController line) not found."
  grep -q '^        MediaActionCard(controller = mediaController)$' "$HOME_FILE" \
    || fail "HomeScreen anchor (MediaActionCard line) not found."
  grep -q '^            systemController.release()$' "$HOME_FILE" \
    || fail "HomeScreen anchor (systemController.release line) not found."
  grep -q "voiceEngine" "$HOME_FILE" || fail "HomeScreen has no voiceEngine."
  grep -q "currentLanguage" "$HOME_FILE" || fail "HomeScreen has no currentLanguage."
  grep -q "scope" "$HOME_FILE" || fail "HomeScreen has no coroutine scope."
else
  grep -q "ScreenReadController" "$HOME_FILE" \
    || fail "HomeScreen mentions ScreenReadCard but not ScreenReadController. Send me the file."
fi

TMP_DIR="$(mktemp -d)"
mkdir -p "$BASE/accessibility" "$BASE/ui/components" app/src/main/res/values

# ======================= A. Remove replaced files =======================

rm -f "$BASE/accessibility/ScreenTreeReader.kt" \
      "$BASE/accessibility/ScreenReadLab.kt" \
      "$BASE/ui/components/ScreenReadLabCard.kt"

if [ -f "$PERMISSIONS_FILE" ] && grep -q "ScreenReadLabCard" "$PERMISSIONS_FILE"; then
  sed -i '/^import com.nova.ai.ui.components.ScreenReadLabCard$/d;/^        ScreenReadLabCard()$/d' "$PERMISSIONS_FILE"
fi

# ======================= B. Strings =======================

cat > app/src/main/res/values/strings_p18.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="scr_title">স্ক্রিন পড়া</string>
    <string name="scr_note">অন্য অ্যাপের স্ক্রিনের লেখা, বাটন ও ইনপুট ঘর পড়ে শোনায়। \"৫ সেকেন্ড পর পড়ো\" চেপে যে অ্যাপের স্ক্রিন পড়াতে চাও সেখানে চলে যাও।</string>
    <string name="scr_privacy">পাসওয়ার্ড, পিন ও OTP-র ঘর লুকানো থাকে। কোনো ঘরে টাইপ করা লেখা কখনো পড়া বা সেভ করা হয় না। পড়া তথ্য ফোনেই থাকে।</string>
    <string name="scr_not_connected">Accessibility সার্ভিস সংযুক্ত নেই। Access ট্যাবে গিয়ে চালু করো।</string>

    <string name="scr_read_delayed">৫ সেকেন্ড পর পড়ো</string>
    <string name="scr_read_now">এখনই পড়ো</string>
    <string name="scr_stop">থামাও</string>
    <string name="scr_waiting">%1$d সেকেন্ড পরে স্ক্রিন পড়া হবে। এখন অন্য অ্যাপে যাও…</string>

    <string name="scr_app">অ্যাপ: %1$s</string>
    <string name="scr_counts">লেখা: %1$d, বাটন: %2$d, ইনপুট ঘর: %3$d</string>
    <string name="scr_stats">মোট উপাদান: %1$d, সময়: %2$d মিলিসেকেন্ড</string>
    <string name="scr_hidden">লুকানো সংবেদনশীল ঘর: %1$d টি</string>
    <string name="scr_screen_truncated">স্ক্রিন অনেক বড়, তাই শুধু প্রথম অংশ পড়া হয়েছে।</string>
    <string name="scr_truncated">লেখা অনেক লম্বা, তাই শুধু শুরুর অংশ বলা হয়েছে।</string>
    <string name="scr_speak_error">বলতে সমস্যা: %1$s</string>

    <string name="scr_texts_title">স্ক্রিনের লেখা</string>
    <string name="scr_buttons_title">বাটন</string>
    <string name="scr_fields_title">ইনপুট ঘর</string>
    <string name="scr_more">…আরও %1$d টি</string>
    <string name="scr_unnamed_fields">নামহীন ইনপুট ঘর: %1$d টি</string>

    <string name="scr_empty">স্ক্রিনে পড়ার মতো কিছু পাওয়া যায়নি। কিছু অ্যাপ (যেমন ব্যাংকিং) স্ক্রিন পড়তে দেয় না।</string>
    <string name="scr_failed">স্ক্রিন পড়তে সমস্যা হয়েছে।</string>

    <string name="scr_intro_texts_bn">স্ক্রিনে লেখা আছে।</string>
    <string name="scr_intro_buttons_bn">স্ক্রিনে এই বাটনগুলো আছে।</string>
    <string name="scr_intro_texts_en">On the screen:</string>
    <string name="scr_intro_buttons_en">Buttons on the screen:</string>
    <string name="scr_speech_hidden_bn">গোপন</string>
    <string name="scr_speech_hidden_en">hidden</string>
</resources>
EOF

# ======================= C. UiNode.kt =======================

cat > "$BASE/accessibility/UiNode.kt" <<'EOF'
package com.nova.ai.accessibility

import com.nova.ai.core.ScreenBounds

/**
 * One item on the screen (a text, button, input field...) as read by the accessibility service.
 * [path] lists the child positions from the top of the screen tree down to this item,
 * so the same item can be found again later (used for clicking in the next phase).
 * Input fields never carry typed text: [text] is always empty for them.
 * Sensitive fields also have an empty [description].
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

# ======================= D. SensitiveNodePolicy.kt =======================

cat > "$BASE/accessibility/SensitiveNodePolicy.kt" <<'EOF'
package com.nova.ai.accessibility

import java.util.Locale

/**
 * Rules that keep secrets out of what NOVA reads: password fields, PIN and OTP
 * fields, and code numbers inside messages. These are best-effort rules based on
 * field names and nearby words; they are tightened in the security phase.
 */
object SensitiveNodePolicy {

    /** What replaces a hidden code number. */
    const val MASK: String = "••••"

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

# ======================= E. ScreenReader.kt =======================

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
EOF

# ======================= F. ScreenSummarizer.kt =======================

cat > "$BASE/accessibility/ScreenSummarizer.kt" <<'EOF'
package com.nova.ai.accessibility

/**
 * What is on the screen, sorted into three groups in reading order
 * (top to bottom, left to right). [unnamedFields] counts input fields without a label.
 */
data class ScreenSummary(
    val texts: List<String>,
    val actions: List<String>,
    val fields: List<String>,
    val unnamedFields: Int
) {
    /** True when nothing readable was found. */
    val isEmpty: Boolean
        get() = texts.isEmpty() && actions.isEmpty() && fields.isEmpty() && unnamedFields == 0
}

/** Text prepared for speaking. [truncated] is true if the end was cut off. */
data class SpeechText(val text: String, val truncated: Boolean)

/** Pure logic (no Android classes), so it is easy to test. */
object ScreenSummarizer {

    /** Speech engines refuse very long text; this keeps a safe margin. */
    const val MAX_SPEECH_CHARS: Int = 1400

    // Items whose tops are closer than this count as one visual row.
    private const val ROW_BUCKET_PX: Int = 40
    // A clickable item with a longer name is really a piece of text (a message row, a link line).
    private const val LONG_NAME_CHARS: Int = 30
    private const val SEPARATOR: String = ". "

    /** Sorts the items of [capture] into texts, buttons and input fields. */
    fun summarize(capture: ScreenCapture): ScreenSummary {
        val ordered: List<UiNode> = capture.nodes.sortedWith(
            compareBy<UiNode>({ it.bounds.top / ROW_BUCKET_PX }, { it.bounds.left })
        )

        val texts: MutableList<String> = ArrayList()
        val actions: MutableList<String> = ArrayList()
        val fields: MutableList<String> = ArrayList()
        var unnamedFields = 0

        for (node in ordered) {
            val name: String = readableName(node)
            when {
                node.isEditable ->
                    if (name.isNotBlank()) fields.add(name) else unnamedFields++
                node.isClickable && node.isEnabled && name.isNotBlank() && name.length <= LONG_NAME_CHARS ->
                    actions.add(name)
                name.isNotBlank() -> texts.add(name)
            }
        }

        return ScreenSummary(
            texts = texts.distinct(),
            actions = actions.distinct(),
            fields = fields.distinct(),
            unnamedFields = unnamedFields
        )
    }

    /** Joins [parts] into one speakable text of at most [maxChars] characters. */
    fun toSpeech(parts: List<String>, maxChars: Int = MAX_SPEECH_CHARS): SpeechText {
        val builder = StringBuilder()
        var truncated = false

        for (part in parts) {
            if (builder.isEmpty()) {
                if (part.length > maxChars) {
                    builder.append(part.take(maxChars))
                    truncated = true
                    break
                }
                builder.append(part)
            } else {
                if (builder.length + SEPARATOR.length + part.length > maxChars) {
                    truncated = true
                    break
                }
                builder.append(SEPARATOR).append(part)
            }
        }
        return SpeechText(builder.toString(), truncated)
    }

    // The visible name of an item: text, else description, else hint (never the short id).
    private fun readableName(node: UiNode): String =
        listOf(node.text, node.description, node.hint).firstOrNull { it.isNotBlank() }.orEmpty()
}
EOF

# ======================= G. ScreenReadController.kt =======================

cat > "$BASE/accessibility/ScreenReadController.kt" <<'EOF'
package com.nova.ai.accessibility

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.R
import com.nova.ai.core.Language
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import com.nova.ai.voice.LanguageDetector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What the screen-reading card shows. */
sealed interface ScreenReadState {
    /** Nothing happening. */
    object Idle : ScreenReadState

    /** Counting down so the user can switch to the app to be read. */
    data class Waiting(val secondsLeft: Int) : ScreenReadState

    /** The screen was read. [speakError] is set if speaking it aloud failed. */
    data class Done(
        val appPackage: String?,
        val nodeCount: Int,
        val durationMs: Long,
        val screenTruncated: Boolean,
        val hiddenSensitive: Int,
        val summary: ScreenSummary,
        val speechTruncated: Boolean,
        val speakError: String?
    ) : ScreenReadState

    /** Reading failed for the reason in [message]. */
    data class Failed(val message: String) : ScreenReadState
}

/**
 * Reads the screen in front and speaks it. Use from the main thread; the heavy
 * work runs on a background dispatcher. Screen content is only held in [state]
 * while the card is open and is never logged or stored.
 *
 * [speak] and [stopSpeaking] are given by the screen (its voice engine), so this
 * class has no dependency on how speech is produced.
 */
class ScreenReadController(
    context: Context,
    private val scope: CoroutineScope,
    private val defaultLanguage: () -> Language,
    private val speak: (String, Language) -> NovaResult<Unit>,
    private val stopSpeaking: () -> Unit
) {

    private val appContext: Context = context.applicationContext
    private var job: Job? = null

    /** What the card should show right now. */
    var state: ScreenReadState by mutableStateOf<ScreenReadState>(ScreenReadState.Idle)
        private set

    /** Waits a few seconds (so the user can open another app), then reads the screen. */
    fun readAfterDelay() {
        job?.cancel()
        job = scope.launch {
            for (secondsLeft in DELAY_SECONDS downTo 1) {
                state = ScreenReadState.Waiting(secondsLeft)
                delay(ONE_SECOND_MS)
            }
            captureAndSpeak()
        }
    }

    /** Reads the screen that is in front at this moment. */
    fun readNow() {
        job?.cancel()
        job = scope.launch { captureAndSpeak() }
    }

    /** Cancels a countdown, stops speaking and clears the card. */
    fun stop() {
        job?.cancel()
        job = null
        stopSpeaking()
        state = ScreenReadState.Idle
    }

    private suspend fun captureAndSpeak() {
        val result: NovaResult<ScreenCapture> = withContext(Dispatchers.Default) {
            ScreenReader.capture()
        }
        if (result is NovaResult.Success) {
            present(result.value)
        } else if (result is NovaResult.Failure) {
            state = ScreenReadState.Failed(
                result.error.message ?: appContext.getString(R.string.scr_failed)
            )
        }
    }

    private fun present(capture: ScreenCapture) {
        val summary: ScreenSummary = ScreenSummarizer.summarize(capture)
        if (summary.isEmpty) {
            state = ScreenReadState.Failed(appContext.getString(R.string.scr_empty))
            return
        }
        // Only counts are logged, never the content.
        NovaLogger.i(
            TAG,
            "Screen read: texts=${summary.texts.size} buttons=${summary.actions.size} " +
                "fields=${summary.fields.size + summary.unnamedFields} hidden=${capture.hiddenSensitiveCount}"
        )

        // Speak the texts; if the screen has none, speak its buttons instead.
        val readTexts: Boolean = summary.texts.isNotEmpty()
        val rawParts: List<String> = if (readTexts) summary.texts else summary.actions

        fun done(speechTruncated: Boolean, speakError: String?): ScreenReadState.Done =
            ScreenReadState.Done(
                appPackage = capture.packageName,
                nodeCount = capture.nodes.size,
                durationMs = capture.durationMs,
                screenTruncated = capture.truncated,
                hiddenSensitive = capture.hiddenSensitiveCount,
                summary = summary,
                speechTruncated = speechTruncated,
                speakError = speakError
            )

        if (rawParts.isEmpty()) {
            state = done(speechTruncated = false, speakError = null)
            return
        }

        val detected: Language = LanguageDetector.detect(rawParts.joinToString(" "))
        val language: Language = if (detected == Language.UNKNOWN) defaultLanguage() else detected
        val english: Boolean = language == Language.ENGLISH

        // A hidden code is spoken as a word instead of the mask symbols.
        val hiddenWord: String = appContext.getString(
            if (english) R.string.scr_speech_hidden_en else R.string.scr_speech_hidden_bn
        )
        val parts: List<String> = rawParts.map { it.replace(SensitiveNodePolicy.MASK, hiddenWord) }

        val speech: SpeechText = ScreenSummarizer.toSpeech(parts)
        val spoken: String = introFor(english, readTexts) + " " + speech.text

        val spoke: NovaResult<Unit> = speak(spoken, language)
        val speakError: String? = if (spoke is NovaResult.Failure) spoke.error.message else null
        state = done(speech.truncated, speakError)
    }

    private fun introFor(english: Boolean, readTexts: Boolean): String {
        val resId: Int = when {
            readTexts && english -> R.string.scr_intro_texts_en
            readTexts -> R.string.scr_intro_texts_bn
            english -> R.string.scr_intro_buttons_en
            else -> R.string.scr_intro_buttons_bn
        }
        return appContext.getString(resId)
    }

    private companion object {
        const val TAG: String = "ScreenReadController"
        const val DELAY_SECONDS: Int = 5
        const val ONE_SECOND_MS: Long = 1_000L
    }
}
EOF

# ======================= H. ScreenReadCard.kt =======================

cat > "$BASE/ui/components/ScreenReadCard.kt" <<'EOF'
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
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.accessibility.AccessibilityBridge
import com.nova.ai.accessibility.ScreenReadController
import com.nova.ai.accessibility.ScreenReadState

private const val MAX_ITEMS_SHOWN: Int = 40

/**
 * Lets the user have the screen in front read aloud and shows what was found:
 * texts, buttons and input fields.
 */
@Composable
fun ScreenReadCard(
    controller: ScreenReadController,
    modifier: Modifier = Modifier
) {
    val connected: Boolean = AccessibilityBridge.isConnected
    val state: ScreenReadState = controller.state

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
                Text(text = "🔐 " + stringResource(R.string.scr_not_connected))
            }

            Button(
                onClick = { controller.readAfterDelay() },
                enabled = connected && state !is ScreenReadState.Waiting,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.scr_read_delayed))
            }
            OutlinedButton(
                onClick = { controller.readNow() },
                enabled = connected,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.scr_read_now))
            }

            when (state) {
                ScreenReadState.Idle -> Unit
                is ScreenReadState.Waiting ->
                    Text(text = stringResource(R.string.scr_waiting, state.secondsLeft))
                is ScreenReadState.Failed -> Text(text = "⚠️ " + state.message)
                is ScreenReadState.Done -> ReportContent(LocalContext.current, state)
            }

            if (state !is ScreenReadState.Idle) {
                TextButton(onClick = { controller.stop() }) {
                    Text(stringResource(R.string.scr_stop))
                }
            }

            Text(
                text = stringResource(R.string.scr_privacy),
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}

@Composable
private fun ReportContent(context: Context, done: ScreenReadState.Done) {
    val summary = done.summary
    val appName: String = remember(done.appPackage) {
        done.appPackage?.let { appLabelOf(context, it) } ?: ""
    }

    if (appName.isNotBlank()) {
        Text(
            text = stringResource(R.string.scr_app, appName),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold
        )
    }
    Text(
        text = stringResource(
            R.string.scr_counts,
            summary.texts.size,
            summary.actions.size,
            summary.fields.size + summary.unnamedFields
        )
    )
    Text(
        text = stringResource(R.string.scr_stats, done.nodeCount, done.durationMs.toInt()),
        style = MaterialTheme.typography.bodySmall
    )
    if (done.hiddenSensitive > 0) {
        Text(
            text = stringResource(R.string.scr_hidden, done.hiddenSensitive),
            style = MaterialTheme.typography.bodySmall
        )
    }
    done.speakError?.let { message ->
        Text(text = "⚠️ " + stringResource(R.string.scr_speak_error, message))
    }
    if (done.screenTruncated) {
        Text(
            text = stringResource(R.string.scr_screen_truncated),
            style = MaterialTheme.typography.bodySmall
        )
    }
    if (done.speechTruncated) {
        Text(
            text = stringResource(R.string.scr_truncated),
            style = MaterialTheme.typography.bodySmall
        )
    }

    ReportSection(stringResource(R.string.scr_texts_title), summary.texts)
    ReportSection(stringResource(R.string.scr_buttons_title), summary.actions)
    ReportSection(stringResource(R.string.scr_fields_title), summary.fields)
    if (summary.unnamedFields > 0) {
        Text(text = stringResource(R.string.scr_unnamed_fields, summary.unnamedFields))
    }
}

@Composable
private fun ReportSection(title: String, items: List<String>) {
    if (items.isEmpty()) return
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold
    )
    items.take(MAX_ITEMS_SHOWN).forEach { item ->
        Text(text = "• $item", style = MaterialTheme.typography.bodyMedium)
    }
    if (items.size > MAX_ITEMS_SHOWN) {
        Text(
            text = stringResource(R.string.scr_more, items.size - MAX_ITEMS_SHOWN),
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

# ======================= I. HomeScreen wiring (only if not already there) =======================

if ! grep -q "ScreenReadCard" "$HOME_FILE"; then
  cat > "$TMP_DIR/home_import.txt" <<'EOF'
import com.nova.ai.ui.components.ScreenReadCard
import com.nova.ai.accessibility.ScreenReadController
EOF
  cat > "$TMP_DIR/home_controller.txt" <<'EOF'

    // Reads the text, buttons and input fields of the screen in front, and speaks them.
    val screenReadController: ScreenReadController = remember {
        ScreenReadController(
            context = context,
            scope = scope,
            defaultLanguage = { currentLanguage.toSpeechLanguage() },
            speak = { text, language -> voiceEngine.speak(text, language) },
            stopSpeaking = { voiceEngine.stopSpeaking() }
        )
    }
EOF
  cat > "$TMP_DIR/home_card.txt" <<'EOF'

        ScreenReadCard(controller = screenReadController)
EOF
  cat > "$TMP_DIR/home_release.txt" <<'EOF'
            screenReadController.stop()
EOF

  sed -i "/^import com.nova.ai.ui.components.MediaActionCard$/r $TMP_DIR/home_import.txt" "$HOME_FILE"
  sed -i "/^    val mediaController: MediaCommandController = remember { MediaCommandController(context) }$/r $TMP_DIR/home_controller.txt" "$HOME_FILE"
  sed -i "/^        MediaActionCard(controller = mediaController)$/r $TMP_DIR/home_card.txt" "$HOME_FILE"
  sed -i "/^            systemController.release()$/r $TMP_DIR/home_release.txt" "$HOME_FILE"
fi

rm -rf "$TMP_DIR"

# ======================= J. Final checks =======================

grep -q "^import com.nova.ai.ui.components.ScreenReadCard$" "$HOME_FILE" || fail "HomeScreen edit failed (card import)."
grep -q "^import com.nova.ai.accessibility.ScreenReadController$" "$HOME_FILE" || fail "HomeScreen edit failed (controller import)."
grep -q "ScreenReadController(" "$HOME_FILE" || fail "HomeScreen edit failed (controller)."
grep -q "ScreenReadCard(controller = screenReadController)" "$HOME_FILE" || fail "HomeScreen edit failed (card)."
grep -q "screenReadController.stop()" "$HOME_FILE" || fail "HomeScreen edit failed (release)."

if grep -rEl "ScreenReadLab|ScreenTreeReader" "$BASE" >/dev/null 2>&1; then
  echo "Files that still mention removed classes:" >&2
  grep -rEl "ScreenReadLab|ScreenTreeReader" "$BASE" >&2
  fail "Old P18 classes are still referenced. Send me those files."
fi

for created in \
  "$BASE/accessibility/UiNode.kt" \
  "$BASE/accessibility/SensitiveNodePolicy.kt" \
  "$BASE/accessibility/ScreenReader.kt" \
  "$BASE/accessibility/ScreenSummarizer.kt" \
  "$BASE/accessibility/ScreenReadController.kt" \
  "$BASE/ui/components/ScreenReadCard.kt" \
  "app/src/main/res/values/strings_p18.xml"; do
  [ -s "$created" ] || fail "$created was not created."
done

# ======================= Commit and push =======================

git add -A
if git diff --cached --quiet; then
  echo "Nothing changed (already up to date)."
else
  git commit -m "P18: screen reader (sensitive fields hidden, typed text never read) with spoken output"
  git push
fi

echo "P18 done. Wait for the GitHub Actions build, install the APK and test the Home card."
