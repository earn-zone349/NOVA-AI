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
