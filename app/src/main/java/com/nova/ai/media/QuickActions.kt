package com.nova.ai.media

import android.app.SearchManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * Opens searches, maps, navigation, music search and the camera by sending
 * Android a ready-made request. Each action tries the best app first, then
 * simpler options. Search words are never logged.
 */
class QuickActions(context: Context) {

    private val appContext: Context = context.applicationContext

    /** Searches Google. With [preferChrome] the search opens in Chrome first. */
    fun webSearch(query: String, preferChrome: Boolean): NovaResult<Unit> {
        val webUri: Uri = Uri.parse(GOOGLE_SEARCH_URL).buildUpon()
            .appendQueryParameter("q", query)
            .build()
        val intents = ArrayList<Intent>()
        if (preferChrome) intents.add(viewIntent(webUri, CHROME_PACKAGE))
        intents.add(Intent(Intent.ACTION_WEB_SEARCH).putExtra(SearchManager.QUERY, query))
        intents.add(viewIntent(webUri))
        return launchFirst(intents)
    }

    /** Searches YouTube (in the YouTube app if it is installed). */
    fun youtubeSearch(query: String): NovaResult<Unit> {
        val uri: Uri = youtubeUri(query)
        return launchFirst(listOf(viewIntent(uri, YOUTUBE_PACKAGE), viewIntent(uri)))
    }

    /** Searches a place in the maps app. */
    fun mapsSearch(query: String): NovaResult<Unit> = launchFirst(
        listOf(
            viewIntent(geoUri(query), MAPS_PACKAGE),
            viewIntent(geoUri(query)),
            viewIntent(mapsWebUri(query))
        )
    )

    /** Starts guidance to [destination] in Google Maps (or shows it on a map). */
    fun navigate(destination: String): NovaResult<Unit> {
        val navigationUri: Uri = Uri.parse("google.navigation:q=${Uri.encode(destination)}")
        return launchFirst(
            listOf(
                viewIntent(navigationUri, MAPS_PACKAGE),
                viewIntent(geoUri(destination)),
                viewIntent(mapsWebUri(destination))
            )
        )
    }

    /** Asks the music app to play [query]; falls back to a YouTube search. */
    fun playFromSearch(query: String): NovaResult<Unit> {
        val playIntent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH)
            .putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
            .putExtra(SearchManager.QUERY, query)
        val youtube: Uri = youtubeUri(query)
        return launchFirst(
            listOf(playIntent, viewIntent(youtube, YOUTUBE_PACKAGE), viewIntent(youtube))
        )
    }

    /** Searches apps in the Play Store. */
    fun playStoreSearch(query: String): NovaResult<Unit> {
        val storeUri: Uri = Uri.parse("market://search?q=${Uri.encode(query)}")
        val webUri: Uri = Uri.parse("https://play.google.com/store/search").buildUpon()
            .appendQueryParameter("q", query)
            .appendQueryParameter("c", "apps")
            .build()
        return launchFirst(listOf(viewIntent(storeUri), viewIntent(webUri)))
    }

    /** Opens the camera app in photo or video mode. */
    fun openCamera(video: Boolean): NovaResult<Unit> {
        val intents: List<Intent> = if (video) {
            listOf(
                Intent(MediaStore.INTENT_ACTION_VIDEO_CAMERA),
                Intent(MediaStore.ACTION_VIDEO_CAPTURE)
            )
        } else {
            listOf(
                Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA),
                Intent(MediaStore.ACTION_IMAGE_CAPTURE)
            )
        }
        return launchFirst(intents)
    }

    private fun youtubeUri(query: String): Uri =
        Uri.parse(YOUTUBE_SEARCH_URL).buildUpon()
            .appendQueryParameter("search_query", query)
            .build()

    private fun geoUri(query: String): Uri = Uri.parse("geo:0,0?q=${Uri.encode(query)}")

    private fun mapsWebUri(query: String): Uri =
        Uri.parse(MAPS_WEB_URL).buildUpon()
            .appendQueryParameter("api", "1")
            .appendQueryParameter("query", query)
            .build()

    private fun viewIntent(uri: Uri, packageName: String? = null): Intent {
        val intent = Intent(Intent.ACTION_VIEW, uri)
        if (packageName != null) intent.setPackage(packageName)
        return intent
    }

    /** Starts the first intent that some app can handle. */
    private fun launchFirst(intents: List<Intent>): NovaResult<Unit> {
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                appContext.startActivity(intent)
                return NovaResult.Success(Unit)
            } catch (e: ActivityNotFoundException) {
                continue
            } catch (e: SecurityException) {
                NovaLogger.w(TAG, "Action refused by the phone", e)
                continue
            } catch (e: Exception) {
                NovaLogger.e(TAG, "Action failed", e)
                continue
            }
        }
        return NovaResult.failure(
            ErrorCode.NOT_FOUND,
            "এই কাজের জন্য ফোনে উপযুক্ত অ্যাপ পাওয়া যায়নি।"
        )
    }

    private companion object {
        const val TAG: String = "QuickActions"
        const val CHROME_PACKAGE: String = "com.android.chrome"
        const val YOUTUBE_PACKAGE: String = "com.google.android.youtube"
        const val MAPS_PACKAGE: String = "com.google.android.apps.maps"
        const val GOOGLE_SEARCH_URL: String = "https://www.google.com/search"
        const val YOUTUBE_SEARCH_URL: String = "https://www.youtube.com/results"
        const val MAPS_WEB_URL: String = "https://www.google.com/maps/search/"
    }
}
