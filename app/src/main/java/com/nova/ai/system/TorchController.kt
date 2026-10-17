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
