#!/usr/bin/env bash
# NOVA AI - Phase 16 setup script: music keys, web/YouTube/Maps search, navigation, camera.
# Additive: new media package and parser; small additive lines in a few existing files.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
HOME_FILE="$BASE/ui/screens/HomeScreen.kt"
PARSER_FILE="$BASE/nlp/IntentParser.kt"
ENTITY_FILE="$BASE/nlp/IntentEntity.kt"
MODELS_FILE="$BASE/core/Models.kt"
INSIGHT_FILE="$BASE/ui/components/IntentInsightCard.kt"

for required in \
  "$BASE/time/TimeCommandController.kt" \
  "$BASE/system/SystemActionOutcome.kt" \
  "$HOME_FILE" "$PARSER_FILE" "$ENTITY_FILE" "$MODELS_FILE" "$INSIGHT_FILE"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after P1 to P15 are installed." >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
mkdir -p "$BASE/media"

# ---------- A. Two new command types: NAVIGATE and CAPTURE_MEDIA (additive) ----------
if ! grep -q "CAPTURE_MEDIA" "$MODELS_FILE"; then
  grep -q '^    MEDIA_CONTROL,$' "$MODELS_FILE" \
    || { echo "ERROR: Models anchor not found" >&2; exit 1; }
  cat > "$TMP_DIR/models_add.txt" <<'EOF'
    NAVIGATE,
    CAPTURE_MEDIA,
EOF
  sed -i "/^    MEDIA_CONTROL,$/r $TMP_DIR/models_add.txt" "$MODELS_FILE"
fi
grep -q "CAPTURE_MEDIA" "$MODELS_FILE" || { echo "ERROR: Models edit failed" >&2; exit 1; }

# ---------- B. Photo and video modes (additive) ----------
if ! grep -q 'const val PHOTO' "$ENTITY_FILE"; then
  grep -q 'const val REMINDER: String = "reminder"' "$ENTITY_FILE" \
    || { echo "ERROR: IntentEntity anchor not found" >&2; exit 1; }
  cat > "$TMP_DIR/entity_add.txt" <<'EOF'
    const val PHOTO: String = "photo"
    const val VIDEO: String = "video"
EOF
  sed -i "/const val REMINDER: String = \"reminder\"/r $TMP_DIR/entity_add.txt" "$ENTITY_FILE"
fi
grep -q 'const val PHOTO' "$ENTITY_FILE" || { echo "ERROR: IntentEntity edit failed" >&2; exit 1; }

# ---------- C. Intent card: readable labels for the new types and modes ----------
if ! grep -q "intent_type_navigate" "$INSIGHT_FILE"; then
  grep -q 'IntentType.MEDIA_CONTROL -> R.string.intent_type_media_control' "$INSIGHT_FILE" \
    || { echo "ERROR: IntentInsightCard anchor (type) not found" >&2; exit 1; }
  grep -q 'IntentMode.REMINDER -> R.string.intent_value_reminder' "$INSIGHT_FILE" \
    || { echo "ERROR: IntentInsightCard anchor (mode) not found" >&2; exit 1; }
  cat > "$TMP_DIR/insight_type.txt" <<'EOF'
    IntentType.NAVIGATE -> R.string.intent_type_navigate
    IntentType.CAPTURE_MEDIA -> R.string.intent_type_capture
EOF
  cat > "$TMP_DIR/insight_mode.txt" <<'EOF'
            IntentMode.PHOTO -> R.string.intent_value_photo
            IntentMode.VIDEO -> R.string.intent_value_video
EOF
  sed -i "/IntentType.MEDIA_CONTROL -> R.string.intent_type_media_control/r $TMP_DIR/insight_type.txt" "$INSIGHT_FILE"
  sed -i "/IntentMode.REMINDER -> R.string.intent_value_reminder/r $TMP_DIR/insight_mode.txt" "$INSIGHT_FILE"
