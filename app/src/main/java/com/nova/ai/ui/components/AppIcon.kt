package com.nova.ai.ui.components

import android.content.Context
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.graphics.drawable.toBitmap
import com.nova.ai.logging.NovaLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Keeps recently loaded app icons in memory so lists scroll smoothly. */
object AppIconCache {
    private const val TAG: String = "AppIconCache"
    private const val ICON_SIZE_PX: Int = 96
    private const val MAX_ENTRIES: Int = 150

    private val cache: LruCache<String, ImageBitmap> = LruCache<String, ImageBitmap>(MAX_ENTRIES)

    fun get(packageName: String): ImageBitmap? = cache.get(packageName)

    /** Loads an icon. Blocking: call from a background thread. Returns null if unavailable. */
    fun load(context: Context, packageName: String): ImageBitmap? {
        return try {
            val drawable = context.packageManager.getApplicationIcon(packageName)
            val image: ImageBitmap = drawable.toBitmap(ICON_SIZE_PX, ICON_SIZE_PX).asImageBitmap()
            cache.put(packageName, image)
            image
        } catch (e: Exception) {
            NovaLogger.d(TAG, "Icon not available")
            null
        }
    }
}

/** Shows the icon of an installed app (a phone symbol while loading or if missing). */
@Composable
fun AppIcon(
    packageName: String,
    modifier: Modifier = Modifier,
    size: Dp = 40.dp
) {
    val context: Context = LocalContext.current
    val icon: ImageBitmap? by produceState<ImageBitmap?>(
        initialValue = AppIconCache.get(packageName),
        key1 = packageName
    ) {
        if (value == null) {
            value = withContext(Dispatchers.Default) { AppIconCache.load(context, packageName) }
        }
    }

    val loaded: ImageBitmap? = icon
    if (loaded != null) {
        Image(bitmap = loaded, contentDescription = null, modifier = modifier.size(size))
    } else {
        Box(modifier = modifier.size(size), contentAlignment = Alignment.Center) {
            Text(text = "📱")
        }
    }
}
