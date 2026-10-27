#!/usr/bin/env bash
# NOVA AI - Phase 22 setup script: the floating bubble and the emergency stop.
# Additive: new bubble, voice-focus and emergency-stop classes, a foreground service, two
# Quick Settings tiles and an Access-screen card. Existing files get only small additions:
# manifest entries, one guard line at the start of the command controllers' actions (so the
# emergency stop really stops them), the Home screen's voice registration, and the card.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
RES="app/src/main/res"
TEST="app/src/test/java/com/nova/ai"
MANIFEST="app/src/main/AndroidManifest.xml"
HOME_FILE="$BASE/ui/screens/HomeScreen.kt"
PERMS_FILE="$BASE/ui/screens/PermissionsScreen.kt"
APP_CTRL="$BASE/apps/AppCommandController.kt"
CONTACT_CTRL="$BASE/contacts/ContactCommandController.kt"
TIME_CTRL="$BASE/time/TimeCommandController.kt"
SYSTEM_CTRL="$BASE/system/SystemCommandController.kt"
MEDIA_CTRL="$BASE/media/MediaCommandController.kt"

fail() { echo "ERROR: $*" >&2; exit 1; }

TMP_FILES=()
cleanup() { [ ${#TMP_FILES[@]} -eq 0 ] || rm -f "${TMP_FILES[@]}"; }
trap cleanup EXIT

# ---------- helpers ----------
# Number of lines that equal $2 exactly.
count_line() { grep -c -x -F -- "$2" "$1" || true; }

# True if the line right after the (single) anchor line contains $3.
next_line_has() { grep -x -F -A1 -- "$2" "$1" | sed -n '2p' | grep -q -F -- "$3"; }

# Adds $3 (one or more lines) right after the single line that equals $2. Skips when $4 is already in the file.
insert_after() {
  local file="$1" anchor="$2" text="$3" marker="$4" tmp
  if grep -q -F -- "$marker" "$file"; then return 0; fi
  [ "$(count_line "$file" "$anchor")" = "1" ] || fail "anchor not found exactly once in $file: $anchor"
  tmp="$(mktemp)"; TMP_FILES+=("$tmp")
  A="$anchor" T="$text" awk '{ print } $0 == ENVIRON["A"] { print ENVIRON["T"] }' "$file" > "$tmp"
  cat "$tmp" > "$file"
}

# Adds the guard as the first line of the function that starts with line $2, unless it is already there.
add_guard() {
  local file="$1" anchor="$2" tmp
  if next_line_has "$file" "$anchor" "EmergencyStop.isActive"; then return 0; fi
  [ "$(count_line "$file" "$anchor")" = "1" ] || fail "anchor not found exactly once in $file: $anchor"
  tmp="$(mktemp)"; TMP_FILES+=("$tmp")
  A="$anchor" awk '{ print } $0 == ENVIRON["A"] { print "        if (EmergencyStop.isActive) return" }' "$file" > "$tmp"
  cat "$tmp" > "$file"
}

# ---------- preflight: stop early if something is missing ----------
for required in "$BASE/accessibility/ActionGate.kt" "$BASE/accessibility/NovaAccessibilityService.kt" \
  "$BASE/voice/ConversationController.kt" "$BASE/voice/AndroidVoiceEngine.kt" \
  "$BASE/core/NovaResult.kt" "$BASE/logging/NovaLogger.kt" "$BASE/settings/SettingsRepository.kt" \
  "$BASE/time/TimeText.kt" "$BASE/time/TimePlanner.kt" "$BASE/system/SystemActionOutcome.kt" \
  "$MANIFEST" "$HOME_FILE" "$PERMS_FILE" "$APP_CTRL" "$CONTACT_CTRL" "$TIME_CTRL" "$SYSTEM_CTRL" "$MEDIA_CTRL" \
  "app/src/test/java/com/nova/ai/verification/VerifiedStepRunnerTest.kt"; do
  [ -f "$required" ] || fail "$required not found. Run from the repo root after P20, P21 and fix-p20-p21 are installed."
done

PERM_ANCHOR='    <uses-permission android:name="android.permission.WRITE_SETTINGS" />'
imp_anchor='import com.nova.ai.brain.RuleBasedBrain'
for f in "$APP_CTRL" "$CONTACT_CTRL" "$TIME_CTRL" "$SYSTEM_CTRL" "$MEDIA_CTRL"; do
  grep -q "import com.nova.ai.security.EmergencyStop" "$f" || [ "$(count_line "$f" "$imp_anchor")" = "1" ] || fail "import anchor missing in $f"
  grep -q "^    fun handleCommand(text: String) {$" "$f" || fail "handleCommand not found in $f"
done
grep -q "SYSTEM_ALERT_WINDOW" "$MANIFEST" || [ "$(count_line "$MANIFEST" "$PERM_ANCHOR")" = "1" ] || fail "manifest permission anchor missing"
grep -q "NovaBubbleService" "$MANIFEST" || [ "$(count_line "$MANIFEST" "    </application>")" = "1" ] || fail "manifest application anchor missing"
grep -q "VoiceFocus" "$HOME_FILE" || {
  [ "$(count_line "$HOME_FILE" "import com.nova.ai.voice.toSpeechLanguage")" = "1" ] || fail "HomeScreen import anchor missing"
  [ "$(count_line "$HOME_FILE" "        lifecycleOwner?.lifecycle?.addObserver(observer)")" = "1" ] || fail "HomeScreen observer anchor missing"
  [ "$(count_line "$HOME_FILE" "            lifecycleOwner?.lifecycle?.removeObserver(observer)")" = "1" ] || fail "HomeScreen dispose anchor missing"
  [ "$(count_line "$HOME_FILE" "    fun startConversation() {")" = "1" ] || fail "HomeScreen start anchor missing"
}
grep -q "BubbleCard" "$PERMS_FILE" || {
  [ "$(count_line "$PERMS_FILE" "import com.nova.ai.ui.components.ActionLabCard")" = "1" ] || fail "PermissionsScreen import anchor missing"
  [ "$(count_line "$PERMS_FILE" "        ActionLabCard()")" = "1" ] || fail "PermissionsScreen call anchor missing"
}

mkdir -p "$BASE/bubble" "$RES/drawable" "$TEST/security" "$TEST/voice" "$TEST/bubble"

# ---------- 1. EmergencyStop.kt ----------
cat > "$BASE/security/EmergencyStop.kt" <<'EOF'
package com.nova.ai.security

import com.nova.ai.accessibility.ActionGate
import com.nova.ai.logging.NovaLogger
import com.nova.ai.voice.VoiceFocus
import java.util.concurrent.CopyOnWriteArrayList

/**
 * The logic of the emergency stop, free of Android classes so it can be tested without a phone.
 * Triggering it switches the stop on, then runs every registered hook (each one on its own, so a
 * failing hook cannot block the others), and tells the listeners when the state really changed.
 * Hooks and listeners run on the thread that triggers the stop: they must be quick, and a hook
 * that needs the main thread must switch to it by itself.
 */
class EmergencyStopController(
    private val readStopped: () -> Boolean,
    private val writeStopped: (Boolean) -> Unit,
    private val onHookError: (key: String, error: Throwable) -> Unit = { _, _ -> },
    private val onEvent: (String) -> Unit = {}
) {

    private val lock = Any()
    private val hooks: LinkedHashMap<String, () -> Unit> = LinkedHashMap()
    private val listeners: CopyOnWriteArrayList<(Boolean) -> Unit> = CopyOnWriteArrayList()

    /** True while the emergency stop is on. */
    val isActive: Boolean get() = readStopped()

    /**
     * Switches the stop on and runs the hooks. The hooks also run when the stop is already on,
     * so one more tap still stops anything that started in the meantime.
     * Returns true if the stop was off before.
     */
    fun trigger(source: String): Boolean {
        val changed: Boolean = !readStopped()
        writeStopped(true)
        onEvent("Emergency stop on (from $source)")
        runHooks()
        if (changed) notifyListeners(true)
        return changed
    }

    /** Switches the stop off. Returns true if it was on before. */
    fun release(source: String): Boolean {
        val changed: Boolean = readStopped()
        writeStopped(false)
        if (changed) {
            onEvent("Emergency stop off (from $source)")
            notifyListeners(false)
        }
        return changed
    }

    /** Registers (or replaces) the hook with the given [key]. It runs every time the stop is triggered. */
    fun registerHook(key: String, hook: () -> Unit) {
        synchronized(lock) { hooks[key] = hook }
    }

    /** Removes the hook with the given [key]. */
    fun unregisterHook(key: String) {
        synchronized(lock) { hooks.remove(key) }
    }

    /** Calls [listener] with true when the stop goes on and with false when it goes off. */
    fun addListener(listener: (Boolean) -> Unit) {
        listeners.addIfAbsent(listener)
    }

    /** Stops calling [listener]. */
    fun removeListener(listener: (Boolean) -> Unit) {
        listeners.remove(listener)
    }

    private fun runHooks() {
        val snapshot: List<Pair<String, () -> Unit>> =
            synchronized(lock) { hooks.entries.map { it.key to it.value } }
        for ((key, hook) in snapshot) {
            try {
                hook()
            } catch (e: Exception) {
                onHookError(key, e)
            }
        }
    }

    private fun notifyListeners(active: Boolean) {
        for (listener in listeners) {
            try {
                listener(active)
            } catch (e: Exception) {
                onHookError("listener", e)
            }
        }
    }
}

/**
 * The app-wide emergency stop. One tap (the floating bubble, the quick settings tile or the
 * notification button) switches off everything NOVA does by itself: the accessibility actions
 * ([ActionGate]), listening and speaking ([VoiceFocus]), and whatever later parts register as
 * a hook (the task planner cancels its queue this way).
 */
object EmergencyStop {

    /** The message shown to the user while the stop is on. */
    const val MESSAGE: String = "জরুরি Stop চালু আছে। ছাড়া না পর্যন্ত নোভা কোনো কাজ করবে না।"

    private const val TAG: String = "EmergencyStop"
    private const val VOICE_HOOK: String = "voice"

    private val controller = EmergencyStopController(
        readStopped = { ActionGate.isStopped },
        writeStopped = { stopped -> if (stopped) ActionGate.stop() else ActionGate.resume() },
        onHookError = { key, error -> NovaLogger.e(TAG, "Stop hook \"$key\" failed", error) },
        onEvent = { line -> NovaLogger.w(TAG, line) }
    )

    init {
        controller.registerHook(VOICE_HOOK) { VoiceFocus.stopAll() }
    }

    /** True while the emergency stop is on. */
    val isActive: Boolean get() = controller.isActive

    /** Switches the emergency stop on and stops everything. [source] says who asked (for the log). */
    fun trigger(source: String): Boolean = controller.trigger(source)

    /** Switches the emergency stop off. */
    fun release(source: String): Boolean = controller.release(source)

    /** Registers a hook that runs on every stop. See [EmergencyStopController.registerHook]. */
    fun registerHook(key: String, hook: () -> Unit) = controller.registerHook(key, hook)

    /** Removes a hook. */
    fun unregisterHook(key: String) = controller.unregisterHook(key)

    /** Calls [listener] when the stop goes on or off. */
    fun addListener(listener: (Boolean) -> Unit) = controller.addListener(listener)

    /** Stops calling [listener]. */
    fun removeListener(listener: (Boolean) -> Unit) = controller.removeListener(listener)
}
EOF

# ---------- 2. VoiceFocus.kt ----------
cat > "$BASE/voice/VoiceFocus.kt" <<'EOF'
package com.nova.ai.voice

import com.nova.ai.logging.NovaLogger

/**
 * Keeps the microphone to one user at a time. The Home screen and the floating bubble both
 * listen; each registers a stop action here. When one of them starts listening it calls
 * [VoiceFocusRegistry.claim], which stops the other, so two voice sessions never fight.
 * The emergency stop calls [VoiceFocusRegistry.stopAll].
 * A stop action must be quick and must switch to the main thread by itself if it needs it.
 */
class VoiceFocusRegistry(
    private val onError: (owner: String, error: Throwable) -> Unit = { _, _ -> }
) {

    private val lock = Any()
    private val owners: LinkedHashMap<String, () -> Unit> = LinkedHashMap()

    /** Registers (or replaces) the stop action of [owner]. */
    fun register(owner: String, stop: () -> Unit) {
        synchronized(lock) { owners[owner] = stop }
    }

    /** Removes [owner]. */
    fun unregister(owner: String) {
        synchronized(lock) { owners.remove(owner) }
    }

    /** [owner] starts to listen: every other owner is stopped. */
    fun claim(owner: String) = stopMatching { key -> key != owner }

    /** Stops every owner. */
    fun stopAll() = stopMatching { true }

    private fun stopMatching(selector: (String) -> Boolean) {
        val targets: List<Pair<String, () -> Unit>> =
            synchronized(lock) { owners.entries.filter { selector(it.key) }.map { it.key to it.value } }
        for ((owner, stop) in targets) {
            try {
                stop()
            } catch (e: Exception) {
                onError(owner, e)
            }
        }
    }
}

/** The app-wide [VoiceFocusRegistry]. */
object VoiceFocus {

    private const val TAG: String = "VoiceFocus"

    private val registry = VoiceFocusRegistry { owner, error ->
        NovaLogger.e(TAG, "Stopping \"$owner\" failed", error)
    }

    /** Registers (or replaces) the stop action of [owner]. */
    fun register(owner: String, stop: () -> Unit) = registry.register(owner, stop)

    /** Removes [owner]. */
    fun unregister(owner: String) = registry.unregister(owner)

    /** [owner] starts to listen: every other owner is stopped. */
    fun claim(owner: String) = registry.claim(owner)

    /** Stops every owner. */
    fun stopAll() = registry.stopAll()
}
EOF

# ---------- 3. BubbleGeometry.kt ----------
cat > "$BASE/bubble/BubbleGeometry.kt" <<'EOF'
package com.nova.ai.bubble

/** A position in pixels. */
internal data class BubblePoint(val x: Int, val y: Int)

/**
 * Where the floating bubble and its panel go on the screen. Plain arithmetic with no Android
 * classes, so it can be tested without a phone. All numbers are pixels.
 */
internal object BubbleGeometry {

    /** True if a box at [x] is on the right half of the screen. */
    fun isRightSide(x: Int, boxWidth: Int, screenWidth: Int): Boolean =
        x + boxWidth / 2 >= screenWidth / 2

    /** The x of the box when it sticks to the nearest screen edge. */
    fun snapX(x: Int, boxWidth: Int, screenWidth: Int): Int =
        if (isRightSide(x, boxWidth, screenWidth)) maxOf(0, screenWidth - boxWidth) else 0

    /** Keeps [x] so the box stays fully on the screen. */
    fun clampX(x: Int, boxWidth: Int, screenWidth: Int): Int =
        x.coerceIn(0, maxOf(0, screenWidth - boxWidth))

    /** Keeps [y] between the top inset (status bar) and the bottom of the screen. */
    fun clampY(y: Int, boxHeight: Int, screenHeight: Int, topInset: Int): Int {
        val highest: Int = maxOf(topInset, screenHeight - boxHeight)
        return y.coerceIn(topInset, highest)
    }

    /** How far down the free area the box is, from 0.0 (top) to 1.0 (bottom). */
    fun yToFraction(y: Int, boxHeight: Int, screenHeight: Int, topInset: Int): Float {
        val range: Int = screenHeight - boxHeight - topInset
        if (range <= 0) return 0f
        return ((y - topInset).toFloat() / range).coerceIn(0f, 1f)
    }

    /** The reverse of [yToFraction]; also works after the screen was turned. */
    fun fractionToY(fraction: Float, boxHeight: Int, screenHeight: Int, topInset: Int): Int {
        val range: Int = maxOf(0, screenHeight - boxHeight - topInset)
        val safe: Float = if (fraction.isNaN()) 0f else fraction.coerceIn(0f, 1f)
        return topInset + (range * safe).toInt()
    }

    /**
     * Where the panel goes: centered on the bubble when possible, kept [gap] away from the screen
     * edges, above the bubble if there is room, otherwise below it.
     */
    fun panelPosition(
        boxX: Int,
        boxY: Int,
        boxWidth: Int,
        boxHeight: Int,
        panelWidth: Int,
        panelHeight: Int,
        screenWidth: Int,
        screenHeight: Int,
        gap: Int
    ): BubblePoint {
        val centered: Int = boxX + boxWidth / 2 - panelWidth / 2
        val x: Int = centered.coerceIn(gap, maxOf(gap, screenWidth - panelWidth - gap))

        val above: Int = boxY - gap - panelHeight
        val below: Int = boxY + boxHeight + gap
        val y: Int = when {
            above >= gap -> above
            below + panelHeight <= screenHeight - gap -> below
            else -> maxOf(gap, screenHeight - panelHeight - gap)
        }
        return BubblePoint(x, y)
    }
}
EOF

# ---------- 4. BubbleState.kt ----------
cat > "$BASE/bubble/BubbleState.kt" <<'EOF'
package com.nova.ai.bubble

import com.nova.ai.voice.ConversationState

/** What the floating bubble shows. */
internal enum class BubbleState {
    /** Waiting for a tap. */
    IDLE,

    /** The microphone is open. */
    LISTENING,

    /** NOVA is speaking. */
    SPEAKING,

    /** A command was heard and is being carried out. */
    THINKING,

    /** The emergency stop is on. */
    STOPPED
}

/** Decides the bubble state from what the rest of the app is doing. */
internal object BubbleStateMapper {

    /** The emergency stop wins over everything; then speaking, listening and working. */
    fun map(emergencyActive: Boolean, conversation: ConversationState, routing: Boolean): BubbleState = when {
        emergencyActive -> BubbleState.STOPPED
        conversation == ConversationState.SPEAKING -> BubbleState.SPEAKING
        conversation == ConversationState.LISTENING || conversation == ConversationState.WAITING ->
            BubbleState.LISTENING
        routing -> BubbleState.THINKING
        else -> BubbleState.IDLE
    }

    /** The red stop badge is shown while NOVA is busy. */
    fun showsStopBadge(state: BubbleState): Boolean = when (state) {
        BubbleState.LISTENING, BubbleState.SPEAKING, BubbleState.THINKING -> true
        BubbleState.IDLE, BubbleState.STOPPED -> false
    }
}
EOF

# ---------- 5. BubbleOutput.kt ----------
cat > "$BASE/bubble/BubbleOutput.kt" <<'EOF'
package com.nova.ai.bubble

import com.nova.ai.apps.InstalledApp
import com.nova.ai.apps.RegisteredApp
import com.nova.ai.contacts.Contact

/** What kind of line a message is, for its icon and color. */
internal enum class MessageKind { DONE, INFO, ERROR }

/** One choice of a [BubbleOutput.Decision]. [action] runs when the user taps it. */
internal data class BubbleOption(
    val label: String,
    val emphasis: Boolean = false,
    val action: () -> Unit
)

/** What the bubble shows after a command: nothing yet, a message, a question, or "open the app". */
internal sealed class BubbleOutput {

    /** Nothing to show (yet). */
    object None : BubbleOutput()

    /** A finished result, or a note. */
    data class Message(val text: String, val kind: MessageKind) : BubbleOutput()

    /**
     * A question the user must answer by tapping one of the [options] (or cancel). [source] is the
     * state the question came from, so the same question is not shown twice.
     */
    data class Decision(
        val source: Any,
        val question: String,
        val options: List<BubbleOption>
    ) : BubbleOutput()

    /** The step needs something only the app screen can do (a permission pop-up, for example). */
    data class NeedsApp(val text: String) : BubbleOutput()
}

/** The texts of the bubble. The app reads them from resources; tests use a fake. */
internal interface BubbleTexts {
    fun opened(appLabel: String): String
    fun confirmApp(appLabel: String): String
    fun chooseApp(spoken: String): String
    fun suggestApp(spoken: String): String
    fun appNotFound(spoken: String): String
    fun chooseContact(spoken: String): String
    fun chooseNumber(contactName: String): String
    fun confirmCall(who: String, number: String): String
    fun contactNotFound(spoken: String): String
    fun askPeriod(clockText: String): String
    fun needsContactsPermission(): String
    fun yesOpen(): String
    fun callNow(): String
    fun notUnderstood(): String
    fun notDone(): String
}

/** What the bubble can do when the user answers a question. The router connects it to the controllers. */
internal interface BubbleActions {
    fun confirmApp()
    fun chooseApp(app: RegisteredApp)
    fun addAndOpen(app: InstalledApp)
    fun pickContact(contact: Contact)
    fun pickNumber(number: String)
    fun placeCall(number: String)
    fun choosePeriod(isEvening: Boolean)
}
EOF

# ---------- 6. BubbleOutputMapper.kt ----------
cat > "$BASE/bubble/BubbleOutputMapper.kt" <<'EOF'
package com.nova.ai.bubble

import com.nova.ai.apps.AppActionUi
import com.nova.ai.contacts.ContactActionUi
import com.nova.ai.system.OutcomeKind
import com.nova.ai.system.SystemActionOutcome
import com.nova.ai.time.TimeActionUi
import com.nova.ai.time.TimePlanner
import com.nova.ai.time.TimeText

/**
 * Turns what the five command controllers hold (the state their Home cards show) into one
 * [BubbleOutput] for the bubble. It only reads: no question is ever answered here, so a call
 * is never placed without the user tapping the call button.
 */
internal class BubbleOutputMapper(
    private val texts: BubbleTexts,
    private val actions: BubbleActions
) {

    /** The first controller that has something to show wins (call, app, time, system, media). */
    fun map(
        app: AppActionUi,
        contact: ContactActionUi,
        time: TimeActionUi,
        system: SystemActionOutcome?,
        media: SystemActionOutcome?
    ): BubbleOutput {
        val candidates: List<BubbleOutput> = listOf(
            fromContact(contact),
            fromApp(app),
            fromTime(time),
            fromOutcome(system),
            fromOutcome(media)
        )
        return candidates.firstOrNull { it !is BubbleOutput.None } ?: BubbleOutput.None
    }

    private fun fromContact(state: ContactActionUi): BubbleOutput = when (state) {
        is ContactActionUi.Idle -> BubbleOutput.None
        is ContactActionUi.NeedsContactsPermission ->
            BubbleOutput.NeedsApp(texts.needsContactsPermission())
        is ContactActionUi.ChooseContact -> BubbleOutput.Decision(
            source = state,
            question = texts.chooseContact(state.spoken),
            options = state.contacts.take(MAX_OPTIONS).map { contact ->
                BubbleOption(contact.name) { actions.pickContact(contact) }
            }
        )
        is ContactActionUi.ChooseNumber -> BubbleOutput.Decision(
            source = state,
            question = texts.chooseNumber(state.contact.name),
            options = state.contact.numbers.take(MAX_OPTIONS).map { number ->
                BubbleOption(number) { actions.pickNumber(number) }
            }
        )
        is ContactActionUi.ConfirmCall -> BubbleOutput.Decision(
            source = state,
            question = texts.confirmCall(state.name ?: state.number, state.number),
            options = listOf(BubbleOption(texts.callNow(), emphasis = true) { actions.placeCall(state.number) })
        )
        is ContactActionUi.Done -> BubbleOutput.Message(state.message, MessageKind.DONE)
        is ContactActionUi.Info -> BubbleOutput.Message(state.message, MessageKind.INFO)
        is ContactActionUi.NotFound ->
            BubbleOutput.Message(texts.contactNotFound(state.spoken), MessageKind.INFO)
        is ContactActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR)
    }

    private fun fromApp(state: AppActionUi): BubbleOutput = when (state) {
        is AppActionUi.Idle -> BubbleOutput.None
        is AppActionUi.Opened -> BubbleOutput.Message(texts.opened(state.appLabel), MessageKind.DONE)
        is AppActionUi.Confirm -> BubbleOutput.Decision(
            source = state,
            question = texts.confirmApp(state.app.label),
            options = listOf(BubbleOption(texts.yesOpen(), emphasis = true) { actions.confirmApp() })
        )
        is AppActionUi.Choose -> BubbleOutput.Decision(
            source = state,
            question = texts.chooseApp(state.spoken),
            options = state.apps.take(MAX_OPTIONS).map { app ->
                BubbleOption(app.label) { actions.chooseApp(app) }
            }
        )
        is AppActionUi.Suggest -> BubbleOutput.Decision(
            source = state,
            question = texts.suggestApp(state.spoken),
            options = state.apps.take(MAX_OPTIONS).map { app ->
                BubbleOption(app.label) { actions.addAndOpen(app) }
            }
        )
        is AppActionUi.NotFound -> BubbleOutput.Message(texts.appNotFound(state.spoken), MessageKind.INFO)
        is AppActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR)
    }

    private fun fromTime(state: TimeActionUi): BubbleOutput = when (state) {
        is TimeActionUi.Idle -> BubbleOutput.None
        is TimeActionUi.Done -> BubbleOutput.Message(state.message, MessageKind.DONE)
        is TimeActionUi.AskPeriod -> {
            val minuteText: String = state.minute.toString().padStart(2, '0')
            BubbleOutput.Decision(
                source = state,
                question = texts.askPeriod(TimeText.digits("${state.hour}:$minuteText")),
                options = listOf(false, true).map { evening ->
                    val label: String = TimeText.clock(TimePlanner.to24(state.hour, evening), state.minute)
                    BubbleOption(label, emphasis = true) { actions.choosePeriod(isEvening = evening) }
                }
            )
        }
        is TimeActionUi.NeedsDetail -> BubbleOutput.Message(state.message, MessageKind.INFO)
        is TimeActionUi.Failed -> BubbleOutput.Message(state.message, MessageKind.ERROR)
    }

    private fun fromOutcome(outcome: SystemActionOutcome?): BubbleOutput {
        if (outcome == null) return BubbleOutput.None
        return when (outcome.kind) {
            OutcomeKind.DONE -> BubbleOutput.Message(outcome.message, MessageKind.DONE)
            OutcomeKind.GUIDED, OutcomeKind.HINT -> BubbleOutput.Message(outcome.message, MessageKind.INFO)
            OutcomeKind.NEEDS_PERMISSION -> BubbleOutput.NeedsApp(outcome.message)
            OutcomeKind.FAILED -> BubbleOutput.Message(outcome.message, MessageKind.ERROR)
        }
    }

    private companion object {
        // A small panel shows at most this many choices.
        const val MAX_OPTIONS: Int = 5
    }
}
EOF

# ---------- 7. BubbleCommandRouter.kt ----------
cat > "$BASE/bubble/BubbleCommandRouter.kt" <<'EOF'
package com.nova.ai.bubble

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.nova.ai.apps.AppCommandController
import com.nova.ai.apps.InstalledApp
import com.nova.ai.apps.RegisteredApp
import com.nova.ai.contacts.Contact
import com.nova.ai.contacts.ContactCommandController
import com.nova.ai.media.MediaCommandController
import com.nova.ai.security.EmergencyStop
import com.nova.ai.system.SystemCommandController
import com.nova.ai.time.TimeCommandController
import kotlinx.coroutines.CoroutineScope

/**
 * Runs a command from the bubble through the same five controllers the Home screen uses, and
 * turns what they report into a [BubbleOutput] for the bubble. Some controllers answer a moment
 * later (they look up apps or contacts first), so after a command the router looks at them every
 * [POLL_MS] until one has something to show or [WAIT_MS] is over.
 * Use from the main thread.
 */
internal class BubbleCommandRouter(
    context: Context,
    scope: CoroutineScope,
    private val texts: BubbleTexts,
    private val onOutput: (BubbleOutput) -> Unit,
    private val onBusyChanged: (Boolean) -> Unit
) : BubbleActions {

    private val app = AppCommandController(context, scope)
    private val system = SystemCommandController(context)
    private val contact = ContactCommandController(context, scope)
    private val time = TimeCommandController(context)
    private val media = MediaCommandController(context)

    private val mapper = BubbleOutputMapper(texts, this)
    private val handler = Handler(Looper.getMainLooper())

    private var pollTask: Runnable? = null
    private var busy: Boolean = false

    /** Carries out [text]. The answer arrives through [onOutput]. */
    fun handle(text: String) {
        cancel()
        if (EmergencyStop.isActive) {
            onOutput(BubbleOutput.Message(EmergencyStop.MESSAGE, MessageKind.ERROR))
            return
        }
        // Every controller looks at the text; the ones it does not concern reset themselves.
        app.handleCommand(text)
        system.handleCommand(text)
        contact.handleCommand(text)
        time.handleCommand(text)
        media.handleCommand(text)
        await(answeredSource = null, timeoutText = texts.notUnderstood())
    }

    /** The user tapped [option] of [decision]: run it and wait for what it leads to. */
    fun choose(decision: BubbleOutput.Decision, option: BubbleOption) {
        cancel()
        if (EmergencyStop.isActive) {
            onOutput(BubbleOutput.Message(EmergencyStop.MESSAGE, MessageKind.ERROR))
            return
        }
        option.action()
        await(answeredSource = decision.source, timeoutText = texts.notDone())
    }

    /** The user closed a question without answering: forget it. */
    fun dismissQuestion() {
        cancel()
        app.dismiss()
        contact.dismiss()
        time.dismiss()
        system.dismiss()
        media.dismiss()
    }

    /** Stops waiting for an answer (for example when the emergency stop goes on). */
    fun cancel() {
        pollTask?.let { handler.removeCallbacks(it) }
        pollTask = null
        setBusy(false)
    }

    /** Releases listeners. Call when the bubble is gone. */
    fun release() {
        cancel()
        system.release()
    }

    // ---------------------------------------------------------------- BubbleActions

    override fun confirmApp() = app.confirm()
    override fun chooseApp(app: RegisteredApp) = this.app.choose(app)
    override fun addAndOpen(app: InstalledApp) = this.app.addAndOpen(app)
    override fun pickContact(contact: Contact) = this.contact.pickContact(contact)
    override fun pickNumber(number: String) = contact.pickNumber(number)
    override fun placeCall(number: String) = contact.placeCall(number)
    override fun choosePeriod(isEvening: Boolean) = time.choosePeriod(isEvening)

    // ---------------------------------------------------------------- waiting

    private fun current(): BubbleOutput =
        mapper.map(app.state, contact.state, time.state, system.state, media.state)

    // Looks again and again until something new is there. A question that was just answered
    // (answeredSource) does not count as new while it is still the same question.
    private fun await(answeredSource: Any?, timeoutText: String) {
        setBusy(true)
        val startedAt: Long = SystemClock.uptimeMillis()
        val task = object : Runnable {
            override fun run() {
                val output: BubbleOutput = current()
                val stale: Boolean = output is BubbleOutput.Decision && output.source === answeredSource
                when {
                    output !is BubbleOutput.None && !stale -> finish(output)
                    SystemClock.uptimeMillis() - startedAt >= WAIT_MS ->
                        finish(BubbleOutput.Message(timeoutText, MessageKind.INFO))
                    else -> handler.postDelayed(this, POLL_MS)
                }
            }
        }
        pollTask = task
        handler.post(task)
    }

    private fun finish(output: BubbleOutput) {
        pollTask = null
        setBusy(false)
        onOutput(output)
    }

    private fun setBusy(value: Boolean) {
        if (busy == value) return
        busy = value
        onBusyChanged(value)
    }

    private companion object {
        const val POLL_MS: Long = 150L
        const val WAIT_MS: Long = 4000L
    }
}
EOF

# ---------- 8. BubblePrefs.kt ----------
cat > "$BASE/bubble/BubblePrefs.kt" <<'EOF'
package com.nova.ai.bubble

import android.content.Context
import android.content.SharedPreferences
import com.nova.ai.logging.NovaLogger

/** Remembers where the user left the bubble: which screen edge and how far down. */
internal class BubblePrefs(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** True if the bubble sticks to the right edge. */
    fun isRightSide(): Boolean = try {
        prefs.getBoolean(KEY_RIGHT, true)
    } catch (e: Exception) {
        NovaLogger.w(TAG, "Could not read the bubble side", e)
        true
    }

    /** How far down the free area the bubble is, from 0.0 to 1.0. */
    fun yFraction(): Float = try {
        prefs.getFloat(KEY_Y, DEFAULT_Y)
    } catch (e: Exception) {
        NovaLogger.w(TAG, "Could not read the bubble position", e)
        DEFAULT_Y
    }

    /** Saves the place of the bubble. */
    fun save(rightSide: Boolean, yFraction: Float) {
        try {
            prefs.edit().putBoolean(KEY_RIGHT, rightSide).putFloat(KEY_Y, yFraction).apply()
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not save the bubble position", e)
        }
    }

    private companion object {
        const val TAG: String = "BubblePrefs"
        const val PREFS_NAME: String = "nova_bubble"
        const val KEY_RIGHT: String = "right_side"
        const val KEY_Y: String = "y_fraction"
        const val DEFAULT_Y: Float = 0.4f
    }
}
EOF

# ---------- 9. ResourceBubbleTexts.kt ----------
cat > "$BASE/bubble/ResourceBubbleTexts.kt" <<'EOF'
package com.nova.ai.bubble

import android.content.Context
import com.nova.ai.R

/** The bubble texts, read from the string resources. */
internal class ResourceBubbleTexts(context: Context) : BubbleTexts {

    private val appContext: Context = context.applicationContext

    override fun opened(appLabel: String): String = appContext.getString(R.string.bub_opened, appLabel)
    override fun confirmApp(appLabel: String): String = appContext.getString(R.string.bub_confirm_app, appLabel)
    override fun chooseApp(spoken: String): String = appContext.getString(R.string.bub_choose_app, spoken)
    override fun suggestApp(spoken: String): String = appContext.getString(R.string.bub_suggest_app, spoken)
    override fun appNotFound(spoken: String): String = appContext.getString(R.string.bub_app_not_found, spoken)
    override fun chooseContact(spoken: String): String = appContext.getString(R.string.bub_choose_contact, spoken)
    override fun chooseNumber(contactName: String): String =
        appContext.getString(R.string.bub_choose_number, contactName)
    override fun confirmCall(who: String, number: String): String =
        appContext.getString(R.string.bub_confirm_call, who, number)
    override fun contactNotFound(spoken: String): String =
        appContext.getString(R.string.bub_contact_not_found, spoken)
    override fun askPeriod(clockText: String): String = appContext.getString(R.string.bub_ask_period, clockText)
    override fun needsContactsPermission(): String = appContext.getString(R.string.bub_needs_contacts)
    override fun yesOpen(): String = appContext.getString(R.string.bub_yes_open)
    override fun callNow(): String = appContext.getString(R.string.bub_call_now)
    override fun notUnderstood(): String = appContext.getString(R.string.bub_not_understood)
    override fun notDone(): String = appContext.getString(R.string.bub_not_done)
}
EOF

# ---------- 10. BubbleController.kt ----------
cat > "$BASE/bubble/BubbleController.kt" <<'EOF'
package com.nova.ai.bubble

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.nova.ai.R
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * Starts and stops the floating bubble and tells whether it can run. The screens, the quick
 * settings tile and the notification all use this one place. Use from the main thread.
 */
object BubbleController {

    private const val TAG: String = "BubbleController"

    /** True while the bubble service is running. Set by the service; the screens only read it. */
    var isRunning: Boolean by mutableStateOf(false)
        internal set

    /** True if the user allowed NOVA to draw over other apps. */
    fun canDrawOverlays(context: Context): Boolean = Settings.canDrawOverlays(context)

    /** True if the user allowed the microphone. */
    fun hasMicrophone(context: Context): Boolean = ContextCompat.checkSelfPermission(
        context, Manifest.permission.RECORD_AUDIO
    ) == PackageManager.PERMISSION_GRANTED

    /** The settings screen where the user allows drawing over other apps. */
    fun overlaySettingsIntent(context: Context): Intent =
        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))

    /** Starts the bubble. A failure result says what is missing. */
    fun start(context: Context): NovaResult<Unit> {
        val appContext: Context = context.applicationContext
        if (!canDrawOverlays(appContext)) {
            return NovaResult.failure(ErrorCode.PERMISSION_DENIED, appContext.getString(R.string.bub_need_overlay))
        }
        if (!hasMicrophone(appContext)) {
            return NovaResult.failure(ErrorCode.PERMISSION_DENIED, appContext.getString(R.string.bub_need_mic))
        }
        return try {
            val intent = Intent(appContext, NovaBubbleService::class.java).setAction(NovaBubbleService.ACTION_START)
            ContextCompat.startForegroundService(appContext, intent)
            NovaResult.Success(Unit)
        } catch (e: Exception) {
            // Android refuses to start a foreground service in some situations (for example from the background).
            NovaLogger.e(TAG, "Could not start the bubble service", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, appContext.getString(R.string.bub_start_failed), e)
        }
    }

    /** Stops the bubble. */
    fun stop(context: Context) {
        try {
            val appContext: Context = context.applicationContext
            appContext.stopService(Intent(appContext, NovaBubbleService::class.java))
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not stop the bubble service", e)
        }
    }
}
EOF