fi
grep -q "intent_type_navigate" "$INSIGHT_FILE" || { echo "ERROR: IntentInsightCard edit failed (type)" >&2; exit 1; }
grep -q "intent_value_photo" "$INSIGHT_FILE" || { echo "ERROR: IntentInsightCard edit failed (mode)" >&2; exit 1; }

# ---------- D. Parser: new rules join the chain (additive) ----------
if ! grep -q "ExtraCommandParser.parse(view)" "$PARSER_FILE"; then
  grep -q '?: parseCall(view)' "$PARSER_FILE" \
    || { echo "ERROR: IntentParser anchor not found" >&2; exit 1; }
  cat > "$TMP_DIR/parser_add.txt" <<'EOF'
            ?: ExtraCommandParser.parse(view)
EOF
  sed -i "/?: parseCall(view)/r $TMP_DIR/parser_add.txt" "$PARSER_FILE"
fi
grep -q "ExtraCommandParser.parse(view)" "$PARSER_FILE" || { echo "ERROR: IntentParser edit failed" >&2; exit 1; }

# ---------- E. New strings file ----------
cat > app/src/main/res/values/strings_p16.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="intent_type_navigate">উদ্দেশ্য: পথ দেখানো (নেভিগেশন)</string>
    <string name="intent_type_capture">উদ্দেশ্য: ছবি বা ভিডিও তোলা</string>
    <string name="intent_value_photo">ছবি তোলা (ক্যামেরা)</string>
    <string name="intent_value_video">ভিডিও রেকর্ড</string>

    <string name="media_title">গান, সার্চ ও ক্যামেরা</string>
    <string name="media_paused">গান বা ভিডিও থামালাম।</string>
    <string name="media_next">পরের গানে গেলাম।</string>
    <string name="media_previous">আগের গানে গেলাম।</string>
    <string name="media_nothing_playing">এখন কোনো গান বা ভিডিও চলছে না।</string>
    <string name="media_resume">চালানোর অনুরোধ পাঠিয়েছি। কিছু না চললে গানের অ্যাপ খুলে দেখো।</string>
    <string name="media_play_query">\"%1$s\" চালানোর চেষ্টা করছি। অ্যাপ নিজে না চালালে প্লে বাটন তুমি চাপো।</string>
    <string name="media_youtube_search">ইউটিউবে খুঁজছি: %1$s</string>
    <string name="media_web_search">গুগলে খুঁজছি: %1$s</string>
    <string name="media_maps_search">ম্যাপে খুঁজছি: %1$s</string>
    <string name="media_play_store_search">প্লে স্টোরে খুঁজছি: %1$s</string>
    <string name="media_navigate">\"%1$s\" যাওয়ার পথ দেখাচ্ছি।</string>
    <string name="media_need_query">কী খুঁজব? যেমন: ক্রোমে গাড়ির দাম সার্চ করো।</string>
    <string name="media_need_destination">কোথায় যাবে? যেমন: মিরপুর যাওয়ার রাস্তা দেখাও।</string>
    <string name="media_app_search_later">অ্যাপের ভেতরে সার্চ (যেমন Facebook বা TikTok) পরের ফেজে আসছে।</string>
    <string name="media_camera_photo">ক্যামেরা খুলেছি। ছবি তুলতে শাটার বাটন চাপো। (Accessibility আসার পর নোভা নিজে চাপবে।)</string>
    <string name="media_camera_video">ভিডিও ক্যামেরা খুলেছি। রেকর্ড বাটন চাপো। (Accessibility আসার পর নোভা নিজে চাপবে।)</string>
    <string name="media_unknown">এই কাজটি বুঝিনি। আরও পরিষ্কার করে বলো।</string>
    <string name="media_failed">সমস্যা: %1$s</string>
</resources>
EOF

# ---------- 1. ExtraCommandParser.kt ----------
cat > "$BASE/nlp/ExtraCommandParser.kt" <<'EOF'
package com.nova.ai.nlp

import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent

