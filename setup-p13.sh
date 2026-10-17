#!/usr/bin/env bash
# NOVA AI - Phase 13 setup script: system actions (torch, volume, brightness, Wi-Fi/Bluetooth screens).
# Additive: new system package; HomeScreen gets a few new lines only.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
MANIFEST="app/src/main/AndroidManifest.xml"
HOME_FILE="$BASE/ui/screens/HomeScreen.kt"

for required in \
  "$BASE/apps/AppCommandController.kt" \
  "$BASE/nlp/IntentParser.kt" \
  "$HOME_FILE" \
  "$MANIFEST"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after P1 to P12 are installed." >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
mkdir -p "$BASE/system"

# ---------- A. Manifest: permission needed to change screen brightness ----------
if ! grep -q "android.permission.WRITE_SETTINGS" "$MANIFEST"; then
  sed -i '/android.permission.RECORD_AUDIO/a\    <uses-permission android:name="android.permission.WRITE_SETTINGS" />' "$MANIFEST"
fi
grep -q "android.permission.WRITE_SETTINGS" "$MANIFEST" || { echo "ERROR: manifest edit failed" >&2; exit 1; }

# ---------- B. New strings file ----------
cat > app/src/main/res/values/strings_p13.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="sys_title">সিস্টেম কাজ</string>
    <string name="sys_unknown">এই কাজটি এখনো বুঝিনি। আরও পরিষ্কার করে বলো।</string>
    <string name="sys_unknown_error">অজানা সমস্যা</string>
    <string name="sys_failed">সিস্টেম কাজে সমস্যা: %1$s</string>

    <string name="sys_flash_on">টর্চ চালু করেছি।</string>
    <string name="sys_flash_off">টর্চ বন্ধ করেছি।</string>
    <string name="sys_flash_none">এই ফোনে ফ্ল্যাশলাইট নেই।</string>

    <string name="sys_volume_set">ভলিউম %1$d%% করেছি।</string>
    <string name="sys_volume_muted">ভলিউম বন্ধ করেছি (মিউট)। আবার চালাতে বলো: ভলিউম চালু করো।</string>
    <string name="sys_volume_hint">ভলিউম বাড়াতে, কমাতে বা শতাংশ বলো। যেমন: ভলিউম ৫০ করো।</string>

    <string name="sys_brightness_set">ব্রাইটনেস %1$d%% করেছি।</string>
    <string name="sys_brightness_hint">ব্রাইটনেস বাড়াতে, কমাতে বা শতাংশ বলো। যেমন: ব্রাইটনেস ৫০ করো।</string>
    <string name="sys_brightness_permission">ব্রাইটনেস বদলাতে একটি বিশেষ অনুমতি লাগে। নিচের বাটন চেপে নোভাকে অনুমতি দাও, তারপর আবার বলো।</string>
    <string name="sys_brightness_permission_button">অনুমতির স্ক্রিন খোলো</string>
    <string name="sys_brightness_permission_opened">অনুমতির স্ক্রিন খুলেছি। নোভার পাশের সুইচটি চালু করে ফিরে এসো।</string>

    <string name="sys_wifi_guided">ওয়াইফাইয়ের প্যানেল খুলেছি। Android নিয়ম অনুযায়ী অ্যাপ নিজে ওয়াইফাই চালু বা বন্ধ করতে পারে না, তাই সুইচটি তুমি চাপো।</string>
    <string name="sys_wifi_settings">ওয়াইফাই সেটিংস খুলেছি।</string>
    <string name="sys_bt_guided">ব্লুটুথ সেটিংস খুলেছি। Android নিয়ম অনুযায়ী অ্যাপ নিজে ব্লুটুথ চালু বা বন্ধ করতে পারে না, তাই সুইচটি তুমি চাপো।</string>
    <string name="sys_bt_settings">ব্লুটুথ সেটিংস খুলেছি।</string>
</resources>
EOF

# ---------- 1. SystemActionOutcome.kt ----------
cat > "$BASE/system/SystemActionOutcome.kt" <<'EOF'
package com.nova.ai.system