# ---------- 11. BubbleOverlay.kt ----------
cat > "$BASE/bubble/BubbleOverlay.kt" <<'EOF'
package com.nova.ai.bubble

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.nova.ai.R
import com.nova.ai.logging.NovaLogger
import kotlin.math.hypot

/** How a button of the panel looks. */
internal enum class PanelStyle { NORMAL, PRIMARY }

/** One button of the panel. */
internal data class PanelButton(
    val label: String,
    val style: PanelStyle = PanelStyle.NORMAL,
    val onClick: () -> Unit
)

/** What the overlay tells its owner. All calls happen on the main thread. */
internal interface BubbleOverlayCallbacks {
    fun onBubbleTap()
    fun onBubbleLongPress()
    fun onStopBadgeTap()
}

/**
 * The floating bubble and its panel, drawn as two small overlay windows over every app.
 * The bubble can be dragged; when let go it sticks to the nearest screen edge and the place is
 * remembered. A red stop badge sits on the bubble while NOVA is busy. The panel shows a status
 * line, a question with choices, or the menu. Only the small areas of the bubble and the panel
 * take touches; everything else on the screen works as usual. Use from the main thread.
 */
internal class BubbleOverlay(
    context: Context,
    private val prefs: BubblePrefs,
    private val callbacks: BubbleOverlayCallbacks
) {

    private val appContext: Context = context.applicationContext
    private val windowManager: WindowManager =
        appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val handler = Handler(Looper.getMainLooper())
    private val density: Float = appContext.resources.displayMetrics.density

    private val bubbleSize: Int = dp(BUBBLE_DP)
    private val boxSize: Int = dp(BOX_DP)
    private val badgeSize: Int = dp(BADGE_DP)
    private val sideShift: Int = boxSize - bubbleSize

    private val box = FrameLayout(appContext)
    private val ring = View(appContext)
    private val bubble = TextView(appContext)
    private val badge = TextView(appContext)

    private val boxParams: WindowManager.LayoutParams = WindowManager.LayoutParams(
        boxSize,
        boxSize,
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT
    ).apply { gravity = Gravity.TOP or Gravity.START }

    private var attached: Boolean = false
    private var layoutRight: Boolean = true
    private var state: BubbleState = BubbleState.IDLE
    private var screenWidth: Int = 0
    private var screenHeight: Int = 0
    private var topInset: Int = 0

    private var pulse: ValueAnimator? = null
    private var snap: ValueAnimator? = null

    private var panelView: LinearLayout? = null
    private var panelText: TextView? = null
    private var panelHasButtons: Boolean = false
    private var panelParams: WindowManager.LayoutParams? = null
    private var panelDismiss: (() -> Unit)? = null
    private var panelHideTask: Runnable? = null

    init {
        buildBubble()
        applyState(BubbleState.IDLE)
    }

    // ---------------------------------------------------------------- showing and hiding

    /** Puts the bubble on the screen. Returns false if Android refused (for example no permission). */
    fun show(): Boolean {
        if (attached) return true
        readScreen()
        placeFromPrefs()
        return try {
            windowManager.addView(box, boxParams)
            attached = true
            true
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not show the bubble", e)
            false
        }
    }

    /** Removes the bubble and the panel. */
    fun hide() {
        hidePanel()
        stopPulse()
        snap?.cancel()
        snap = null
        handler.removeCallbacksAndMessages(null)
        if (attached) {
            try {
                windowManager.removeView(box)
            } catch (e: Exception) {
                NovaLogger.w(TAG, "Could not remove the bubble", e)
            }
            attached = false
        }
    }

    /** Call when the screen was turned or the display changed. */
    fun onConfigurationChanged() {
        if (!attached) return
        hidePanel()
        readScreen()
        placeFromPrefs()
        updateBox()
    }

    // ---------------------------------------------------------------- state

    /** Shows [newState] on the bubble. */
    fun setState(newState: BubbleState) {
        if (newState == state) return
        applyState(newState)
    }

    private fun applyState(newState: BubbleState) {
        state = newState
        bubble.text = when (newState) {
            BubbleState.IDLE, BubbleState.LISTENING -> "🎙️"
            BubbleState.SPEAKING -> "🔊"
            BubbleState.THINKING -> "⏳"
            BubbleState.STOPPED -> "⏸️"
        }
        val color: Int = when (newState) {
            BubbleState.IDLE -> COLOR_IDLE
            BubbleState.LISTENING -> COLOR_LISTENING
            BubbleState.SPEAKING -> COLOR_SPEAKING
            BubbleState.THINKING -> COLOR_THINKING
            BubbleState.STOPPED -> COLOR_STOPPED
        }
        bubble.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
            setStroke(dp(2), Color.WHITE)
        }
        bubble.contentDescription = appContext.getString(
            when (newState) {
                BubbleState.IDLE -> R.string.bub_desc_idle
                BubbleState.LISTENING -> R.string.bub_desc_listening
                BubbleState.SPEAKING -> R.string.bub_desc_speaking
                BubbleState.THINKING -> R.string.bub_desc_thinking
                BubbleState.STOPPED -> R.string.bub_desc_stopped
            }
        )
        badge.visibility = if (BubbleStateMapper.showsStopBadge(newState)) View.VISIBLE else View.GONE
        box.alpha = if (newState == BubbleState.IDLE) IDLE_ALPHA else 1f
        if (newState == BubbleState.LISTENING) startPulse() else stopPulse()
    }

    // ---------------------------------------------------------------- panel

    /**
     * Shows a line of text in the panel. While a text-only panel is open its text is replaced in
     * place (used for the live words while listening). With [autoHideMs] above 0 it closes by itself.
     */
    fun showStatus(text: String, kind: MessageKind?, autoHideMs: Long) {
        val label: String = decorate(text, kind)
        val existing: TextView? = panelText
        if (panelView != null && !panelHasButtons && existing != null) {
            existing.text = label
            repositionPanel()
            scheduleAutoHide(autoHideMs)
            return
        }
        showPanel(label, emptyList(), autoHideMs, null)
    }

    /**
     * Shows [text] with [buttons]. [onDismiss] runs when the panel is closed without tapping a
     * button (a tap outside, or the time ran out). With [autoHideMs] above 0 the panel closes by itself.
     */
    fun showPanel(text: String, buttons: List<PanelButton>, autoHideMs: Long, onDismiss: (() -> Unit)?) {
        if (!attached) return
        closePanelWindow()
        panelDismiss = onDismiss
        panelHasButtons = buttons.isNotEmpty()

        val dark: Boolean = isDarkMode()
        val root = LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(12))
            background = GradientDrawable().apply {
                cornerRadius = dp(20).toFloat()
                setColor(if (dark) PANEL_DARK else PANEL_LIGHT)
            }
            elevation = dp(8).toFloat()
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            setOnTouchListener { _, event ->
                if (event.actionMasked == MotionEvent.ACTION_OUTSIDE) {
                    dismissByUser()
                    true
                } else {
                    false
                }
            }
        }
        val title = TextView(appContext).apply {
            this.text = text
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTextColor(if (dark) TEXT_ON_DARK else TEXT_ON_LIGHT)
            maxLines = MAX_PANEL_LINES
        }
        root.addView(title)
        for (button in buttons) root.addView(buildButton(button, dark))

        panelView = root
        panelText = title
        panelParams = WindowManager.LayoutParams(
            panelWidth(),
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.TOP or Gravity.START }
        positionPanel()
        try {
            windowManager.addView(root, panelParams)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not show the panel", e)
            panelView = null
            panelText = null
            panelParams = null
            panelDismiss = null
            return
        }
        scheduleAutoHide(autoHideMs)
    }

    /** Closes the panel without telling anyone. */
    fun hidePanel() {
        panelDismiss = null
        closePanelWindow()
    }

    private fun dismissByUser() {
        val callback: (() -> Unit)? = panelDismiss
        panelDismiss = null
        closePanelWindow()
        callback?.invoke()
    }

    private fun closePanelWindow() {
        panelHideTask?.let { handler.removeCallbacks(it) }
        panelHideTask = null
        val view: View? = panelView
        panelView = null
        panelText = null
        panelParams = null
        panelHasButtons = false
        if (view != null) {
            try {
                windowManager.removeView(view)
            } catch (e: Exception) {
                NovaLogger.w(TAG, "Could not remove the panel", e)
            }
        }
    }

    private fun scheduleAutoHide(autoHideMs: Long) {
        panelHideTask?.let { handler.removeCallbacks(it) }
        panelHideTask = null
        if (autoHideMs <= 0L) return
        val task = Runnable { dismissByUser() }
        panelHideTask = task
        handler.postDelayed(task, autoHideMs)
    }

    private fun buildButton(button: PanelButton, dark: Boolean): TextView {
        val primary: Boolean = button.style == PanelStyle.PRIMARY
        val fill: Int = when {
            primary -> COLOR_IDLE
            dark -> BUTTON_DARK
            else -> BUTTON_LIGHT
        }
        val textColor: Int = when {
            primary -> Color.WHITE
            dark -> TEXT_ON_DARK
            else -> COLOR_IDLE
        }
        return TextView(appContext).apply {
            text = button.label
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTextColor(textColor)
            gravity = Gravity.CENTER
            minHeight = dp(MIN_TOUCH_DP)
            setPadding(dp(12), dp(8), dp(12), dp(8))
            isClickable = true
            background = RippleDrawable(
                ColorStateList.valueOf(RIPPLE_COLOR),
                roundedFill(fill),
                roundedFill(Color.WHITE)
            )
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(8) }
            setOnClickListener {
                panelDismiss = null
                closePanelWindow()
                button.onClick()
            }
        }
    }

    private fun roundedFill(color: Int): GradientDrawable = GradientDrawable().apply {
        cornerRadius = dp(14).toFloat()
        setColor(color)
    }

    private fun decorate(text: String, kind: MessageKind?): String = when (kind) {
        MessageKind.DONE -> "✅ $text"
        MessageKind.ERROR -> "⚠️ $text"
        MessageKind.INFO, null -> text
    }

    private fun panelWidth(): Int =
        minOf(dp(PANEL_MAX_DP), screenWidth - 2 * dp(PANEL_GAP_DP))

    // Measures the panel and puts its window next to the bubble.
    private fun positionPanel() {
        val view: View = panelView ?: return
        val params: WindowManager.LayoutParams = panelParams ?: return
        view.measure(
            View.MeasureSpec.makeMeasureSpec(params.width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val point: BubblePoint = BubbleGeometry.panelPosition(
            boxX = boxParams.x,
            boxY = boxParams.y,
            boxWidth = boxSize,
            boxHeight = boxSize,
            panelWidth = params.width,
            panelHeight = view.measuredHeight,
            screenWidth = screenWidth,
            screenHeight = screenHeight,
            gap = dp(PANEL_GAP_DP)
        )
        params.x = point.x
        params.y = point.y
    }

    private fun repositionPanel() {
        val view: View = panelView ?: return
        val params: WindowManager.LayoutParams = panelParams ?: return
        positionPanel()
        try {
            windowManager.updateViewLayout(view, params)
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not move the panel", e)
        }
    }

    // ---------------------------------------------------------------- building the bubble

    private fun buildBubble() {
        ring.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.TRANSPARENT)
            setStroke(dp(3), COLOR_LISTENING)
        }
        ring.alpha = 0f

        bubble.apply {
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            includeFontPadding = false
            isClickable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            setOnClickListener { callbacks.onBubbleTap() }
            setOnLongClickListener {
                callbacks.onBubbleLongPress()
                true
            }
            setOnTouchListener(DragListener())
        }

        badge.apply {
            text = "⏹"
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            background = InsetDrawable(
                GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(COLOR_BADGE)
                },
                dp(BADGE_INSET_DP)
            )
            contentDescription = appContext.getString(R.string.bub_desc_badge)
            visibility = View.GONE
            setOnClickListener { callbacks.onStopBadgeTap() }
        }

        box.addView(ring, FrameLayout.LayoutParams(bubbleSize, bubbleSize))
        box.addView(bubble, FrameLayout.LayoutParams(bubbleSize, bubbleSize))
        box.addView(badge, FrameLayout.LayoutParams(badgeSize, badgeSize))
        layoutForSide(true)
    }

    // The bubble sits in the corner of the box that touches the screen edge; the badge in the opposite top corner.
    private fun layoutForSide(right: Boolean) {
        layoutRight = right
        val bubbleGravity: Int = Gravity.BOTTOM or (if (right) Gravity.END else Gravity.START)
        val badgeGravity: Int = Gravity.TOP or (if (right) Gravity.START else Gravity.END)
        (ring.layoutParams as FrameLayout.LayoutParams).gravity = bubbleGravity
        (bubble.layoutParams as FrameLayout.LayoutParams).gravity = bubbleGravity
        (badge.layoutParams as FrameLayout.LayoutParams).gravity = badgeGravity
        box.requestLayout()
    }

    // ---------------------------------------------------------------- the pulse around the bubble while listening

    private fun startPulse() {
        if (pulse != null) return
        pulse = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = PULSE_MS
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener { animator ->
                val progress: Float = animator.animatedValue as Float
                val scale: Float = 1f + PULSE_GROWTH * progress
                ring.scaleX = scale
                ring.scaleY = scale
                ring.alpha = PULSE_ALPHA * (1f - progress)
            }
            start()
        }
    }

    private fun stopPulse() {
        pulse?.cancel()
        pulse = null
        ring.alpha = 0f
        ring.scaleX = 1f
        ring.scaleY = 1f
    }

    // ---------------------------------------------------------------- position

    private fun readScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.maximumWindowMetrics.bounds
            screenWidth = bounds.width()
            screenHeight = bounds.height()
        } else {
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealMetrics(metrics)
            screenWidth = metrics.widthPixels
            screenHeight = metrics.heightPixels
        }
        val resource: Int = appContext.resources.getIdentifier("status_bar_height", "dimen", "android")
        topInset = if (resource > 0) appContext.resources.getDimensionPixelSize(resource) else 0
    }

    private fun placeFromPrefs() {
        val right: Boolean = prefs.isRightSide()
        layoutForSide(right)
        boxParams.x = if (right) maxOf(0, screenWidth - boxSize) else 0
        boxParams.y = BubbleGeometry.fractionToY(prefs.yFraction(), boxSize, screenHeight, topInset)
    }

    private fun updateBox() {
        if (!attached) return
        try {
            windowManager.updateViewLayout(box, boxParams)
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not move the bubble", e)
        }
    }

    // The left edge of the bubble itself (not of the whole box) on the screen.
    private fun bubbleLeft(): Int = if (layoutRight) boxParams.x + sideShift else boxParams.x

    private fun finishDrag() {
        val right: Boolean = BubbleGeometry.isRightSide(bubbleLeft(), bubbleSize, screenWidth)
        if (right != layoutRight) {
            // Flipping the corner moves the bubble inside the box; move the box so the bubble stays where it is.
            boxParams.x += if (right) -sideShift else sideShift
            layoutForSide(right)
        }
        val targetX: Int = if (right) maxOf(0, screenWidth - boxSize) else 0
        snap?.cancel()
        snap = ValueAnimator.ofInt(boxParams.x, targetX).apply {
            duration = SNAP_MS
            addUpdateListener { animator ->
                boxParams.x = animator.animatedValue as Int
                updateBox()
            }
            start()
        }
        prefs.save(right, BubbleGeometry.yToFraction(boxParams.y, boxSize, screenHeight, topInset))
    }

    // ---------------------------------------------------------------- touch: tap, long press, drag

    private inner class DragListener : View.OnTouchListener {
        private val slop: Int = ViewConfiguration.get(appContext).scaledTouchSlop
        private var downX: Float = 0f
        private var downY: Float = 0f
        private var startX: Int = 0
        private var startY: Int = 0
        private var dragging: Boolean = false
        private var longPressed: Boolean = false

        private val longPressTask = Runnable {
            if (!dragging) {
                longPressed = true
                bubble.performLongClick()
            }
        }

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = boxParams.x
                    startY = boxParams.y
                    dragging = false
                    longPressed = false
                    snap?.cancel()
                    handler.postDelayed(longPressTask, ViewConfiguration.getLongPressTimeout().toLong())
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx: Float = event.rawX - downX
                    val dy: Float = event.rawY - downY
                    if (!dragging && hypot(dx, dy) > slop) {
                        dragging = true
                        handler.removeCallbacks(longPressTask)
                        hidePanel()
                    }
                    if (dragging) {
                        boxParams.x = BubbleGeometry.clampX(startX + dx.toInt(), boxSize, screenWidth)
                        boxParams.y = BubbleGeometry.clampY(startY + dy.toInt(), boxSize, screenHeight, topInset)
                        updateBox()
                    }
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(longPressTask)
                    if (dragging) {
                        finishDrag()
                    } else if (!longPressed) {
                        view.performClick()
                    }
                    return true
                }
                MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPressTask)
                    if (dragging) finishDrag()
                    return true
                }
            }
            return false
        }
    }

    // ---------------------------------------------------------------- helpers

    private fun isDarkMode(): Boolean =
        (appContext.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    private fun dp(value: Int): Int = (value * density + 0.5f).toInt()

    private companion object {
        const val TAG: String = "BubbleOverlay"

        const val BUBBLE_DP: Int = 56
        const val BADGE_DP: Int = 44
        const val BADGE_INSET_DP: Int = 6
        const val BOX_DP: Int = 84
        const val PANEL_MAX_DP: Int = 300
        const val PANEL_GAP_DP: Int = 12
        const val MIN_TOUCH_DP: Int = 44
        const val MAX_PANEL_LINES: Int = 6

        const val IDLE_ALPHA: Float = 0.85f
        const val PULSE_MS: Long = 1100L
        const val PULSE_GROWTH: Float = 0.45f
        const val PULSE_ALPHA: Float = 0.7f
        const val SNAP_MS: Long = 160L

        val COLOR_IDLE: Int = Color.parseColor("#1E5BFF")
        val COLOR_LISTENING: Int = Color.parseColor("#1B9E5A")
        val COLOR_SPEAKING: Int = Color.parseColor("#7B4DFF")
        val COLOR_THINKING: Int = Color.parseColor("#F29900")
        val COLOR_STOPPED: Int = Color.parseColor("#C62828")
        val COLOR_BADGE: Int = Color.parseColor("#D32F2F")

        val PANEL_LIGHT: Int = Color.parseColor("#FFFFFF")
        val PANEL_DARK: Int = Color.parseColor("#2B2D31")
        val TEXT_ON_LIGHT: Int = Color.parseColor("#202124")
        val TEXT_ON_DARK: Int = Color.parseColor("#E8EAED")
        val BUTTON_LIGHT: Int = Color.parseColor("#E8EEF9")
        val BUTTON_DARK: Int = Color.parseColor("#3C4043")
        val RIPPLE_COLOR: Int = Color.parseColor("#33000000")
    }
}
EOF

