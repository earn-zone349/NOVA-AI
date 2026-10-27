package com.nova.ai.bubble

import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.nova.ai.R
import com.nova.ai.logging.NovaLogger
import com.nova.ai.security.EmergencyStop

/**
 * Quick Settings tile for the emergency stop. It works from the notification shade over any app,
 * even if the bubble is closed. Tap once to stop NOVA, tap again to let it work.
 */
class NovaStopTileService : TileService() {

    private val handler = Handler(Looper.getMainLooper())
    private val listener: (Boolean) -> Unit = { _ -> handler.post { refreshTile() } }

    override fun onStartListening() {
        super.onStartListening()
        EmergencyStop.addListener(listener)
        refreshTile()
    }

    override fun onStopListening() {
        EmergencyStop.removeListener(listener)
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        if (EmergencyStop.isActive) {
            EmergencyStop.release(SOURCE)
        } else {
            EmergencyStop.trigger(SOURCE)
        }
        refreshTile()
    }

    private fun refreshTile() {
        val tile: Tile = qsTile ?: return
        try {
            val stopped: Boolean = EmergencyStop.isActive
            tile.state = if (stopped) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            tile.label = getString(R.string.bub_tile_stop_label)
            tile.contentDescription = getString(
                if (stopped) R.string.bub_tile_stop_on else R.string.bub_tile_stop_off
            )
            tile.updateTile()
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not update the stop tile", e)
        }
    }

    private companion object {
        const val TAG: String = "NovaStopTile"
        const val SOURCE: String = "quick tile"
    }
}