/** How a system action ended. */
enum class OutcomeKind {
    /** The app did the job itself. */
    DONE,

    /** The app opened the right screen; the user must finish with one tap. */
    GUIDED,

    /** A special permission is missing; the user can open its screen. */
    NEEDS_PERMISSION,

    /** The command was understood but needs more detail. */
    HINT,

    /** Something went wrong. */
    FAILED
}

/** Result of a system action, with a Bangla message to show the user. */
data class SystemActionOutcome(val kind: OutcomeKind, val message: String)
EOF

# ---------- 2. TorchController.kt ----------
cat > "$BASE/system/TorchController.kt" <<'EOF'
package com.nova.ai.system

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Handler
import android.os.Looper
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * Turns the camera flash on and off as a torch. No camera permission is needed.
 * Tracks whether the torch is on, even when another app changes it.
 */
class TorchController(context: Context) {

    private val appContext: Context = context.applicationContext
    private val cameraManager: CameraManager? =
        appContext.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
    private val handler: Handler = Handler(Looper.getMainLooper())

    private val torchCameraId: String? = findTorchCameraId()

    @Volatile
    private var torchOn: Boolean = false

    private var torchCallback: CameraManager.TorchCallback? = null

    init {
        registerCallback()
    }

    /** True if this phone has a flash that can work as a torch. */
    fun hasTorch(): Boolean = torchCameraId != null

    /** True while the torch is on. */
    fun isOn(): Boolean = torchOn

    /** Switches the torch on or off. */
    fun set(enabled: Boolean): NovaResult<Unit> {
        val manager: CameraManager = cameraManager
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_NO_TORCH)
        val cameraId: String = torchCameraId
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, MSG_NO_TORCH)

        return try {
            manager.setTorchMode(cameraId, enabled)
            torchOn = enabled
            NovaResult.Success(Unit)
        } catch (e: CameraAccessException) {
            NovaLogger.w(TAG, "Torch is busy or unavailable", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_BUSY, e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Torch change failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, MSG_BUSY, e)
        }
    }

    /** Stops listening to torch changes. Call when the screen is gone. */
    fun release() {
        val callback: CameraManager.TorchCallback = torchCallback ?: return
        try {
            cameraManager?.unregisterTorchCallback(callback)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to unregister torch callback", e)
        } finally {
            torchCallback = null
        }
    }

    private fun findTorchCameraId(): String? {
        val manager: CameraManager = cameraManager ?: return null
        if (!appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_FLASH)) {
            return null
        }
        return try {
            manager.cameraIdList.firstOrNull { id ->
                val characteristics: CameraCharacteristics = manager.getCameraCharacteristics(id)
                val hasFlash: Boolean =
                    characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                val isBack: Boolean =
                    characteristics.get(CameraCharacteristics.LENS_FACING) ==
                        CameraCharacteristics.LENS_FACING_BACK
                hasFlash && isBack
            }
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to find torch camera", e)
            null
        }
    }

    private fun registerCallback() {
        val manager: CameraManager = cameraManager ?: return
        val callback = object : CameraManager.TorchCallback() {
            override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
                if (cameraId == torchCameraId) torchOn = enabled
            }
        }
        try {
            manager.registerTorchCallback(callback, handler)
            torchCallback = callback
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to register torch callback", e)
        }
    }

    private companion object {
        const val TAG: String = "TorchController"
        const val MSG_NO_TORCH: String = "এই ফোনে ফ্ল্যাশলাইট নেই।"
        const val MSG_BUSY: String = "ক্যামেরা এখন অন্য অ্যাপ ব্যবহার করছে, তাই টর্চ চালানো গেল না।"
    }
}
EOF

# ---------- 3. VolumeController.kt ----------
cat > "$BASE/system/VolumeController.kt" <<'EOF'
package com.nova.ai.system

import android.content.Context
import android.media.AudioManager
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import kotlin.math.roundToInt