# ---------- 12. NovaBubbleService.kt ----------
cat > "$BASE/bubble/NovaBubbleService.kt" <<'EOF'
package com.nova.ai.bubble

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.nova.ai.MainActivity
import com.nova.ai.R
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.security.EmergencyStop
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.SettingsRepository
import com.nova.ai.voice.AndroidVoiceEngine
import com.nova.ai.voice.ConversationController
import com.nova.ai.voice.ConversationEnd
import com.nova.ai.voice.ConversationListener
import com.nova.ai.voice.ConversationState
import com.nova.ai.voice.VoiceFocus
import com.nova.ai.voice.toSpeechLanguage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * Keeps the floating bubble alive. A foreground service (type microphone) is used so Android
 * lets the microphone work while another app is on the screen. The service owns the bubble
 * window, one listening turn at a time, and the command router. Everything runs on the main thread.
 *
 * Tap the bubble: speak one command. Long press: menu. The red badge and the notification
 * button switch the emergency stop on; the bubble then shows a Resume button.
 */
class NovaBubbleService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private lateinit var settings: SettingsRepository
    private lateinit var overlay: BubbleOverlay
    private lateinit var router: BubbleCommandRouter
    private lateinit var voiceEngine: AndroidVoiceEngine
    private lateinit var conversation: ConversationController
    private lateinit var texts: ResourceBubbleTexts

    private var conversationState: ConversationState = ConversationState.IDLE
    private var routing: Boolean = false
    private var running: Boolean = false
    private var destroyed: Boolean = false

    private val emergencyListener: (Boolean) -> Unit = { _ -> handler.post { onEmergencyChanged() } }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // The channel comes first: even a service that cannot start must be able to show its notification.
        try {
            createChannel()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not create the notification channel", e)
        }
        try {
            settings = SettingsRepository(applicationContext)
            texts = ResourceBubbleTexts(this)
            overlay = BubbleOverlay(this, BubblePrefs(this), overlayCallbacks)
            router = BubbleCommandRouter(
                context = this,
                scope = scope,
                texts = texts,
                onOutput = { output -> showOutput(output) },
                onBusyChanged = { busy ->
                    routing = busy
                    refreshState()
                }
            )
            voiceEngine = AndroidVoiceEngine(
                context = this,
                languageProvider = { settings.getLanguage() },
                speechRateProvider = { settings.getSpeechSpeed().rate }
            )
            conversation = ConversationController(
                engine = voiceEngine,
                listener = conversationListener,
                continuousProvider = { false },
                replyProvider = { _ -> null }
            )
        } catch (e: Exception) {
            // Without these parts the bubble cannot work; onStartCommand sees `running` is false and stops.
            NovaLogger.e(TAG, "Bubble service could not be created", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action: String? = intent?.action
        if (!isReady()) {
            // startForegroundService() demands a notification even when we give up right away.
            if (action == null || action == ACTION_START) enterForeground()
            stopSelf()
            return START_NOT_STICKY
        }
        when (action) {
            ACTION_EMERGENCY_STOP -> {
                EmergencyStop.trigger(SOURCE_NOTIFICATION)
                if (!running) stopSelf()
            }
            ACTION_RESUME -> {
                EmergencyStop.release(SOURCE_NOTIFICATION)
                if (!running) stopSelf()
            }
            ACTION_CLOSE -> {
                stopSelf()
            }
            else -> startBubble()
        }
        // If Android kills the service, the bubble stays closed until the user opens it again.
        return START_NOT_STICKY
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (running) overlay.onConfigurationChanged()
    }

    override fun onDestroy() {
        destroyed = true
        try {
            EmergencyStop.removeListener(emergencyListener)
            EmergencyStop.unregisterHook(HOOK_KEY)
            VoiceFocus.unregister(VOICE_OWNER)
            if (isReady()) {
                conversation.shutdown()
                router.release()
                voiceEngine.shutdown()
                overlay.hide()
            }
            scope.cancel()
            handler.removeCallbacksAndMessages(null)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Bubble service did not close cleanly", e)
        }
        running = false
        BubbleController.isRunning = false
        super.onDestroy()
    }

    // ---------------------------------------------------------------- start

    private fun isReady(): Boolean = this::overlay.isInitialized && this::conversation.isInitialized

    private fun startBubble() {
        if (running) return
        // A foreground service must show its notification within seconds of being started.
        if (!enterForeground()) {
            stopSelf()
            return
        }
        if (!BubbleController.canDrawOverlays(this) || !overlay.show()) {
            NovaLogger.w(TAG, "No permission to draw the bubble; stopping")
            stopSelf()
            return
        }
        running = true
        BubbleController.isRunning = true
        VoiceFocus.register(VOICE_OWNER) { handler.post { stopListeningTurn() } }
        EmergencyStop.registerHook(HOOK_KEY) { handler.post { onEmergencyHook() } }
        EmergencyStop.addListener(emergencyListener)
        refreshState()
        NovaLogger.i(TAG, "Bubble started")
    }

    private fun enterForeground(): Boolean = try {
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        )
        true
    } catch (e: Exception) {
        // For example Android 14 refuses a microphone service started from the background.
        NovaLogger.e(TAG, "Could not enter the foreground", e)
        false
    }

    // ---------------------------------------------------------------- bubble touches

    private val overlayCallbacks = object : BubbleOverlayCallbacks {
        override fun onBubbleTap() = handleTap()
        override fun onBubbleLongPress() = showMenu()
        override fun onStopBadgeTap() {
            EmergencyStop.trigger(SOURCE_BADGE)
        }
    }

    private fun handleTap() {
        if (EmergencyStop.isActive) {
            showResumePanel()
            return
        }
        if (conversation.isActive()) {
            // A second tap while listening cancels it.
            conversation.stop()
            overlay.hidePanel()
            return
        }
        startListeningTurn()
    }

    private fun startListeningTurn() {
        overlay.hidePanel()
        router.cancel()
        VoiceFocus.claim(VOICE_OWNER)
        when (val result: NovaResult<Unit> = conversation.start()) {
            is NovaResult.Success -> overlay.showStatus(getString(R.string.bub_listening), null, 0L)
            is NovaResult.Failure -> {
                val text: String = if (result.error.code == ErrorCode.PERMISSION_DENIED) {
                    getString(R.string.bub_mic_needed)
                } else {
                    result.error.message
                }
                overlay.showStatus(text, MessageKind.ERROR, STATUS_MS)
            }
        }
    }

    private fun stopListeningTurn() {
        if (!isReady() || destroyed) return
        try {
            conversation.stop()
            voiceEngine.stopSpeaking()
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not stop the listening turn", e)
        }
    }

    private fun showMenu() {
        val buttons: MutableList<PanelButton> = mutableListOf(
            PanelButton(getString(R.string.bub_menu_open), PanelStyle.PRIMARY) { openNova() }
        )
        if (EmergencyStop.isActive) {
            buttons.add(PanelButton(getString(R.string.bub_menu_resume)) { EmergencyStop.release(SOURCE_MENU) })
        } else {
            buttons.add(PanelButton(getString(R.string.bub_menu_stop)) { EmergencyStop.trigger(SOURCE_MENU) })
        }
        buttons.add(PanelButton(getString(R.string.bub_menu_close)) { stopSelf() })
        overlay.showPanel(getString(R.string.bub_menu_title), buttons, MENU_MS, null)
    }

    private fun showResumePanel() {
        val buttons: List<PanelButton> = listOf(
            PanelButton(getString(R.string.bub_menu_resume), PanelStyle.PRIMARY) { EmergencyStop.release(SOURCE_PANEL) },
            PanelButton(getString(R.string.bub_menu_close)) { stopSelf() }
        )
        overlay.showPanel(EmergencyStop.MESSAGE, buttons, QUESTION_MS, null)
    }

    private fun openNova() {
        try {
            val intent = Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            startActivity(intent)
        } catch (e: Exception) {
            // Android may block opening a screen from the background; the notification still opens it.
            NovaLogger.w(TAG, "Could not open NOVA from the bubble", e)
            overlay.showStatus(getString(R.string.bub_open_blocked), MessageKind.INFO, STATUS_MS)
        }
    }

    // ---------------------------------------------------------------- conversation

    private val conversationListener = object : ConversationListener {
        override fun onStateChanged(state: ConversationState) {
            conversationState = state
            refreshState()
        }

        override fun onPartialText(text: String) {
            if (text.isNotBlank()) overlay.showStatus("“$text”", null, 0L)
        }

        override fun onCommand(command: VoiceCommand) {
            overlay.showStatus("“${command.rawText}”", null, 0L)
            router.handle(command.rawText)
        }

        override fun onEnded(reason: ConversationEnd) {
            when (reason) {
                is ConversationEnd.SingleCompleted, is ConversationEnd.UserStopped -> Unit
                is ConversationEnd.StopPhrase -> overlay.hidePanel()
                is ConversationEnd.SilenceTimeout ->
                    overlay.showStatus(getString(R.string.bub_not_heard), MessageKind.INFO, STATUS_MS)
                is ConversationEnd.Failed -> {
                    val code: ErrorCode = reason.error.code
                    val text: String = if (code == ErrorCode.TIMEOUT || code == ErrorCode.NOT_FOUND) {
                        getString(R.string.bub_not_heard)
                    } else {
                        reason.error.message
                    }
                    overlay.showStatus(text, MessageKind.ERROR, STATUS_MS)
                }
            }
        }
    }

    // ---------------------------------------------------------------- showing what the router found

    private fun showOutput(output: BubbleOutput) {
        when (output) {
            is BubbleOutput.None -> Unit
            is BubbleOutput.Message -> {
                overlay.showStatus(output.text, output.kind, if (output.kind == MessageKind.ERROR) STATUS_MS else DONE_MS)
                speakResult(output.text)
            }
            is BubbleOutput.Decision -> {
                val buttons: MutableList<PanelButton> = output.options.map { option ->
                    PanelButton(
                        label = option.label,
                        style = if (option.emphasis) PanelStyle.PRIMARY else PanelStyle.NORMAL
                    ) { router.choose(output, option) }
                }.toMutableList()
                buttons.add(PanelButton(getString(R.string.bub_cancel)) { router.dismissQuestion() })
                overlay.showPanel(output.question, buttons, QUESTION_MS) { router.dismissQuestion() }
                speakResult(output.question)
            }
            is BubbleOutput.NeedsApp -> {
                val buttons: List<PanelButton> = listOf(
                    PanelButton(getString(R.string.bub_menu_open), PanelStyle.PRIMARY) { openNova() },
                    PanelButton(getString(R.string.bub_cancel)) { router.dismissQuestion() }
                )
                overlay.showPanel(output.text, buttons, QUESTION_MS) { router.dismissQuestion() }
            }
        }
    }

    // Speaks the result when voice replies are on and NOVA is not stopped.
    private fun speakResult(text: String) {
        if (EmergencyStop.isActive) return
        try {
            if (!settings.isVoiceReplyEnabled()) return
            val language: AppLanguage = settings.getLanguage()
            voiceEngine.speak(text, language.toSpeechLanguage())
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not speak the result", e)
        }
    }

    // ---------------------------------------------------------------- emergency stop

    // Runs for every stop, on the main thread: nothing may go on working.
    private fun onEmergencyHook() {
        if (!isReady() || destroyed) return
        router.cancel()
        router.dismissQuestion()
        stopListeningTurn()
        overlay.hidePanel()
    }

    private fun onEmergencyChanged() {
        if (!running || destroyed) return
        refreshState()
        updateNotification()
        if (EmergencyStop.isActive) {
            overlay.showStatus(EmergencyStop.MESSAGE, MessageKind.ERROR, STATUS_MS)
        } else {
            overlay.hidePanel()
        }
    }

    private fun refreshState() {
        if (!isReady() || destroyed) return
        overlay.setState(BubbleStateMapper.map(EmergencyStop.isActive, conversationState, routing))
    }

    // ---------------------------------------------------------------- notification

    private fun createChannel() {
        val manager: NotificationManager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.bub_channel_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply { setShowBadge(false) }
        manager.createNotificationChannel(channel)
    }

    private fun updateNotification() {
        try {
            getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, buildNotification())
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not update the notification", e)
        }
    }

    private fun buildNotification(): Notification {
        val stopped: Boolean = EmergencyStop.isActive
        val open: PendingIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PENDING_FLAGS
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_nova_bubble)
            .setContentTitle(getString(R.string.bub_notif_title))
            .setContentText(getString(if (stopped) R.string.bub_notif_stopped else R.string.bub_notif_text))
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        if (stopped) {
            builder.addAction(0, getString(R.string.bub_menu_resume), servicePending(ACTION_RESUME, 1))
        } else {
            builder.addAction(0, getString(R.string.bub_notif_stop), servicePending(ACTION_EMERGENCY_STOP, 2))
        }
        builder.addAction(0, getString(R.string.bub_menu_close), servicePending(ACTION_CLOSE, 3))
        return builder.build()
    }

    private fun servicePending(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, NovaBubbleService::class.java).setAction(action)
        return PendingIntent.getService(this, requestCode, intent, PENDING_FLAGS)
    }

    companion object {
        private const val TAG: String = "NovaBubbleService"
        private const val CHANNEL_ID: String = "nova_bubble"
        private const val NOTIFICATION_ID: Int = 2201
        private const val PENDING_FLAGS: Int = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        private const val VOICE_OWNER: String = "bubble"
        private const val HOOK_KEY: String = "bubble"
        private const val SOURCE_BADGE: String = "bubble badge"
        private const val SOURCE_MENU: String = "bubble menu"
        private const val SOURCE_PANEL: String = "bubble panel"
        private const val SOURCE_NOTIFICATION: String = "notification"

        private const val STATUS_MS: Long = 4000L
        private const val DONE_MS: Long = 3500L
        private const val MENU_MS: Long = 8000L
        private const val QUESTION_MS: Long = 20000L

        /** Starts the bubble. */
        const val ACTION_START: String = "com.nova.ai.bubble.START"

        /** Switches the emergency stop on. */
        const val ACTION_EMERGENCY_STOP: String = "com.nova.ai.bubble.EMERGENCY_STOP"

        /** Switches the emergency stop off. */
        const val ACTION_RESUME: String = "com.nova.ai.bubble.RESUME"

        /** Closes the bubble. */
        const val ACTION_CLOSE: String = "com.nova.ai.bubble.CLOSE"
    }
}
EOF

