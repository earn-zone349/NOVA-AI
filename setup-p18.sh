#!/usr/bin/env bash
# NOVA AI - Phase 18 setup script: screen reader (Accessibility tree: texts, buttons, input fields).
# Additive: new classes in the accessibility package, one new Home card, new strings file.
# HomeScreen gets a few additive lines only. Nothing from P1 to P17 is removed.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
HOME_FILE="$BASE/ui/screens/HomeScreen.kt"

for required in \
  "$BASE/accessibility/AccessibilityBridge.kt" \
  "$BASE/accessibility/NovaAccessibilityService.kt" \
  "$BASE/setup/SetupChecker.kt" \
  "$BASE/voice/LanguageDetector.kt" \
  "$BASE/voice/LanguageMapping.kt" \
  "$BASE/ui/components/SetupReminderCard.kt" \
  "$HOME_FILE"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after P1 to P17 are installed." >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
mkdir -p "$BASE/accessibility" "$BASE/ui/components" app/src/main/res/values

# ---------- A. New strings file ----------
cat > app/src/main/res/values/strings_p18.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="scr_title">স্ক্রিন পড়া</string>
    <string name="scr_note">অন্য অ্যাপের স্ক্রিনের লেখা, বাটন ও ইনপুট ঘর পড়ে শোনায়। \"৫ সেকেন্ড পর পড়ো\" চেপে যে অ্যাপের স্ক্রিন পড়াতে চাও সেখানে চলে যাও।</string>
    <string name="scr_privacy">পাসওয়ার্ড ঘর এবং ঘরে টাইপ করা লেখা কখনো পড়া বা সেভ করা হয় না।</string>
    <string name="scr_not_connected">Accessibility সার্ভিস সংযুক্ত নেই। Access ট্যাবে গিয়ে চালু করো।</string>

    <string name="scr_read_delayed">৫ সেকেন্ড পর পড়ো</string>
    <string name="scr_read_now">এখনই পড়ো</string>
    <string name="scr_stop">থামাও</string>
    <string name="scr_waiting">%1$d সেকেন্ড পরে স্ক্রিন পড়া হবে। এখন অন্য অ্যাপে যাও…</string>

    <string name="scr_counts">লেখা: %1$d, বাটন: %2$d, ইনপুট ঘর: %3$d</string>
    <string name="scr_texts_title">স্ক্রিনের লেখা</string>
    <string name="scr_buttons_title">বাটন</string>
    <string name="scr_fields_title">ইনপুট ঘর</string>
    <string name="scr_more">…আরও %1$d টি</string>
    <string name="scr_unnamed_fields">নামহীন ইনপুট ঘর: %1$d টি</string>
    <string name="scr_truncated">লেখা অনেক লম্বা, তাই শুধু শুরুর অংশ বলা হয়েছে।</string>
    <string name="scr_speak_error">বলতে সমস্যা: %1$s</string>

    <string name="scr_empty">স্ক্রিনে পড়ার মতো কিছু পাওয়া যায়নি। কিছু অ্যাপ (যেমন ব্যাংকিং) স্ক্রিন পড়তে দেয় না।</string>
    <string name="scr_failed">স্ক্রিন পড়তে সমস্যা হয়েছে।</string>

    <string name="scr_intro_texts_bn">স্ক্রিনে লেখা আছে।</string>
    <string name="scr_intro_buttons_bn">স্ক্রিনে এই বাটনগুলো আছে।</string>
    <string name="scr_intro_texts_en">On the screen:</string>
    <string name="scr_intro_buttons_en">Buttons on the screen:</string>
</resources>
EOF

# ---------- B. Reads the Accessibility tree into plain data ----------
cat > "$BASE/accessibility/ScreenTreeReader.kt" <<'EOF'
package com.nova.ai.accessibility

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo
import com.nova.ai.core.ScreenBounds
import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot

/**
 * Walks the Accessibility tree of one window and turns it into plain [ScreenNode] data.
 *
 * Privacy rules (kept on purpose, later phases rely on them):
 *  - Password fields never give out any text.
 *  - Input fields never give out what the user typed. Only their label (hint or
 *    description) is kept, so NOVA can find the field without reading its content.
 *  - Nothing read here is logged or stored.
 *
 * The walk is limited in depth and node count, so a huge or broken screen cannot
 * freeze the app.
 */
object ScreenTreeReader {

    /** Most nodes kept from one screen. */
    const val MAX_NODES: Int = 400

    private const val MAX_DEPTH: Int = 40
    private const val MAX_LABEL_LENGTH: Int = 300
    private val WHITESPACE: Regex = Regex("\\s+")

