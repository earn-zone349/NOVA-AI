package com.nova.ai.logging

import android.os.Process
import android.util.Log
import kotlin.system.exitProcess

/**
 * Saves every uncaught crash to the local log before the app closes,
 * then hands over to the previous system handler so Android behaves normally.
 */
class GlobalCrashHandler private constructor(
    private val previous: Thread.UncaughtExceptionHandler?
) : Thread.UncaughtExceptionHandler {

    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        try {
            NovaLogger.logBlocking(
                level = LogLevel.FATAL,
                tag = TAG,
                message = "Uncaught exception on thread ${thread.name}",
                throwable = throwable
            )
        } catch (e: Throwable) {
            Log.e(TAG, "Crash logging failed", e)
        } finally {
            if (previous != null) {
                previous.uncaughtException(thread, throwable)
            } else {
                Process.killProcess(Process.myPid())
                exitProcess(CRASH_EXIT_CODE)
            }
        }
    }

    companion object {
        private const val TAG: String = "CrashHandler"
        private const val CRASH_EXIT_CODE: Int = 10

        @Volatile
        private var installed: Boolean = false

        /** Installs the handler once. Safe to call more than once. */
        fun install() {
            synchronized(this) {
                if (installed) return
                Thread.setDefaultUncaughtExceptionHandler(
                    GlobalCrashHandler(Thread.getDefaultUncaughtExceptionHandler())
                )
                installed = true
            }
        }
    }
}
