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
 * Performs touch gestures (taps, swipes, long presses, two-finger gestures) through the
 * accessibility service and waits until the phone says the gesture finished. Results come
 * on a helper thread, so waiting never blocks the screen thread. Every gesture first
 * checks the emergency stop.
 */
internal object GestureRunner {

    private const val TAG: String = "GestureRunner"
    private const val WAIT_MARGIN_MS: Long = 1500L

    private const val MSG_REFUSED: String = "ফোন এই ইশারা নিতে রাজি হয়নি।"
    private const val MSG_NOT_DONE: String = "ইশারা সম্পন্ন হয়নি। স্ক্রিন এটা আটকে থাকতে পারে।"
    private const val MSG_FAILED: String = "ইশারা দিতে সমস্যা হয়েছে।"
    private const val MSG_TOO_COMPLEX: String = "এই ইশারা ফোনের সীমার চেয়ে বড়।"

    private val workerThread: HandlerThread = HandlerThread("nova-gesture").apply { start() }
    private val workerHandler: Handler = Handler(workerThread.looper)

    /** Taps the screen at ([x], [y]) in pixels. */
    fun tap(service: AccessibilityService, x: Float, y: Float): NovaResult<Unit> {
        val point = GesturePoint(x, y)
        val stroke = GestureStroke(point, point, 0L, GestureGeometry.TAP_DURATION_MS)
        return execute(service, GesturePlan(listOf(stroke)))
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
        val stroke = GestureStroke(GesturePoint(startX, startY), GesturePoint(endX, endY), 0L, durationMs)
        return execute(service, GesturePlan(listOf(stroke)))
    }

    /** Performs every finger of [plan] at the same time (with their own delays) and waits for the end. */
    fun execute(service: AccessibilityService, plan: GesturePlan): NovaResult<Unit> {
        ActionGate.check()?.let { return it }

        if (plan.strokes.isEmpty() ||
            plan.strokes.size > GestureDescription.getMaxStrokeCount() ||
            plan.totalDurationMs > GestureDescription.getMaxGestureDuration()
        ) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, MSG_TOO_COMPLEX)
        }

        return try {
            val builder = GestureDescription.Builder()
            for (stroke in plan.strokes) {
                builder.addStroke(
                    GestureDescription.StrokeDescription(
                        pathOf(stroke),
                        stroke.startDelayMs,
                        stroke.durationMs
                    )
                )
            }
            val gesture: GestureDescription = builder.build()
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
            finished.await(plan.totalDurationMs + WAIT_MARGIN_MS, TimeUnit.MILLISECONDS)
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

    // A tap or a long press stays on one spot, so its path is only a starting point.
    private fun pathOf(stroke: GestureStroke): Path = Path().apply {
        moveTo(stroke.start.x, stroke.start.y)
        if (stroke.end != stroke.start) lineTo(stroke.end.x, stroke.end.y)
    }
}
