package com.nova.ai

import android.app.Application
import android.util.Log

/**
 * Application entry point. Global, app-wide initialization lives here.
 * Later phases add the logger, database and crash handler.
 */
class NovaApp : Application() {

    override fun onCreate() {
        super.onCreate()
        try {
            Log.i(TAG, "NOVA AI started")
        } catch (e: Exception) {
            // Initialization must never crash the app at startup.
            Log.e(TAG, "Application init failed", e)
        }
    }

    companion object {
        private const val TAG: String = "NovaApp"
    }
}
