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
                SystemTarget.MOBILE_DATA -> mobileData(action)
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

    private fun mobileData(action: String?): SystemActionOutcome =
        when (val result: NovaResult<Unit> = settingsOpener.openMobileData()) {
            is NovaResult.Success ->
                if (action == IntentAction.ON || action == IntentAction.OFF) {
                    SystemActionOutcome(OutcomeKind.GUIDED, text(R.string.sys_data_guided))
                } else {
                    done(text(R.string.sys_data_settings))
                }
            is NovaResult.Failure -> failed(result.error.message)
        }
    private fun hint(message: String) = SystemActionOutcome(OutcomeKind.HINT, message)
    private fun failed(message: String) = SystemActionOutcome(OutcomeKind.FAILED, message)

    private companion object {
        const val TAG: String = "SystemActionExecutor"
    }
}
