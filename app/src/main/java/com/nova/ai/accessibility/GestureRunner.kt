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