# ---------- 13. NovaStopTileService.kt ----------
cat > "$BASE/bubble/NovaStopTileService.kt" <<'EOF'
package com.nova.ai.bubble

import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.nova.ai.R
import com.nova.ai.logging.NovaLogger
import com.nova.ai.security.EmergencyStop

/**
 * Quick Settings tile for the emergency stop. It works from the notification shade over any app,
 * even if the bubble is closed. Tap once to stop NOVA, tap again to let it work.
 */
class NovaStopTileService : TileService() {

    private val handler = Handler(Looper.getMainLooper())
    private val listener: (Boolean) -> Unit = { _ -> handler.post { refreshTile() } }

    override fun onStartListening() {
        super.onStartListening()
        EmergencyStop.addListener(listener)
        refreshTile()
    }

    override fun onStopListening() {
        EmergencyStop.removeListener(listener)
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        if (EmergencyStop.isActive) {
            EmergencyStop.release(SOURCE)
        } else {
            EmergencyStop.trigger(SOURCE)
        }
        refreshTile()
    }

    private fun refreshTile() {
        val tile: Tile = qsTile ?: return
        try {
            val stopped: Boolean = EmergencyStop.isActive
            tile.state = if (stopped) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            tile.label = getString(R.string.bub_tile_stop_label)
            tile.contentDescription = getString(
                if (stopped) R.string.bub_tile_stop_on else R.string.bub_tile_stop_off
            )
            tile.updateTile()
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not update the stop tile", e)
        }
    }