/**
 * Understands camera commands ("ছবি তোলো", "ভিডিও রেকর্ড করো", "ক্যামেরা খোলো")
 * and navigation commands ("মিরপুর যাওয়ার রাস্তা দেখাও").
 * Pure logic, no Android needed.
 */
internal object ExtraCommandParser {

    private const val CONF_HIGH: Float = 0.9f
    private const val CONF_LOW: Float = 0.5f

    private val PHOTO_WORDS: Set<String> = setOf(
        "ছবি", "ছবিটা", "ফটো", "photo", "picture", "pic", "selfie", "সেলফি"
    )
    private val PHOTO_VERBS: Set<String> = setOf(
        "তোলো", "তুলো", "তোল", "তুলুন", "তুলে", "take", "click", "snap", "capture"
    )
    private val VIDEO_WORDS: Set<String> = setOf("ভিডিও", "ভিডিওটা", "video")
    private val VIDEO_VERBS: Set<String> = setOf(
        "রেকর্ড", "রেকর্ডিং", "record", "recording", "শুট", "শ্যুট", "shoot"
    )
    private val CAMERA_WORDS: Set<String> = setOf("camera", "ক্যামেরা")

    private val NAVIGATION_WORDS: Set<String> = setOf(
        "navigate", "navigation", "নেভিগেট", "নেভিগেশন", "directions", "direction",
        "route", "রুট", "রাস্তা", "রাস্তাটা", "দিকনির্দেশ", "দিকনির্দেশনা", "ডিরেকশন"
    )
    private val DESTINATION_NOISE: Set<String> = setOf(
        "যাওয়ার", "যেতে", "যাব", "যাবো", "যাই", "যাচ্ছি", "যাও",
        "go", "going", "to", "from", "থেকে", "show", "me", "get",
        "পথ", "পথটা", "গন্তব্য"
    )

    /** Returns the understood command, or null if this is not a camera or navigation command. */
    fun parse(v: CommandView): NovaIntent? = parseCapture(v) ?: parseNavigation(v)

    private fun parseCapture(v: CommandView): NovaIntent? {
        val mode: String = when {
            v.hasAny(VIDEO_WORDS) && v.hasAny(VIDEO_VERBS) -> IntentMode.VIDEO
            v.hasAny(PHOTO_WORDS) && v.hasAny(PHOTO_VERBS) -> IntentMode.PHOTO
            v.hasAny(CAMERA_WORDS) && v.hasAny(IntentVocabulary.OPEN_VERBS_STRONG) -> IntentMode.PHOTO
            else -> return null
        }
        return NovaIntent(
            IntentType.CAPTURE_MEDIA,
            mapOf(IntentEntity.MODE to mode),
            CONF_HIGH
        )
    }

    private fun parseNavigation(v: CommandView): NovaIntent? {
        if (!v.hasAny(NAVIGATION_WORDS)) return null

        val destination: String = v.remaining(
            NAVIGATION_WORDS,
            DESTINATION_NOISE,
            IntentVocabulary.HELPER_WORDS,
            IntentVocabulary.COMMON_STRIP,
            IntentVocabulary.OPEN_VERBS_STRONG
        ).joinToString(" ")

        val entities = LinkedHashMap<String, String>()
        if (destination.isNotEmpty()) entities[IntentEntity.QUERY] = destination
        return NovaIntent(
            IntentType.NAVIGATE,
            entities,
            if (destination.isNotEmpty()) CONF_HIGH else CONF_LOW
        )
    }
}
EOF

# ---------- 2. MediaKeyController.kt ----------
cat > "$BASE/media/MediaKeyController.kt" <<'EOF'
package com.nova.ai.media