/**
 * Changes the media volume (songs, videos and NOVA's own voice).
 * Every change shows the system volume bar and returns the new volume in percent.
 */
class VolumeController(context: Context) {

    private val audioManager: AudioManager? =
        context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    private var volumeBeforeMute: Int = 0

    /** Sets the volume to [percent] (0 to 100). */
    fun setPercent(percent: Int): NovaResult<Int> = change { max, _ ->
        (max * percent.coerceIn(MIN_PERCENT, MAX_PERCENT) / PERCENT_BASE).roundToInt()
    }

    /** Raises or lowers the volume by one step. */
    fun step(up: Boolean): NovaResult<Int> = change { max, current ->
        val size: Int = maxOf(1, (max * STEP_FRACTION).roundToInt())
        if (up) current + size else current - size
    }

    /** Mutes, remembering the old volume so it can be restored. */
    fun mute(): NovaResult<Int> = change { _, current ->
        if (current > 0) volumeBeforeMute = current
        0
    }

    /** Restores the volume from before muting (or half volume). */
    fun unmute(): NovaResult<Int> = change { max, current ->
        when {
            current > 0 -> current
            volumeBeforeMute > 0 -> volumeBeforeMute
            else -> maxOf(1, max / 2)
        }
    }

    private fun change(compute: (max: Int, current: Int) -> Int): NovaResult<Int> {
        val manager: AudioManager = audioManager
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, "ফোনের অডিও সিস্টেম পাওয়া যায়নি।")
        return try {
            val max: Int = manager.getStreamMaxVolume(STREAM)
            val current: Int = manager.getStreamVolume(STREAM)
            if (max <= 0) {
                return NovaResult.failure(ErrorCode.NOT_AVAILABLE, "ভলিউম বদলানো যাচ্ছে না।")
            }
            val target: Int = compute(max, current).coerceIn(0, max)
            manager.setStreamVolume(STREAM, target, AudioManager.FLAG_SHOW_UI)
            NovaResult.Success((target * PERCENT_BASE / max).roundToInt())
        } catch (e: SecurityException) {
            NovaLogger.w(TAG, "Volume change not allowed", e)
            NovaResult.failure(ErrorCode.PERMISSION_DENIED, "ফোন এখন ভলিউম বদলাতে দিচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Volume change failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "ভলিউম বদলাতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "VolumeController"
        const val STREAM: Int = AudioManager.STREAM_MUSIC
        const val MIN_PERCENT: Int = 0
        const val MAX_PERCENT: Int = 100
        const val PERCENT_BASE: Float = 100f
        const val STEP_FRACTION: Float = 0.15f
    }
}
EOF

# ---------- 4. BrightnessController.kt ----------
cat > "$BASE/system/BrightnessController.kt" <<'EOF'
package com.nova.ai.system

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import kotlin.math.roundToInt

/**
 * Changes the screen brightness. Android asks the user to allow this once
 * ("Modify system settings"); [canWrite] tells whether that was done.
 */
class BrightnessController(context: Context) {

    private val appContext: Context = context.applicationContext

    /** True if the user allowed NOVA to change system settings. */
    fun canWrite(): Boolean = Settings.System.canWrite(appContext)

    /** Sets the brightness to [percent] (kept between 3 and 100). */
    fun setPercent(percent: Int): NovaResult<Int> =
        apply(percent.coerceIn(MIN_PERCENT, MAX_PERCENT))

    /** Raises or lowers the brightness by one step. */
    fun step(up: Boolean): NovaResult<Int> {
        val delta: Int = if (up) STEP_PERCENT else -STEP_PERCENT
        return apply((currentPercent() + delta).coerceIn(MIN_PERCENT, MAX_PERCENT))
    }