    private companion object {
        const val TAG: String = "NovaStopTile"
        const val SOURCE: String = "quick tile"
    }
}
EOF

# ---------- 14. NovaBubbleTileService.kt ----------
cat > "$BASE/bubble/NovaBubbleTileService.kt" <<'EOF'
package com.nova.ai.bubble

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.nova.ai.MainActivity
import com.nova.ai.R
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * Quick Settings tile that shows or hides the floating bubble. If the bubble cannot start
 * (a permission is missing), the NOVA app opens so the user can allow it.
 */
class NovaBubbleTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        if (BubbleController.isRunning) {
            BubbleController.stop(this)
        } else if (BubbleController.start(this) is NovaResult.Failure) {
            openApp()
        }
        refreshTile()
    }

    private fun refreshTile() {
        val tile: Tile = qsTile ?: return
        try {
            tile.state = if (BubbleController.isRunning) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            tile.label = getString(R.string.bub_tile_bubble_label)
            tile.updateTile()
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not update the bubble tile", e)
        }
    }

    // Opens the NOVA app and closes the shade. Android 14 wants a PendingIntent for this.
    @Suppress("DEPRECATION")
    private fun openApp() {
        try {
            val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val pending: PendingIntent = PendingIntent.getActivity(
                    this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                startActivityAndCollapse(pending)
            } else {
                startActivityAndCollapse(intent)
            }
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not open the app from the tile", e)
        }
    }

    private companion object {
        const val TAG: String = "NovaBubbleTile"
    }
}
EOF