    /** Reads the tree below [root]. The caller owns [root] and must recycle it. */
    fun read(root: AccessibilityNodeInfo, capturedAtMs: Long): ScreenSnapshot {
        val nodes: MutableList<ScreenNode> = ArrayList()
        walk(root, 0, nodes)
        return ScreenSnapshot(
            packageName = root.packageName?.toString(),
            nodes = nodes,
            capturedAtMs = capturedAtMs
        )
    }

    private fun walk(node: AccessibilityNodeInfo, depth: Int, out: MutableList<ScreenNode>) {
        if (out.size >= MAX_NODES || depth > MAX_DEPTH) return
        // Parts of the screen the user cannot see are not read.
        if (!node.isVisibleToUser) return

        toScreenNode(node)?.let { out.add(it) }

        for (index in 0 until node.childCount) {
            if (out.size >= MAX_NODES) break
            val child: AccessibilityNodeInfo = node.getChild(index) ?: continue
            try {
                walk(child, depth + 1, out)
            } finally {
                recycleQuietly(child)
            }
        }
    }

    /** Returns null for nodes that carry nothing useful (empty layout containers). */
    private fun toScreenNode(node: AccessibilityNodeInfo): ScreenNode? {
        val isSecret: Boolean = node.isPassword
        val isField: Boolean = node.isEditable

        val label: String? = when {
            isSecret -> null
            isField -> clean(node.hintText) ?: clean(node.contentDescription)
            else -> clean(node.text)
        }
        val description: String? = when {
            isSecret || isField -> null
            else -> clean(node.contentDescription)
        }

        val isUseful: Boolean = label != null || description != null ||
            node.isClickable || isField || node.isScrollable
        if (!isUseful) return null

        val rect = Rect()
        node.getBoundsInScreen(rect)
        if (rect.isEmpty) return null

        return ScreenNode(
            // For input fields the label travels in the description slot (never the typed text).
            text = if (isField) null else label,
            contentDescription = if (isField) label else description,
            className = node.className?.toString(),
            packageName = node.packageName?.toString(),
            isClickable = node.isClickable,
            isEditable = isField,
            isScrollable = node.isScrollable,
            bounds = ScreenBounds(rect.left, rect.top, rect.right, rect.bottom)
        )
    }

    private fun clean(value: CharSequence?): String? {
        val trimmed: String = value?.toString()?.replace(WHITESPACE, " ")?.trim() ?: return null
        return if (trimmed.isEmpty()) null else trimmed.take(MAX_LABEL_LENGTH)
    }

    @Suppress("DEPRECATION")
    private fun recycleQuietly(node: AccessibilityNodeInfo) {
        try {
            node.recycle()
        } catch (e: Exception) {
            // Recycling is only a memory courtesy; a failure here is harmless.
        }
    }
}
EOF

# ---------- C. Turns a snapshot into texts, buttons and fields (pure logic) ----------
cat > "$BASE/accessibility/ScreenSummarizer.kt" <<'EOF'
package com.nova.ai.accessibility

import com.nova.ai.core.ScreenNode
import com.nova.ai.core.ScreenSnapshot

/**
 * What is on the screen, sorted into three groups in reading order.
 * [unnamedFields] counts input fields that have no label.
 */
data class ScreenReport(
    val packageName: String?,
    val texts: List<String>,
    val buttons: List<String>,
    val fields: List<String>,
    val unnamedFields: Int
) {
    /** True when nothing readable was found. */
    val isEmpty: Boolean
        get() = texts.isEmpty() && buttons.isEmpty() && fields.isEmpty() && unnamedFields == 0
}

/** Text prepared for speaking. [truncated] is true if the end was cut off. */
data class SpeechText(val text: String, val truncated: Boolean)

/** Pure logic (no Android classes), so it is easy to test. */
object ScreenSummarizer {

    /** Speech engines refuse very long text; this keeps a safe margin. */
    const val MAX_SPEECH_CHARS: Int = 1400

    // Nodes whose tops are closer than this are treated as one visual row.
    private const val ROW_BUCKET_PX: Int = 40
    private const val SEPARATOR: String = ". "

    /** Sorts the nodes of [snapshot] into texts, buttons and input fields. */
    fun summarize(snapshot: ScreenSnapshot): ScreenReport {
        val ordered: List<ScreenNode> = snapshot.nodes.sortedWith(
            compareBy<ScreenNode>({ it.bounds.top / ROW_BUCKET_PX }, { it.bounds.left })
        )

        val texts: MutableList<String> = ArrayList()
        val buttons: MutableList<String> = ArrayList()
        val fields: MutableList<String> = ArrayList()
        var unnamedFields = 0

        for (node in ordered) {
            val label: String? = node.text ?: node.contentDescription
            if (node.isEditable) {
                if (label != null) fields.add(label) else unnamedFields++
            } else if (node.isClickable) {
                if (label != null) buttons.add(label)
            } else if (label != null) {
                texts.add(label)
            }
        }

        return ScreenReport(
            packageName = snapshot.packageName,
            texts = texts.distinct(),
            buttons = buttons.distinct(),
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
}
EOF

# ---------- D. Captures the screen in front through the running service ----------
cat > "$BASE/accessibility/ScreenReader.kt" <<'EOF'
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
EOF

# ---------- E. Screen-side holder: countdown, capture, speak ----------
cat > "$BASE/accessibility/ScreenReadController.kt" <<'EOF'
package com.nova.ai.accessibility

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.R
import com.nova.ai.core.Language
import com.nova.ai.core.NovaResult
import com.nova.ai.core.ScreenSnapshot
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
        val report: ScreenReport,
        val truncated: Boolean,
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
        val result: NovaResult<ScreenSnapshot> = withContext(Dispatchers.Default) {
            ScreenReader.capture()
        }
        when (result) {
            is NovaResult.Failure -> state = ScreenReadState.Failed(result.error.message)
            is NovaResult.Success -> present(ScreenSummarizer.summarize(result.value))
        }
    }

