package com.nova.ai

import android.app.Application
import android.util.Log
import com.nova.ai.logging.GlobalCrashHandler
import com.nova.ai.logging.NovaLogger

/**
 * Application entry point. Global, app-wide initialization lives here:
 * the local logger and the crash handler start before anything else.
 */
class NovaApp : Application() {

    override fun onCreate() {
        super.onCreate()
        try {
            NovaLogger.init(this)
            GlobalCrashHandler.install()
            NovaLogger.i(TAG, "NOVA AI started")
        } catch (e: Exception) {
            // Initialization must never crash the app at startup.
            Log.e(TAG, "Application init failed", e)
        }
    }

    companion object {
        private const val TAG: String = "NovaApp"
    }
}