# ---------- 15. BubbleCard.kt ----------
cat > "$BASE/ui/components/BubbleCard.kt" <<'EOF'
package com.nova.ai.ui.components

import android.content.Context
import android.widget.Toast
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.nova.ai.R
import com.nova.ai.bubble.BubbleController
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import com.nova.ai.security.EmergencyStop

/**
 * Controls for the floating bubble: allow drawing over other apps, show or hide the bubble,
 * and the emergency stop. The permission status is checked again whenever the screen returns
 * from the Android settings.
 */
@Composable
fun BubbleCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val running: Boolean = BubbleController.isRunning
    val stopped: Boolean = EmergencyStop.isActive

    var overlayAllowed: Boolean by remember { mutableStateOf(BubbleController.canDrawOverlays(context)) }
    var micAllowed: Boolean by remember { mutableStateOf(BubbleController.hasMicrophone(context)) }

    val lifecycleOwner: LifecycleOwner? = context as? LifecycleOwner
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                overlayAllowed = BubbleController.canDrawOverlays(context)
                micAllowed = BubbleController.hasMicrophone(context)
            }
        }
        lifecycleOwner?.lifecycle?.addObserver(observer)
        onDispose { lifecycleOwner?.lifecycle?.removeObserver(observer) }
    }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.bub_card_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.bub_card_note),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(
                    if (running) R.string.bub_card_running else R.string.bub_card_not_running
                ),
                style = MaterialTheme.typography.bodyMedium
            )
            if (stopped) {
                Text(
                    text = EmergencyStop.MESSAGE,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }

            if (!overlayAllowed) {
                Text(
                    text = stringResource(R.string.bub_card_overlay_missing),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
                Button(
                    onClick = { openOverlaySettings(context) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.bub_card_allow_overlay))
                }
            }
            if (!micAllowed) {
                Text(
                    text = stringResource(R.string.bub_card_mic_missing),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }

            if (running) {
                OutlinedButton(
                    onClick = { BubbleController.stop(context) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.bub_card_hide))
                }
            } else {
                Button(
                    onClick = { startBubble(context) },
                    enabled = overlayAllowed && micAllowed,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.bub_card_show))
                }
            }

            if (stopped) {
                Button(
                    onClick = { EmergencyStop.release(SOURCE) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.bub_menu_resume))
                }
            } else {
                OutlinedButton(
                    onClick = { EmergencyStop.trigger(SOURCE) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.bub_card_stop))
                }
            }
        }
    }
}

private const val TAG: String = "BubbleCard"
private const val SOURCE: String = "bubble card"

private fun startBubble(context: Context) {
    when (val result: NovaResult<Unit> = BubbleController.start(context)) {
        is NovaResult.Success -> Unit
        is NovaResult.Failure -> {
            NovaLogger.w(TAG, "Bubble did not start: ${result.error.message}")
            Toast.makeText(context, result.error.message, Toast.LENGTH_LONG).show()
        }
    }
}

private fun openOverlaySettings(context: Context) {
    try {
        context.startActivity(BubbleController.overlaySettingsIntent(context))
    } catch (e: Exception) {
        NovaLogger.w(TAG, "Could not open the overlay settings", e)
        Toast.makeText(context, context.getString(R.string.bub_card_settings_failed), Toast.LENGTH_LONG).show()
    }
}
EOF

