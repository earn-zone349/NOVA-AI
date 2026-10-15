package com.nova.ai

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.nova.ai.ui.navigation.NovaMainScaffold

/**
 * Single-activity host. Shows the navigation graph (Home, Brain, Tasks,
 * Access, Memory, Privacy). The theme is upgraded in Phase 4.
 */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            setContent { NovaRoot() }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set content", e)
        }
    }

    companion object {
        private const val TAG: String = "MainActivity"
    }
}

/** Root composable: theme, surface and the main scaffold. */
@Composable
private fun NovaRoot() {
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            NovaMainScaffold()
        }
    }
}