import android.content.Context
import android.media.AudioManager
import android.view.KeyEvent
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * Sends play, pause, next and previous to whatever app is playing now
 * (Spotify, YouTube Music, the phone's music player). No permission needed.
 */
class MediaKeyController(context: Context) {

    /** The media buttons NOVA can press. */
    enum class Key(val code: Int) {
        PLAY(KeyEvent.KEYCODE_MEDIA_PLAY),
        PAUSE(KeyEvent.KEYCODE_MEDIA_PAUSE),
        NEXT(KeyEvent.KEYCODE_MEDIA_NEXT),
        PREVIOUS(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
    }

    private val audioManager: AudioManager? =
        context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    /** True while some app is playing music or video sound. */
    fun isMediaPlaying(): Boolean = try {
        audioManager?.isMusicActive == true
    } catch (e: Exception) {
        NovaLogger.e(TAG, "Failed to check playback", e)
        false
    }

    /** Presses [key] (down and up) for the active media app. */
    fun send(key: Key): NovaResult<Unit> {
        val manager: AudioManager = audioManager
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, "ফোনের অডিও সিস্টেম পাওয়া যায়নি।")
        return try {
            manager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, key.code))
            manager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, key.code))
            NovaResult.Success(Unit)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to send media key", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "গানের নির্দেশ পাঠাতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "MediaKeyController"
    }
}
EOF

# ---------- 3. QuickActions.kt ----------
cat > "$BASE/media/QuickActions.kt" <<'EOF'
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
EOF

# ---------- 4. MediaCommandController.kt ----------
cat > "$BASE/media/MediaCommandController.kt" <<'EOF'
package com.nova.ai.media

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.R
import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.nlp.IntentAction
import com.nova.ai.nlp.IntentEntity
import com.nova.ai.nlp.IntentMode
import com.nova.ai.system.OutcomeKind
import com.nova.ai.system.SystemActionOutcome
import com.nova.ai.voice.LanguageDetector

/**
 * Carries out music control, searches, navigation and camera commands.
 * Home gives it every command; it acts only on the ones it understands and
 * keeps the last [state] for the screen to show. Use from the main thread.
 */
class MediaCommandController(context: Context) {

    private val appContext: Context = context.applicationContext
    private val keys = MediaKeyController(appContext)
    private val quick = QuickActions(appContext)
    private val brain = RuleBasedBrain()

    /** The last result, or null when there is nothing to show. */
    var state: SystemActionOutcome? by mutableStateOf<SystemActionOutcome?>(null)
        private set

    /** Looks at [text]; if it is a music, search, navigation or camera command, carries it out. */
    fun handleCommand(text: String) {
        val intent: NovaIntent? = analyze(text)
        if (intent == null) {
            state = null
            return
        }
        state = when (intent.type) {
            IntentType.MEDIA_CONTROL -> media(intent)
            IntentType.WEB_SEARCH -> search(intent)
            IntentType.NAVIGATE -> navigate(intent)
            IntentType.CAPTURE_MEDIA -> capture(intent)
            else -> null
        }
    }

    /** Hides the result card. */
    fun dismiss() {
        state = null
    }

    // ---------------------------------------------------------------- music

    private fun media(intent: NovaIntent): SystemActionOutcome {
        val query: String? = cleanQuery(intent.entities[IntentEntity.QUERY])
        val app: String? = intent.entities[IntentEntity.APP]
        return when (intent.entities[IntentEntity.ACTION]) {
            IntentAction.PAUSE -> pressKey(MediaKeyController.Key.PAUSE, R.string.media_paused)
            IntentAction.NEXT -> pressKey(MediaKeyController.Key.NEXT, R.string.media_next)
            IntentAction.PREVIOUS -> pressKey(MediaKeyController.Key.PREVIOUS, R.string.media_previous)
            IntentAction.PLAY -> play(query, app)
            else -> hint(text(R.string.media_unknown))
        }
    }

    private fun pressKey(key: MediaKeyController.Key, @StringRes doneMessage: Int): SystemActionOutcome {
        if (!keys.isMediaPlaying()) return hint(text(R.string.media_nothing_playing))
        return when (val result: NovaResult<Unit> = keys.send(key)) {
            is NovaResult.Success -> done(text(doneMessage))
            is NovaResult.Failure -> failed(result.error.message)
        }
    }