# ---------- 16. strings_p22.xml ----------
cat > "$RES/values/strings_p22.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Bubble: panel texts -->
    <string name="bub_opened">%1$s খোলা হয়েছে।</string>
    <string name="bub_confirm_app">%1$s খুলবো?</string>
    <string name="bub_choose_app">“%1$s” — কোন অ্যাপ খুলবো?</string>
    <string name="bub_suggest_app">“%1$s” নামে অ্যাপ তালিকায় নেই। ফোনের কোনটা খুলবো?</string>
    <string name="bub_app_not_found">“%1$s” নামে কোনো অ্যাপ পাইনি।</string>
    <string name="bub_choose_contact">“%1$s” — কাকে ফোন করবো?</string>
    <string name="bub_choose_number">%1$s-এর কোন নম্বরে ফোন করবো?</string>
    <string name="bub_confirm_call">%1$s-কে (%2$s) ফোন করবো?</string>
    <string name="bub_contact_not_found">“%1$s” নামে কাউকে পাইনি।</string>
    <string name="bub_ask_period">%1$s — কোনটা?</string>
    <string name="bub_needs_contacts">কন্টাক্ট দেখার অনুমতি লাগবে। নোভা অ্যাপ খুলে অনুমতি দিন।</string>
    <string name="bub_yes_open">হ্যাঁ, খোলো</string>
    <string name="bub_call_now">এখনই ফোন করো</string>
    <string name="bub_cancel">বাদ দিন</string>
    <string name="bub_not_understood">কথাটা বুঝতে পারিনি। আবার বলুন।</string>
    <string name="bub_not_done">কাজটা শেষ করা যায়নি।</string>
    <string name="bub_listening">শুনছি… বলুন</string>
    <string name="bub_not_heard">কিছু শুনতে পাইনি। আবার চেপে বলুন।</string>
    <string name="bub_open_blocked">নোভা অ্যাপ এখান থেকে খোলা গেল না। নোটিফিকেশনে চাপ দিন।</string>

    <!-- Bubble: start problems -->
    <string name="bub_need_overlay">অন্য অ্যাপের উপরে দেখানোর অনুমতি লাগবে।</string>
    <string name="bub_need_mic">মাইক্রোফোনের অনুমতি লাগবে।</string>
    <string name="bub_start_failed">বাবল চালু করা যায়নি।</string>
    <string name="bub_mic_needed">মাইক্রোফোনের অনুমতি নেই। নোভা অ্যাপে অনুমতি দিন।</string>

    <!-- Bubble: accessibility descriptions -->
    <string name="bub_desc_idle">নোভা বাবল। চাপ দিয়ে কথা বলুন, ধরে রাখলে মেনু।</string>
    <string name="bub_desc_listening">নোভা শুনছে। বাদ দিতে আবার চাপ দিন।</string>
    <string name="bub_desc_speaking">নোভা বলছে।</string>
    <string name="bub_desc_thinking">নোভা কাজ করছে।</string>
    <string name="bub_desc_stopped">নোভা থামানো আছে। ছাড়তে চাপ দিন।</string>
    <string name="bub_desc_badge">নোভা জরুরি Stop</string>

    <!-- Bubble: menu -->
    <string name="bub_menu_title">নোভা</string>
    <string name="bub_menu_open">নোভা অ্যাপ খোলো</string>
    <string name="bub_menu_stop">জরুরি Stop</string>
    <string name="bub_menu_resume">Stop ছাড়ুন</string>
    <string name="bub_menu_close">বাবল বন্ধ করুন</string>

    <!-- Bubble: notification and tiles -->
    <string name="bub_channel_name">ভাসমান বাবল</string>
    <string name="bub_notif_title">নোভা বাবল চালু আছে</string>
    <string name="bub_notif_text">বাবলে চাপ দিয়ে কথা বলুন।</string>
    <string name="bub_notif_stopped">জরুরি Stop চালু। নোভা কোনো কাজ করবে না।</string>
    <string name="bub_notif_stop">জরুরি Stop</string>
    <string name="bub_tile_stop_label">নোভা Stop</string>
    <string name="bub_tile_stop_on">নোভা থামানো আছে</string>
    <string name="bub_tile_stop_off">নোভা কাজ করতে পারে</string>
    <string name="bub_tile_bubble_label">নোভা বাবল</string>

    <!-- Bubble card (Access screen) -->
    <string name="bub_card_title">ভাসমান বাবল ও জরুরি Stop</string>
    <string name="bub_card_note">গোল মাইক বাবল সব অ্যাপের উপরে থাকে। চাপ দিয়ে এক কমান্ড বলুন: অ্যাপ খোলা, ভলিউম, টর্চ, কল, অ্যালার্ম, গান। বাবল সরানো যায়। লাল ⏹ বা কুইক সেটিংসের “নোভা Stop” সব বন্ধ করে।</string>
    <string name="bub_card_running">বাবল চালু আছে।</string>
    <string name="bub_card_not_running">বাবল বন্ধ আছে।</string>
    <string name="bub_card_overlay_missing">অন্য অ্যাপের উপরে দেখানোর অনুমতি দেওয়া নেই।</string>
    <string name="bub_card_allow_overlay">অনুমতি দিতে সেটিংস খুলুন</string>
    <string name="bub_card_mic_missing">মাইক্রোফোনের অনুমতি নেই। হোম স্ক্রিনে মাইক চেপে অনুমতি দিন।</string>
    <string name="bub_card_show">বাবল চালু করুন</string>
    <string name="bub_card_hide">বাবল বন্ধ করুন</string>
    <string name="bub_card_stop">জরুরি Stop</string>
    <string name="bub_card_settings_failed">সেটিংস খোলা যায়নি।</string>
</resources>
EOF

# ---------- 17. ic_nova_bubble.xml ----------
cat > "$RES/drawable/ic_nova_bubble.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M12,14c1.66,0 3,-1.34 3,-3V5c0,-1.66 -1.34,-3 -3,-3S9,3.34 9,5v6c0,1.66 1.34,3 3,3zM17.3,11c0,3 -2.54,5.1 -5.3,5.1S6.7,14 6.7,11H5c0,3.41 2.72,6.23 6,6.72V21h2v-3.28c3.28,-0.48 6,-3.3 6,-6.72h-1.7z" />
</vector>
EOF

# ---------- 18. EmergencyStopControllerTest.kt ----------
cat > "$TEST/security/EmergencyStopControllerTest.kt" <<'EOF'
package com.nova.ai.security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests the logic of the emergency stop. Plain JVM test, no phone needed. */
class EmergencyStopControllerTest {

    private var stopped = false
    private val errors = mutableListOf<String>()
    private val events = mutableListOf<String>()

    private fun controller() = EmergencyStopController(
        readStopped = { stopped },
        writeStopped = { stopped = it },
        onHookError = { key, _ -> errors.add(key) },
        onEvent = { events.add(it) }
    )

    @Test
    fun triggerSwitchesTheStopOnAndReleaseSwitchesItOff() {
        val c = controller()
        assertFalse(c.isActive)
        assertTrue(c.trigger("test"))
        assertTrue(c.isActive)
        assertTrue(c.release("test"))
        assertFalse(c.isActive)
    }

    @Test
    fun secondTriggerReportsNoChangeButStillRunsTheHooks() {
        val c = controller()
        var runs = 0
        c.registerHook("a") { runs += 1 }
        assertTrue(c.trigger("one"))
        assertFalse(c.trigger("two"))
        assertEquals(2, runs)
    }

    @Test
    fun releaseWhenNotStoppedReportsNoChange() {
        assertFalse(controller().release("test"))
    }

    @Test
    fun aFailingHookDoesNotBlockTheOthers() {
        val c = controller()
        var ran = false
        c.registerHook("bad") { throw IllegalStateException("boom") }
        c.registerHook("good") { ran = true }
        c.trigger("test")
        assertTrue(ran)
        assertEquals(listOf("bad"), errors)
        assertTrue(c.isActive)
    }

    @Test
    fun registeringTheSameKeyReplacesTheHook() {
        val c = controller()
        var first = 0
        var second = 0
        c.registerHook("k") { first += 1 }
        c.registerHook("k") { second += 1 }
        c.trigger("test")
        assertEquals(0, first)
        assertEquals(1, second)
    }

    @Test
    fun unregisteredHookDoesNotRun() {
        val c = controller()
        var runs = 0
        c.registerHook("k") { runs += 1 }
        c.unregisterHook("k")
        c.trigger("test")
        assertEquals(0, runs)
    }

    @Test
    fun listenersHearOnlyRealChanges() {
        val c = controller()
        val heard = mutableListOf<Boolean>()
        c.addListener { heard.add(it) }
        c.trigger("a")
        c.trigger("b")
        c.release("a")
        c.release("b")
        assertEquals(listOf(true, false), heard)
    }

    @Test
    fun removedListenerHearsNothing() {
        val c = controller()
        val heard = mutableListOf<Boolean>()
        val listener: (Boolean) -> Unit = { heard.add(it) }
        c.addListener(listener)
        c.removeListener(listener)
        c.trigger("a")
        assertTrue(heard.isEmpty())
    }

    @Test
    fun hooksMayRegisterAnotherHookWhileRunning() {
        val c = controller()
        var lateRuns = 0
        c.registerHook("first") { c.registerHook("late") { lateRuns += 1 } }
        c.trigger("a")
        assertEquals(0, lateRuns)
        c.trigger("b")
        assertEquals(1, lateRuns)
    }

    @Test
    fun theSourceIsLogged() {
        val c = controller()
        c.trigger("quick tile")
        assertTrue(events.single().contains("quick tile"))
    }
}
EOF

# ---------- 19. VoiceFocusRegistryTest.kt ----------
cat > "$TEST/voice/VoiceFocusRegistryTest.kt" <<'EOF'
package com.nova.ai.voice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests that only one voice user listens at a time. Plain JVM test. */
class VoiceFocusRegistryTest {

    @Test
    fun claimStopsEveryoneElseButNotTheClaimer() {
        val registry = VoiceFocusRegistry()
        val stopped = mutableListOf<String>()
        registry.register("home") { stopped.add("home") }
        registry.register("bubble") { stopped.add("bubble") }
        registry.claim("bubble")
        assertEquals(listOf("home"), stopped)
    }

    @Test
    fun stopAllStopsEveryone() {
        val registry = VoiceFocusRegistry()
        val stopped = mutableListOf<String>()
        registry.register("home") { stopped.add("home") }
        registry.register("bubble") { stopped.add("bubble") }
        registry.stopAll()
        assertEquals(listOf("home", "bubble"), stopped)
    }

    @Test
    fun unregisteredOwnerIsNotStopped() {
        val registry = VoiceFocusRegistry()
        var runs = 0
        registry.register("home") { runs += 1 }
        registry.unregister("home")
        registry.stopAll()
        assertEquals(0, runs)
    }

    @Test
    fun aFailingStopIsReportedAndOthersStillRun() {
        val failed = mutableListOf<String>()
        val registry = VoiceFocusRegistry { owner, _ -> failed.add(owner) }
        var ran = false
        registry.register("bad") { throw IllegalStateException("boom") }
        registry.register("good") { ran = true }
        registry.stopAll()
        assertTrue(ran)
        assertEquals(listOf("bad"), failed)
    }

    @Test
    fun registeringAgainReplacesTheStopAction() {
        val registry = VoiceFocusRegistry()
        var old = 0
        var new = 0
        registry.register("home") { old += 1 }
        registry.register("home") { new += 1 }
        registry.stopAll()
        assertEquals(0, old)
        assertEquals(1, new)
    }
}
EOF

# ---------- 20. BubbleGeometryTest.kt ----------
cat > "$TEST/bubble/BubbleGeometryTest.kt" <<'EOF'
package com.nova.ai.bubble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests where the bubble and its panel go. Plain JVM test, no phone needed. */
class BubbleGeometryTest {

    private val screenW = 1080
    private val screenH = 2400
    private val box = 220
    private val inset = 80

    @Test
    fun leftHalfIsLeftAndRightHalfIsRight() {
        assertFalse(BubbleGeometry.isRightSide(100, box, screenW))
        assertTrue(BubbleGeometry.isRightSide(800, box, screenW))
    }

    @Test
    fun snapGoesToTheNearestEdge() {
        assertEquals(0, BubbleGeometry.snapX(150, box, screenW))
        assertEquals(screenW - box, BubbleGeometry.snapX(700, box, screenW))
    }

    @Test
    fun clampKeepsTheBoxOnTheScreen() {
        assertEquals(0, BubbleGeometry.clampX(-50, box, screenW))
        assertEquals(screenW - box, BubbleGeometry.clampX(5000, box, screenW))
        assertEquals(inset, BubbleGeometry.clampY(0, box, screenH, inset))
        assertEquals(screenH - box, BubbleGeometry.clampY(9999, box, screenH, inset))
    }

    @Test
    fun fractionRoundTripsAndSurvivesATurnedScreen() {
        val y = 900
        val f = BubbleGeometry.yToFraction(y, box, screenH, inset)
        assertTrue(kotlin.math.abs(y - BubbleGeometry.fractionToY(f, box, screenH, inset)) <= 1)
        // Landscape: the same fraction lands inside the smaller screen.
        val turned = BubbleGeometry.fractionToY(f, box, 1080, inset)
        assertTrue(turned in inset..(1080 - box))
    }

    @Test
    fun badFractionsAreSafe() {
        assertEquals(inset, BubbleGeometry.fractionToY(Float.NaN, box, screenH, inset))
        assertEquals(inset, BubbleGeometry.fractionToY(-3f, box, screenH, inset))
        assertEquals(screenH - box, BubbleGeometry.fractionToY(7f, box, screenH, inset))
        assertEquals(0f, BubbleGeometry.yToFraction(100, box, 100, inset), 0f)
    }

    private fun panel(boxX: Int, boxY: Int, h: Int = 300): BubblePoint =
        BubbleGeometry.panelPosition(boxX, boxY, box, box, 800, h, screenW, screenH, 30)

    @Test
    fun panelGoesAboveTheBubbleWhenThereIsRoom() {
        val p = panel(screenW - box, 1500)
        assertEquals(1500 - 30 - 300, p.y)
    }

    @Test
    fun panelGoesBelowWhenTheBubbleIsAtTheTop() {
        val p = panel(screenW - box, inset)
        assertEquals(inset + box + 30, p.y)
    }

    @Test
    fun panelStaysInsideTheScreenHorizontally() {
        val right = panel(screenW - box, 1500)
        val left = panel(0, 1500)
        assertTrue(right.x >= 30 && right.x + 800 <= screenW - 30)
        assertTrue(left.x >= 30)
    }

    @Test
    fun aVeryTallPanelIsStillClampedOnTheScreen() {
        val p = panel(0, 1200, h = 2300)
        assertTrue(p.y >= 30)
    }
}
EOF

# ---------- 21. BubbleStateMapperTest.kt ----------
cat > "$TEST/bubble/BubbleStateMapperTest.kt" <<'EOF'
package com.nova.ai.bubble