    private fun present(report: ScreenReport) {
        if (report.isEmpty) {
            state = ScreenReadState.Failed(appContext.getString(R.string.scr_empty))
            return
        }
        // Only counts are logged, never the content.
        NovaLogger.i(
            TAG,
            "Screen read: texts=${report.texts.size} buttons=${report.buttons.size} " +
                "fields=${report.fields.size + report.unnamedFields}"
        )

        // Speak the texts; if the screen has none, speak its buttons instead.
        val readTexts: Boolean = report.texts.isNotEmpty()
        val parts: List<String> = if (readTexts) report.texts else report.buttons
        if (parts.isEmpty()) {
            state = ScreenReadState.Done(report, truncated = false, speakError = null)
            return
        }

        val detected: Language = LanguageDetector.detect(parts.joinToString(" "))
        val language: Language = if (detected == Language.UNKNOWN) defaultLanguage() else detected
        val speech: SpeechText = ScreenSummarizer.toSpeech(parts)
        val spoken: String = introFor(language, readTexts) + " " + speech.text

        val spoke: NovaResult<Unit> = speak(spoken, language)
        val speakError: String? = (spoke as? NovaResult.Failure)?.error?.message
        state = ScreenReadState.Done(report, speech.truncated, speakError)
    }

    private fun introFor(language: Language, readTexts: Boolean): String {
        val english: Boolean = language == Language.ENGLISH
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

# ---------- F. Home card ----------
cat > "$BASE/ui/components/ScreenReadCard.kt" <<'EOF'
package com.nova.ai.ui.components

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
import androidx.compose.ui.Modifier
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
                is ScreenReadState.Done -> ReportContent(state)
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
private fun ReportContent(done: ScreenReadState.Done) {
    val report = done.report
    Text(
        text = stringResource(
            R.string.scr_counts,
            report.texts.size,
            report.buttons.size,
            report.fields.size + report.unnamedFields
        )
    )
    done.speakError?.let { message ->
        Text(text = "⚠️ " + stringResource(R.string.scr_speak_error, message))
    }
    if (done.truncated) {
        Text(
            text = stringResource(R.string.scr_truncated),
            style = MaterialTheme.typography.bodySmall
        )
    }

    ReportSection(stringResource(R.string.scr_texts_title), report.texts)
    ReportSection(stringResource(R.string.scr_buttons_title), report.buttons)
    ReportSection(stringResource(R.string.scr_fields_title), report.fields)
    if (report.unnamedFields > 0) {
        Text(text = stringResource(R.string.scr_unnamed_fields, report.unnamedFields))
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
EOF

# ---------- G. HomeScreen: five additive lines ----------
if ! grep -q "ScreenReadCard" "$HOME_FILE"; then
  grep -q '^import com.nova.ai.ui.components.MediaActionCard$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (import) not found" >&2; exit 1; }
  grep -q '^    val mediaController: MediaCommandController = remember { MediaCommandController(context) }$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (controller) not found" >&2; exit 1; }
  grep -q '^        MediaActionCard(controller = mediaController)$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (card) not found" >&2; exit 1; }
  grep -q '^            systemController.release()$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (release) not found" >&2; exit 1; }

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
grep -q "^import com.nova.ai.ui.components.ScreenReadCard$" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (card import)" >&2; exit 1; }
grep -q "^import com.nova.ai.accessibility.ScreenReadController$" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (controller import)" >&2; exit 1; }
grep -q "^    val screenReadController: ScreenReadController = remember {$" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (controller)" >&2; exit 1; }
grep -q "^        ScreenReadCard(controller = screenReadController)$" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (card)" >&2; exit 1; }
grep -q "^            screenReadController.stop()$" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (release)" >&2; exit 1; }

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "P18: screen reader (accessibility tree: texts, buttons, input fields) with spoken output"
git push
echo "P18 done. Wait for the GitHub Actions build, install the APK and test the Home card."