    private fun play(query: String?, app: String?): SystemActionOutcome {
        if (query == null) {
            return when (val result: NovaResult<Unit> = keys.send(MediaKeyController.Key.PLAY)) {
                is NovaResult.Success -> done(text(R.string.media_resume))
                is NovaResult.Failure -> failed(result.error.message)
            }
        }
        val onYoutube: Boolean = app == APP_YOUTUBE
        val result: NovaResult<Unit> =
            if (onYoutube) quick.youtubeSearch(query) else quick.playFromSearch(query)
        return outcomeOf(
            result,
            if (onYoutube) text(R.string.media_youtube_search, query) else text(R.string.media_play_query, query)
        )
    }

    // ---------------------------------------------------------------- search

    private fun search(intent: NovaIntent): SystemActionOutcome {
        val query: String = cleanQuery(intent.entities[IntentEntity.QUERY])
            ?: return hint(text(R.string.media_need_query))
        val app: String? = intent.entities[IntentEntity.APP]

        return when (app) {
            null, APP_CHROME, APP_GOOGLE ->
                outcomeOf(
                    quick.webSearch(query, preferChrome = app == APP_CHROME),
                    text(R.string.media_web_search, query)
                )
            APP_YOUTUBE ->
                outcomeOf(quick.youtubeSearch(query), text(R.string.media_youtube_search, query))
            APP_MAPS ->
                outcomeOf(quick.mapsSearch(query), text(R.string.media_maps_search, query))
            APP_PLAY_STORE ->
                outcomeOf(quick.playStoreSearch(query), text(R.string.media_play_store_search, query))
            else -> hint(text(R.string.media_app_search_later))
        }
    }

    // ---------------------------------------------------------------- navigation and camera

    private fun navigate(intent: NovaIntent): SystemActionOutcome {
        val destination: String = cleanQuery(intent.entities[IntentEntity.QUERY])
            ?: return hint(text(R.string.media_need_destination))
        return outcomeOf(quick.navigate(destination), text(R.string.media_navigate, destination))
    }

    private fun capture(intent: NovaIntent): SystemActionOutcome {
        val video: Boolean = intent.entities[IntentEntity.MODE] == IntentMode.VIDEO
        return when (val result: NovaResult<Unit> = quick.openCamera(video)) {
            is NovaResult.Success -> SystemActionOutcome(
                OutcomeKind.GUIDED,
                text(if (video) R.string.media_camera_video else R.string.media_camera_photo)
            )
            is NovaResult.Failure -> failed(result.error.message)
        }
    }

    // ---------------------------------------------------------------- helpers

    private fun outcomeOf(result: NovaResult<Unit>, successMessage: String): SystemActionOutcome =
        when (result) {
            is NovaResult.Success -> done(successMessage)
            is NovaResult.Failure -> failed(result.error.message)
        }

    private fun cleanQuery(raw: String?): String? = raw?.trim()?.takeIf { it.isNotEmpty() }

    private fun analyze(text: String): NovaIntent? {
        if (text.isBlank()) return null
        val command = VoiceCommand(
            rawText = text,
            language = LanguageDetector.detect(text),
            timestampMs = System.currentTimeMillis()
        )
        return (brain.analyze(command, emptyList()) as? NovaResult.Success)?.value
    }

    private fun text(@StringRes id: Int, vararg args: Any): String = appContext.getString(id, *args)

    private fun done(message: String) = SystemActionOutcome(OutcomeKind.DONE, message)
    private fun hint(message: String) = SystemActionOutcome(OutcomeKind.HINT, message)
    private fun failed(message: String) = SystemActionOutcome(OutcomeKind.FAILED, message)

    private companion object {
        const val APP_CHROME: String = "Chrome"
        const val APP_GOOGLE: String = "Google"
        const val APP_YOUTUBE: String = "YouTube"
        const val APP_MAPS: String = "Maps"
        const val APP_PLAY_STORE: String = "Play Store"
    }
}
EOF