    /** Opens the screen where the user can allow NOVA to change brightness. */
    fun openPermissionScreen(): NovaResult<Unit> {
        return try {
            val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                .setData(Uri.parse("package:${appContext.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appContext.startActivity(intent)
            NovaResult.Success(Unit)
        } catch (e: ActivityNotFoundException) {
            NovaLogger.e(TAG, "Permission screen not found", e)
            NovaResult.failure(ErrorCode.NOT_AVAILABLE, "অনুমতির স্ক্রিন খোলা যাচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to open permission screen", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "অনুমতির স্ক্রিন খুলতে সমস্যা হয়েছে।", e)
        }
    }

    private fun currentPercent(): Int {
        val raw: Int = Settings.System.getInt(
            appContext.contentResolver,
            Settings.System.SCREEN_BRIGHTNESS,
            DEFAULT_RAW
        )
        return (raw * PERCENT_BASE / MAX_RAW).roundToInt()
    }

    private fun apply(percent: Int): NovaResult<Int> {
        if (!canWrite()) {
            return NovaResult.failure(ErrorCode.PERMISSION_DENIED, "ব্রাইটনেস বদলানোর অনুমতি নেই।")
        }
        return try {
            val raw: Int = (percent * MAX_RAW / PERCENT_BASE).roundToInt().coerceIn(1, MAX_RAW.toInt())
            val resolver = appContext.contentResolver
            Settings.System.putInt(
                resolver,
                Settings.System.SCREEN_BRIGHTNESS_MODE,
                Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL
            )
            val saved: Boolean = Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS, raw)
            if (saved) {
                NovaResult.Success(percent)
            } else {
                NovaResult.failure(ErrorCode.EXECUTION_FAILED, "ব্রাইটনেস বদলানো যায়নি।")
            }
        } catch (e: SecurityException) {
            NovaLogger.w(TAG, "Brightness change not allowed", e)
            NovaResult.failure(ErrorCode.PERMISSION_DENIED, "ব্রাইটনেস বদলানোর অনুমতি নেই।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Brightness change failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "ব্রাইটনেস বদলাতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "BrightnessController"
        const val MIN_PERCENT: Int = 3
        const val MAX_PERCENT: Int = 100
        const val STEP_PERCENT: Int = 15
        const val PERCENT_BASE: Float = 100f
        const val MAX_RAW: Float = 255f
        const val DEFAULT_RAW: Int = 128
    }
}
EOF

# ---------- 5. SystemSettingsOpener.kt ----------
cat > "$BASE/system/SystemSettingsOpener.kt" <<'EOF'
package com.nova.ai.system

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * Opens the phone's Wi-Fi and Bluetooth screens. Android does not let ordinary
 * apps switch these on or off, so the user taps the final switch.
 */
class SystemSettingsOpener(context: Context) {

    private val appContext: Context = context.applicationContext

    /** Opens the quick Wi-Fi panel (Android 10 and newer) or the Wi-Fi settings page. */
    fun openWifi(): NovaResult<Unit> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val panel: NovaResult<Unit> = start(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
            if (panel is NovaResult.Success) return panel
        }
        return start(Settings.ACTION_WIFI_SETTINGS)
    }

    /** Opens the Bluetooth settings page. */
    fun openBluetooth(): NovaResult<Unit> = start(Settings.ACTION_BLUETOOTH_SETTINGS)

    private fun start(action: String): NovaResult<Unit> {
        return try {
            appContext.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            NovaResult.Success(Unit)
        } catch (e: ActivityNotFoundException) {
            NovaLogger.e(TAG, "Settings screen not found", e)
            NovaResult.failure(ErrorCode.NOT_AVAILABLE, "সেটিংস স্ক্রিন খোলা যাচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to open settings screen", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "সেটিংস খুলতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "SystemSettingsOpener"
    }
}
EOF

# ---------- 6. SystemActionExecutor.kt ----------
cat > "$BASE/system/SystemActionExecutor.kt" <<'EOF'
package com.nova.ai.system

import android.content.Context
import androidx.annotation.StringRes
import com.nova.ai.R
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import com.nova.ai.nlp.IntentAction
import com.nova.ai.nlp.IntentEntity
import com.nova.ai.nlp.SystemTarget

/**
 * Carries out understood system commands: torch, volume, brightness, and the
 * Wi-Fi and Bluetooth screens. It never crashes; problems become a
 * [SystemActionOutcome] with a Bangla message.
 */
class SystemActionExecutor(context: Context) {

    private val appContext: Context = context.applicationContext
    private val torch = TorchController(appContext)
    private val volumeControl = VolumeController(appContext)
    private val brightnessControl = BrightnessController(appContext)
    private val settingsOpener = SystemSettingsOpener(appContext)

    /** Runs a SYSTEM_ACTION [intent]. */
    fun execute(intent: NovaIntent): SystemActionOutcome {
        if (intent.type != IntentType.SYSTEM_ACTION) return failed(text(R.string.sys_unknown))

        val target: String? = intent.entities[IntentEntity.TARGET]
        val action: String? = intent.entities[IntentEntity.ACTION]
        val value: Int? = intent.entities[IntentEntity.VALUE]?.toIntOrNull()

        return try {
            when (target) {
                SystemTarget.FLASHLIGHT -> flashlight(action)
                SystemTarget.VOLUME -> volume(action, value)
                SystemTarget.BRIGHTNESS -> brightness(action, value)
                SystemTarget.WIFI -> wifi(action)
                SystemTarget.BLUETOOTH -> bluetooth(action)
                else -> hint(text(R.string.sys_unknown))
            }
        } catch (e: Exception) {
            NovaLogger.e(TAG, "System action failed", e)
            failed(text(R.string.sys_failed, text(R.string.sys_unknown_error)))
        }
    }

    /** Opens the screen where the user allows brightness changes. */
    fun openBrightnessPermission(): SystemActionOutcome =
        when (val result: NovaResult<Unit> = brightnessControl.openPermissionScreen()) {
            is NovaResult.Success ->
                SystemActionOutcome(OutcomeKind.GUIDED, text(R.string.sys_brightness_permission_opened))
            is NovaResult.Failure -> failed(result.error.message)
        }

    /** Releases listeners. Call when the screen is gone. */
    fun release() {
        torch.release()
    }

    private fun flashlight(action: String?): SystemActionOutcome {
        if (!torch.hasTorch()) return failed(text(R.string.sys_flash_none))

        val enable: Boolean = when (action) {
            IntentAction.ON -> true
            IntentAction.OFF -> false
            else -> !torch.isOn()
        }
        return when (val result: NovaResult<Unit> = torch.set(enable)) {
            is NovaResult.Success ->
                done(text(if (enable) R.string.sys_flash_on else R.string.sys_flash_off))
            is NovaResult.Failure -> failed(result.error.message)
        }
    }

    private fun volume(action: String?, value: Int?): SystemActionOutcome {
        val result: NovaResult<Int> = when (action) {
            IntentAction.UP -> volumeControl.step(true)
            IntentAction.DOWN -> volumeControl.step(false)
            IntentAction.SET ->
                if (value != null) volumeControl.setPercent(value) else return hint(text(R.string.sys_volume_hint))
            IntentAction.MUTE, IntentAction.OFF -> volumeControl.mute()
            IntentAction.ON -> volumeControl.unmute()
            else -> return hint(text(R.string.sys_volume_hint))
        }
        return when (result) {
            is NovaResult.Success ->
                if (result.value == 0) {
                    done(text(R.string.sys_volume_muted))
                } else {
                    done(text(R.string.sys_volume_set, result.value))
                }
            is NovaResult.Failure -> failed(result.error.message)
        }
    }

    private fun brightness(action: String?, value: Int?): SystemActionOutcome {
        val adjustable: Boolean = action == IntentAction.UP ||
            action == IntentAction.DOWN ||
            (action == IntentAction.SET && value != null)
        if (!adjustable) return hint(text(R.string.sys_brightness_hint))

        if (!brightnessControl.canWrite()) {
            return SystemActionOutcome(
                OutcomeKind.NEEDS_PERMISSION,
                text(R.string.sys_brightness_permission)
            )
        }

        val result: NovaResult<Int> = when (action) {
            IntentAction.UP -> brightnessControl.step(true)
            IntentAction.DOWN -> brightnessControl.step(false)
            else -> brightnessControl.setPercent(value ?: return hint(text(R.string.sys_brightness_hint)))
        }
        return when (result) {
            is NovaResult.Success -> done(text(R.string.sys_brightness_set, result.value))
            is NovaResult.Failure -> failed(result.error.message)
        }
    }

    private fun wifi(action: String?): SystemActionOutcome =
        when (val result: NovaResult<Unit> = settingsOpener.openWifi()) {
            is NovaResult.Success ->
                if (action == IntentAction.ON || action == IntentAction.OFF) {
                    SystemActionOutcome(OutcomeKind.GUIDED, text(R.string.sys_wifi_guided))
                } else {
                    done(text(R.string.sys_wifi_settings))
                }
            is NovaResult.Failure -> failed(result.error.message)
        }

    private fun bluetooth(action: String?): SystemActionOutcome =
        when (val result: NovaResult<Unit> = settingsOpener.openBluetooth()) {
            is NovaResult.Success ->
                if (action == IntentAction.ON || action == IntentAction.OFF) {
                    SystemActionOutcome(OutcomeKind.GUIDED, text(R.string.sys_bt_guided))
                } else {
                    done(text(R.string.sys_bt_settings))
                }
            is NovaResult.Failure -> failed(result.error.message)
        }

    private fun text(@StringRes id: Int, vararg args: Any): String = appContext.getString(id, *args)

    private fun done(message: String) = SystemActionOutcome(OutcomeKind.DONE, message)
    private fun hint(message: String) = SystemActionOutcome(OutcomeKind.HINT, message)
    private fun failed(message: String) = SystemActionOutcome(OutcomeKind.FAILED, message)

    private companion object {
        const val TAG: String = "SystemActionExecutor"
    }
}
EOF

# ---------- 7. SystemCommandController.kt ----------
cat > "$BASE/system/SystemCommandController.kt" <<'EOF'
package com.nova.ai.system

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.voice.LanguageDetector

/**
 * Screen-side holder for system commands. Home gives it every command;
 * it acts only on commands that ask for a system action and keeps the
 * last [state] for the screen to show. Use from the main thread.
 */
class SystemCommandController(context: Context) {

    private val executor = SystemActionExecutor(context)
    private val brain = RuleBasedBrain()

    /** The last system action result, or null when there is nothing to show. */
    var state: SystemActionOutcome? by mutableStateOf<SystemActionOutcome?>(null)
        private set

    /** Looks at [text]; if it asks for a system action, carries it out. */
    fun handleCommand(text: String) {
        val intent: NovaIntent? = analyze(text)
        if (intent == null || intent.type != IntentType.SYSTEM_ACTION) {
            state = null
            return
        }
        state = executor.execute(intent)
    }

    /** Opens the screen where the user allows brightness changes. */
    fun openBrightnessPermission() {
        state = executor.openBrightnessPermission()
    }

    /** Hides the result card. */
    fun dismiss() {
        state = null
    }

    /** Releases listeners. Call when the screen is gone. */
    fun release() {
        executor.release()
    }

    private fun analyze(text: String): NovaIntent? {
        if (text.isBlank()) return null
        val command = VoiceCommand(
            rawText = text,
            language = LanguageDetector.detect(text),
            timestampMs = System.currentTimeMillis()
        )
        return (brain.analyze(command, emptyList()) as? NovaResult.Success)?.value
    }
}
EOF

# ---------- 8. SystemActionCard.kt ----------
cat > "$BASE/ui/components/SystemActionCard.kt" <<'EOF'
package com.nova.ai.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.system.OutcomeKind
import com.nova.ai.system.SystemActionOutcome
import com.nova.ai.system.SystemCommandController

/**
 * Shows the result of a system command (torch, volume, brightness, Wi-Fi,
 * Bluetooth) on the Home screen. Shows nothing while there is nothing to report.
 */
@Composable
fun SystemActionCard(
    controller: SystemCommandController,
    modifier: Modifier = Modifier
) {
    val outcome: SystemActionOutcome = controller.state ?: return

    val marker: String = when (outcome.kind) {
        OutcomeKind.DONE -> "✅"
        OutcomeKind.GUIDED -> "👉"
        OutcomeKind.NEEDS_PERMISSION -> "🔐"
        OutcomeKind.HINT -> "💡"
        OutcomeKind.FAILED -> "⚠️"
    }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.sys_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(text = "$marker ${outcome.message}")

            if (outcome.kind == OutcomeKind.NEEDS_PERMISSION) {
                Button(
                    onClick = { controller.openBrightnessPermission() },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.sys_brightness_permission_button))
                }
            }

            TextButton(onClick = { controller.dismiss() }) {
                Text(stringResource(R.string.action_dismiss))
            }
        }
    }
}
EOF

# ---------- C. HomeScreen.kt: a few additive lines (idempotent) ----------
if ! grep -q "SystemCommandController" "$HOME_FILE"; then
  grep -q 'val appController: AppCommandController = remember' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (controller) not found" >&2; exit 1; }
  grep -q 'appController.handleCommand(command.rawText)' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (voice command) not found" >&2; exit 1; }
  grep -q 'appController.handleCommand(commandText)' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (send button) not found" >&2; exit 1; }
  grep -q '^            voiceEngine.shutdown()$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (dispose) not found" >&2; exit 1; }
  grep -q '^        AppActionCard(controller = appController)$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (card) not found" >&2; exit 1; }
  grep -q '^import com.nova.ai.apps.AppCommandController$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (import) not found" >&2; exit 1; }