import com.nova.ai.voice.ConversationState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests which look the bubble takes. Plain JVM test. */
class BubbleStateMapperTest {

    @Test
    fun emergencyStopWinsOverEverything() {
        for (c in ConversationState.values()) {
            assertEquals(BubbleState.STOPPED, BubbleStateMapper.map(true, c, true))
        }
    }

    @Test
    fun speakingThenListeningThenWorking() {
        assertEquals(BubbleState.SPEAKING, BubbleStateMapper.map(false, ConversationState.SPEAKING, true))
        assertEquals(BubbleState.LISTENING, BubbleStateMapper.map(false, ConversationState.LISTENING, true))
        assertEquals(BubbleState.LISTENING, BubbleStateMapper.map(false, ConversationState.WAITING, false))
        assertEquals(BubbleState.THINKING, BubbleStateMapper.map(false, ConversationState.IDLE, true))
        assertEquals(BubbleState.IDLE, BubbleStateMapper.map(false, ConversationState.IDLE, false))
    }

    @Test
    fun stopBadgeShowsOnlyWhileBusy() {
        assertTrue(BubbleStateMapper.showsStopBadge(BubbleState.LISTENING))
        assertTrue(BubbleStateMapper.showsStopBadge(BubbleState.SPEAKING))
        assertTrue(BubbleStateMapper.showsStopBadge(BubbleState.THINKING))
        assertFalse(BubbleStateMapper.showsStopBadge(BubbleState.IDLE))
        assertFalse(BubbleStateMapper.showsStopBadge(BubbleState.STOPPED))
    }
}
EOF

# ---------- 22. BubbleOutputMapperTest.kt ----------
cat > "$TEST/bubble/BubbleOutputMapperTest.kt" <<'EOF'
package com.nova.ai.bubble

import com.nova.ai.apps.AppActionUi
import com.nova.ai.apps.InstalledApp
import com.nova.ai.apps.RegisteredApp
import com.nova.ai.contacts.Contact
import com.nova.ai.contacts.ContactActionUi
import com.nova.ai.contacts.ContactPurpose
import com.nova.ai.system.OutcomeKind
import com.nova.ai.system.SystemActionOutcome
import com.nova.ai.time.TimeActionUi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests what the bubble shows for each controller state. Plain JVM test. */
class BubbleOutputMapperTest {

    private class FakeTexts : BubbleTexts {
        override fun opened(appLabel: String) = "opened $appLabel"
        override fun confirmApp(appLabel: String) = "confirm $appLabel"
        override fun chooseApp(spoken: String) = "chooseApp $spoken"
        override fun suggestApp(spoken: String) = "suggest $spoken"
        override fun appNotFound(spoken: String) = "noapp $spoken"
        override fun chooseContact(spoken: String) = "chooseContact $spoken"
        override fun chooseNumber(contactName: String) = "chooseNumber $contactName"
        override fun confirmCall(who: String, number: String) = "call $who $number"
        override fun contactNotFound(spoken: String) = "nocontact $spoken"
        override fun askPeriod(clockText: String) = "period $clockText"
        override fun needsContactsPermission() = "needs contacts"
        override fun yesOpen() = "yes"
        override fun callNow() = "callnow"
        override fun notUnderstood() = "?"
        override fun notDone() = "notdone"
    }

    private class RecordingActions : BubbleActions {
        val log = mutableListOf<String>()
        override fun confirmApp() { log.add("confirmApp") }
        override fun chooseApp(app: RegisteredApp) { log.add("chooseApp ${app.label}") }
        override fun addAndOpen(app: InstalledApp) { log.add("addAndOpen ${app.label}") }
        override fun pickContact(contact: Contact) { log.add("pickContact ${contact.name}") }
        override fun pickNumber(number: String) { log.add("pickNumber $number") }
        override fun placeCall(number: String) { log.add("placeCall $number") }
        override fun choosePeriod(isEvening: Boolean) { log.add("period $isEvening") }
    }

    private val actions = RecordingActions()
    private val mapper = BubbleOutputMapper(FakeTexts(), actions)

    private fun map(
        app: AppActionUi = AppActionUi.Idle,
        contact: ContactActionUi = ContactActionUi.Idle,
        time: TimeActionUi = TimeActionUi.Idle,
        system: SystemActionOutcome? = null,
        media: SystemActionOutcome? = null
    ) = mapper.map(app, contact, time, system, media)

    @Test
    fun nothingToShowGivesNone() {
        assertEquals(BubbleOutput.None, map())
    }

    @Test
    fun openedAppIsADoneMessage() {
        val out = map(app = AppActionUi.Opened("Camera")) as BubbleOutput.Message
        assertEquals("opened Camera", out.text)
        assertEquals(MessageKind.DONE, out.kind)
    }

    @Test
    fun callNeverHappensWithoutTheUserTappingCallNow() {
        val out = map(contact = ContactActionUi.ConfirmCall("Rahim", "0171")) as BubbleOutput.Decision
        assertTrue(actions.log.isEmpty())
        val option = out.options.single()
        assertEquals("callnow", option.label)
        option.action()
        assertEquals(listOf("placeCall 0171"), actions.log)
    }

    @Test
    fun confirmCallFallsBackToTheNumberWhenThereIsNoName() {
        val out = map(contact = ContactActionUi.ConfirmCall(null, "0171")) as BubbleOutput.Decision
        assertEquals("call 0171 0171", out.question)
    }

    @Test
    fun contactChoicesAreLimitedToFive() {
        val contacts = (1..9).map { Contact(it.toLong(), "C$it", listOf("0$it")) }
        val out = map(
            contact = ContactActionUi.ChooseContact(ContactPurpose.CALL, "c", contacts, null)
        ) as BubbleOutput.Decision
        assertEquals(5, out.options.size)
        out.options[2].action()
        assertEquals(listOf("pickContact C3"), actions.log)
    }

    @Test
    fun numberChoiceCallsPickNumber() {
        val contact = Contact(1, "Rahim", listOf("01", "02"))
        val out = map(contact = ContactActionUi.ChooseNumber(ContactPurpose.CALL, contact, null)) as BubbleOutput.Decision
        out.options[1].action()
        assertEquals(listOf("pickNumber 02"), actions.log)
    }

    @Test
    fun appConfirmAndChooseAndSuggest() {
        val reg = RegisteredApp("p.a", "Alpha")
        val confirm = map(app = AppActionUi.Confirm("alfa", reg)) as BubbleOutput.Decision
        confirm.options.single().action()
        val choose = map(app = AppActionUi.Choose("a", listOf(reg))) as BubbleOutput.Decision
        choose.options.single().action()
        val suggest = map(app = AppActionUi.Suggest("a", listOf(InstalledApp("p.b", "Beta")))) as BubbleOutput.Decision
        suggest.options.single().action()
        assertEquals(listOf("confirmApp", "chooseApp Alpha", "addAndOpen Beta"), actions.log)
    }

    @Test
    fun periodQuestionOffersMorningAndEvening() {
        val out = map(time = TimeActionUi.AskPeriod(7, 30, null, false)) as BubbleOutput.Decision
        assertEquals(2, out.options.size)
        out.options[0].action()
        out.options[1].action()
        assertEquals(listOf("period false", "period true"), actions.log)
    }

    @Test
    fun permissionProblemsSendTheUserToTheApp() {
        val out = map(system = SystemActionOutcome(OutcomeKind.NEEDS_PERMISSION, "allow")) as BubbleOutput.NeedsApp
        assertEquals("allow", out.text)
        assertTrue(map(contact = ContactActionUi.NeedsContactsPermission) is BubbleOutput.NeedsApp)
    }

    @Test
    fun outcomeKindsBecomeMessageKinds() {
        fun kind(k: OutcomeKind) = (map(system = SystemActionOutcome(k, "m")) as BubbleOutput.Message).kind
        assertEquals(MessageKind.DONE, kind(OutcomeKind.DONE))
        assertEquals(MessageKind.INFO, kind(OutcomeKind.GUIDED))
        assertEquals(MessageKind.INFO, kind(OutcomeKind.HINT))
        assertEquals(MessageKind.ERROR, kind(OutcomeKind.FAILED))
    }

    @Test
    fun contactWinsOverAppAndSystemOverMedia() {
        val both = map(
            app = AppActionUi.Opened("X"),
            contact = ContactActionUi.Done("called")
        ) as BubbleOutput.Message
        assertEquals("called", both.text)
        val sys = map(
            system = SystemActionOutcome(OutcomeKind.DONE, "sys"),
            media = SystemActionOutcome(OutcomeKind.DONE, "media")
        ) as BubbleOutput.Message
        assertEquals("sys", sys.text)
    }
}
EOF

# ---------- Manifest: permissions and services (idempotent) ----------
insert_after "$MANIFEST" "$PERM_ANCHOR" \
'    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />' \
  "SYSTEM_ALERT_WINDOW"

if ! grep -q "NovaBubbleService" "$MANIFEST"; then
  tmp="$(mktemp)"; TMP_FILES+=("$tmp")
  awk '
    $0 == "    </application>" {
      print "        <service"
      print "            android:name=\".bubble.NovaBubbleService\""
      print "            android:exported=\"false\""
      print "            android:foregroundServiceType=\"microphone\" />"
      print ""
      print "        <service"
      print "            android:name=\".bubble.NovaStopTileService\""
      print "            android:exported=\"true\""
      print "            android:icon=\"@drawable/ic_nova_bubble\""
      print "            android:label=\"@string/bub_tile_stop_label\""
      print "            android:permission=\"android.permission.BIND_QUICK_SETTINGS_TILE\">"
      print "            <intent-filter>"
      print "                <action android:name=\"android.service.quicksettings.action.QS_TILE\" />"
      print "            </intent-filter>"
      print "        </service>"
      print ""
      print "        <service"
      print "            android:name=\".bubble.NovaBubbleTileService\""
      print "            android:exported=\"true\""
      print "            android:icon=\"@drawable/ic_nova_bubble\""
      print "            android:label=\"@string/bub_tile_bubble_label\""
      print "            android:permission=\"android.permission.BIND_QUICK_SETTINGS_TILE\">"
      print "            <intent-filter>"
      print "                <action android:name=\"android.service.quicksettings.action.QS_TILE\" />"
      print "            </intent-filter>"
      print "        </service>"
      print ""
    }
    { print }
  ' "$MANIFEST" > "$tmp"
  cat "$tmp" > "$MANIFEST"
fi
grep -q "NovaBubbleTileService" "$MANIFEST" || fail "manifest service edit failed"

# ---------- Command controllers: nothing runs while the emergency stop is on ----------
for f in "$APP_CTRL" "$CONTACT_CTRL" "$TIME_CTRL" "$SYSTEM_CTRL" "$MEDIA_CTRL"; do
  insert_after "$f" "$imp_anchor" "import com.nova.ai.security.EmergencyStop" "import com.nova.ai.security.EmergencyStop"
  add_guard "$f" "    fun handleCommand(text: String) {"
done
add_guard "$APP_CTRL" "    fun confirm() {"
add_guard "$APP_CTRL" "    fun choose(app: RegisteredApp) {"
add_guard "$APP_CTRL" "    fun addAndOpen(app: InstalledApp) {"
add_guard "$CONTACT_CTRL" "    fun pickContact(contact: Contact) {"
add_guard "$CONTACT_CTRL" "    fun pickNumber(number: String) {"
add_guard "$CONTACT_CTRL" "    fun placeCall(number: String) {"
add_guard "$TIME_CTRL" "    fun choosePeriod(isEvening: Boolean) {"

# ---------- Home screen: share the microphone with the bubble ----------
insert_after "$HOME_FILE" "import com.nova.ai.voice.toSpeechLanguage" \
'import com.nova.ai.voice.VoiceFocus
import android.os.Handler
import android.os.Looper' \
  "import com.nova.ai.voice.VoiceFocus"
insert_after "$HOME_FILE" "        lifecycleOwner?.lifecycle?.addObserver(observer)" \
'        // The bubble and the emergency stop stop this screen'"'"'s voice through the shared registry.
        VoiceFocus.register("home") { Handler(Looper.getMainLooper()).post { conversation.stop() } }' \
  'VoiceFocus.register("home")'
insert_after "$HOME_FILE" "            lifecycleOwner?.lifecycle?.removeObserver(observer)" \
'            VoiceFocus.unregister("home")' \
  'VoiceFocus.unregister("home")'
insert_after "$HOME_FILE" "    fun startConversation() {" \
'        VoiceFocus.claim("home")' \
  'VoiceFocus.claim("home")'

# ---------- Access screen: the bubble card ----------
insert_after "$PERMS_FILE" "import com.nova.ai.ui.components.ActionLabCard" \
"import com.nova.ai.ui.components.BubbleCard" "import com.nova.ai.ui.components.BubbleCard"
insert_after "$PERMS_FILE" "        ActionLabCard()" "        BubbleCard()" "        BubbleCard()"

# ---------- Commit and push ----------
git add -A
if git diff --cached --quiet; then
  echo "Nothing new to commit."
else
  git commit -m "P22: floating bubble, emergency stop, quick settings tiles"
  git push
fi

echo "P22 files created and pushed."