# ---------- 5. MediaActionCard.kt ----------
cat > "$BASE/ui/components/MediaActionCard.kt" <<'EOF'
package com.nova.ai.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.media.MediaCommandController
import com.nova.ai.system.OutcomeKind
import com.nova.ai.system.SystemActionOutcome

/**
 * Shows the result of a music, search, navigation or camera command on the
 * Home screen. Shows nothing while there is nothing to report.
 */
@Composable
fun MediaActionCard(
    controller: MediaCommandController,
    modifier: Modifier = Modifier
) {
    val outcome: SystemActionOutcome = controller.state ?: return

    val marker: String = when (outcome.kind) {
        OutcomeKind.DONE -> "✅"
        OutcomeKind.GUIDED -> "👉"
        OutcomeKind.NEEDS_PERMISSION -> "🔐"
        OutcomeKind.HINT -> "💡"
        OutcomeKind.FAILED -> "⚠️"
    }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.media_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(text = "$marker ${outcome.message}")
            TextButton(onClick = { controller.dismiss() }) {
                Text(stringResource(R.string.action_dismiss))
            }
        }
    }
}
EOF

# ---------- F. HomeScreen.kt: a few additive lines (idempotent) ----------
if ! grep -q "MediaCommandController" "$HOME_FILE"; then
  grep -q '^import com.nova.ai.time.TimeCommandController$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (import) not found" >&2; exit 1; }
  grep -q 'val timeController: TimeCommandController = remember' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (controller) not found" >&2; exit 1; }
  grep -q 'timeController.handleCommand(command.rawText)' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (voice command) not found" >&2; exit 1; }
  grep -q 'timeController.handleCommand(commandText)' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (send button) not found" >&2; exit 1; }
  grep -q '^        TimeActionCard(controller = timeController)$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (card) not found" >&2; exit 1; }

  cat > "$TMP_DIR/home_imports.txt" <<'EOF'
import com.nova.ai.media.MediaCommandController
import com.nova.ai.ui.components.MediaActionCard
EOF
  cat > "$TMP_DIR/home_controller.txt" <<'EOF'

    // Runs music control, searches, navigation and camera commands.
    val mediaController: MediaCommandController = remember { MediaCommandController(context) }
EOF
  cat > "$TMP_DIR/home_voice.txt" <<'EOF'
                    mediaController.handleCommand(command.rawText)
EOF
  cat > "$TMP_DIR/home_send.txt" <<'EOF'
                    mediaController.handleCommand(commandText)
EOF
  cat > "$TMP_DIR/home_card.txt" <<'EOF'

        MediaActionCard(controller = mediaController)
EOF

  sed -i "/^import com.nova.ai.time.TimeCommandController$/r $TMP_DIR/home_imports.txt" "$HOME_FILE"
  sed -i "/val timeController: TimeCommandController = remember/r $TMP_DIR/home_controller.txt" "$HOME_FILE"
  sed -i "/timeController.handleCommand(command.rawText)/r $TMP_DIR/home_voice.txt" "$HOME_FILE"
  sed -i "/timeController.handleCommand(commandText)/r $TMP_DIR/home_send.txt" "$HOME_FILE"
  sed -i "/^        TimeActionCard(controller = timeController)$/r $TMP_DIR/home_card.txt" "$HOME_FILE"
fi
grep -q "val mediaController: MediaCommandController" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (controller)" >&2; exit 1; }
grep -q "mediaController.handleCommand(command.rawText)" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (voice)" >&2; exit 1; }
grep -q "mediaController.handleCommand(commandText)" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (send)" >&2; exit 1; }
grep -q "MediaActionCard(controller = mediaController)" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (card)" >&2; exit 1; }

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "P16: music keys, web/YouTube/Maps search, navigation, camera"
git push

echo "P16 files created and pushed."