  cat > "$TMP_DIR/home_imports.txt" <<'EOF'
import com.nova.ai.system.SystemCommandController
import com.nova.ai.ui.components.SystemActionCard
EOF
  cat > "$TMP_DIR/home_controller.txt" <<'EOF'

    // Runs system commands: torch, volume, brightness, Wi-Fi and Bluetooth screens.
    val systemController: SystemCommandController = remember { SystemCommandController(context) }
EOF
  cat > "$TMP_DIR/home_voice.txt" <<'EOF'
                    systemController.handleCommand(command.rawText)
EOF
  cat > "$TMP_DIR/home_send.txt" <<'EOF'
                    systemController.handleCommand(commandText)
EOF
  cat > "$TMP_DIR/home_dispose.txt" <<'EOF'
            systemController.release()
EOF
  cat > "$TMP_DIR/home_card.txt" <<'EOF'

        SystemActionCard(controller = systemController)
EOF

  sed -i "/^import com.nova.ai.apps.AppCommandController$/r $TMP_DIR/home_imports.txt" "$HOME_FILE"
  sed -i "/val appController: AppCommandController = remember/r $TMP_DIR/home_controller.txt" "$HOME_FILE"
  sed -i "/appController.handleCommand(command.rawText)/r $TMP_DIR/home_voice.txt" "$HOME_FILE"
  sed -i "/appController.handleCommand(commandText)/r $TMP_DIR/home_send.txt" "$HOME_FILE"
  sed -i "/^            voiceEngine.shutdown()$/r $TMP_DIR/home_dispose.txt" "$HOME_FILE"
  sed -i "/^        AppActionCard(controller = appController)$/r $TMP_DIR/home_card.txt" "$HOME_FILE"
fi
grep -q "val systemController: SystemCommandController" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (controller)" >&2; exit 1; }
grep -q "systemController.handleCommand(command.rawText)" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (voice)" >&2; exit 1; }
grep -q "systemController.handleCommand(commandText)" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (send)" >&2; exit 1; }
grep -q "systemController.release()" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (dispose)" >&2; exit 1; }
grep -q "SystemActionCard(controller = systemController)" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (card)" >&2; exit 1; }

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "P13: system actions (torch, volume, brightness, Wi-Fi and Bluetooth screens)"
git push

echo "P13 files created and pushed."
