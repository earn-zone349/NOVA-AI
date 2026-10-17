#!/usr/bin/env bash
# NOVA AI - Phase 12 setup script: app library (user picks apps + nicknames) and opening apps.
# Additive: previous behavior is kept in every rewritten file.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
MANIFEST="app/src/main/AndroidManifest.xml"

for required in \
  "$BASE/nlp/IntentParser.kt" \
  "$BASE/data/db/NovaDatabase.kt" \
  "$BASE/ui/screens/OnboardingScreen.kt" \
  "$BASE/ui/screens/HomeScreen.kt" \
  "$BASE/ui/screens/PermissionsScreen.kt" \
  "app/src/main/res/values/strings_ui.xml" \
  "app/src/main/res/values/strings_p11.xml"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after P1 to P11 are installed." >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"

# ---------- A. Manifest: let the app see launcher apps (no QUERY_ALL_PACKAGES needed) ----------
if ! grep -q "nova-launcher-query" "$MANIFEST"; then
  cat > "$TMP_DIR/launcher_query.txt" <<'EOF'
        <!-- nova-launcher-query -->
        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent>
EOF
  sed -i "/<queries>/r $TMP_DIR/launcher_query.txt" "$MANIFEST"
fi
grep -q "nova-launcher-query" "$MANIFEST" || { echo "ERROR: manifest edit failed" >&2; exit 1; }

# ---------- B. Update two texts that said "coming later" ----------
sed -i 's|<string name="home_status_command_received">.*</string>|<string name="home_status_command_received">কমান্ড নেওয়া হয়েছে।</string>|' app/src/main/res/values/strings_ui.xml
sed -i 's|<string name="intent_note">.*</string>|<string name="intent_note">বোঝা হয়েছে। এখন শুধু অ্যাপ খোলা কাজ করে, বাকি কাজ পরের ফেজে আসবে।</string>|' app/src/main/res/values/strings_p11.xml

# ---------- C. New strings file ----------
cat > app/src/main/res/values/strings_p12.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- App library (Access tab) -->
    <string name="apps_title">নোভার অ্যাপ</string>
    <string name="apps_note">নোভা শুধু এই তালিকার অ্যাপ খুলবে। তালিকা শুধু তোমার ফোনেই থাকে।</string>
    <string name="apps_count">মোট %1$d টি অ্যাপ যোগ করা আছে</string>
    <string name="apps_add_button">অ্যাপ যোগ করো</string>
    <string name="apps_empty">এখনো কোনো অ্যাপ যোগ করা হয়নি। \"অ্যাপ যোগ করো\" চেপে বাছাই করো।</string>
    <string name="apps_alias_label">ডাকনাম: %1$s</string>
    <string name="apps_alias_none">ডাকনাম নেই</string>
    <string name="apps_not_installed">⚠ ফোনে এই অ্যাপ নেই</string>
    <string name="apps_edit">ডাকনাম বদলাও</string>
    <string name="apps_remove">বাদ দাও</string>
    <string name="apps_error">অ্যাপের তালিকায় সমস্যা: %1$s</string>

    <!-- Picker dialog -->
    <string name="picker_title">অ্যাপ বাছাই করো</string>
    <string name="picker_search">অ্যাপ খোঁজো</string>
    <string name="picker_confirm">যোগ করো (%1$d)</string>
    <string name="picker_cancel">বাতিল</string>
    <string name="picker_already">✓ যোগ করা আছে</string>
    <string name="picker_empty">কোনো অ্যাপ পাওয়া যায়নি।</string>

    <!-- Alias dialog -->
    <string name="alias_title">ডাকনাম: %1$s</string>
    <string name="alias_help">যে নামে তুমি অ্যাপটিকে ডাকো, সেটা লেখো। যেমন: ফ্রি ফায়ার, এফএফ</string>
    <string name="alias_hint">ডাকনাম (কমা দিয়ে আলাদা করো)</string>
    <string name="alias_save">সেভ করো</string>

    <!-- Onboarding step -->
    <string name="onboarding_apps_title">কোন অ্যাপগুলো নোভা চালাবে?</string>
    <string name="onboarding_apps_body">নোভা শুধু তোমার বাছাই করা অ্যাপ খুলবে। পরে Access ট্যাব থেকে যোগ বা বাদ দেওয়া যাবে।</string>
    <string name="onboarding_apps_button">অ্যাপ বাছাই করো</string>
    <string name="onboarding_apps_selected">%1$d টি অ্যাপ বাছাই করা হয়েছে</string>
    <string name="onboarding_apps_skip_note">এখন না চাইলে সরাসরি \"শুরু করো\" চাপো।</string>

    <!-- Home: app action card -->
    <string name="action_title">অ্যাপ খোলা</string>
    <string name="action_opened">✅ খুলছি: %1$s</string>
    <string name="action_confirm">\"%1$s\" বলতে কি %2$s বুঝিয়েছো?</string>
    <string name="action_confirm_yes">হ্যাঁ, খোলো</string>
    <string name="action_confirm_no">না</string>
    <string name="action_choose">\"%1$s\": কোনটি খুলব?</string>
    <string name="action_suggest">\"%1$s\" নোভার তালিকায় নেই। ফোনে এগুলো পেয়েছি। যোগ করে খুলব?</string>
    <string name="action_suggest_button">%1$s যোগ করে খোলো</string>
    <string name="action_not_found">\"%1$s\" নামে কোনো অ্যাপ ফোনে পেলাম না। Access ট্যাবে \"অ্যাপ যোগ করো\" দিয়ে খুঁজে দেখো।</string>
    <string name="action_failed">অ্যাপ খুলতে সমস্যা: %1$s</string>
    <string name="action_dismiss">বন্ধ করো</string>
</resources>
EOF

mkdir -p "$BASE/apps" "$BASE/data/entity" "$BASE/data/dao" "$BASE/data/db" "$BASE/ui/components"

# ---------- 1. AppEntity.kt ----------
cat > "$BASE/data/entity/AppEntity.kt" <<'EOF'
package com.nova.ai.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/** One app the user allowed NOVA to control. [aliases] holds nicknames, one per line. */
@Entity(tableName = "nova_apps")
data class AppEntity(
    @PrimaryKey
    @ColumnInfo(name = "package_name") val packageName: String,
    @ColumnInfo(name = "label") val label: String,
    @ColumnInfo(name = "aliases") val aliases: String,
    @ColumnInfo(name = "added_at_ms") val addedAtMs: Long
)
EOF

# ---------- 2. AppDao.kt ----------
cat > "$BASE/data/dao/AppDao.kt" <<'EOF'
package com.nova.ai.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.nova.ai.data.entity.AppEntity

/** Database access for the app library. Blocking: call from a background thread. */
@Dao
interface AppDao {

    /** Adds the app unless it already exists. Returns -1 when it already existed. */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    fun insertIfAbsent(app: AppEntity): Long

    @Query("SELECT * FROM nova_apps ORDER BY label COLLATE NOCASE ASC")
    fun getAll(): List<AppEntity>

    @Query("SELECT * FROM nova_apps WHERE package_name = :packageName LIMIT 1")
    fun get(packageName: String): AppEntity?

    @Query("UPDATE nova_apps SET aliases = :aliases WHERE package_name = :packageName")
    fun updateAliases(packageName: String, aliases: String): Int

    @Query("DELETE FROM nova_apps WHERE package_name = :packageName")
    fun delete(packageName: String): Int

    @Query("SELECT COUNT(*) FROM nova_apps")
    fun count(): Int
}
EOF

# ---------- 3. NovaDatabase.kt (P5 content kept; app table + safe migration added) ----------
cat > "$BASE/data/db/NovaDatabase.kt" <<'EOF'
package com.nova.ai.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.nova.ai.data.dao.AppDao
import com.nova.ai.data.dao.LogDao
import com.nova.ai.data.dao.MemoryDao
import com.nova.ai.data.dao.TaskDao
import com.nova.ai.data.entity.AppEntity
import com.nova.ai.data.entity.LogEntity
import com.nova.ai.data.entity.MemoryEntity
import com.nova.ai.data.entity.TaskEntity

/**
 * Local on-device database (logs, task history, personal memory, app library).
 * Nothing here leaves the phone.
 *
 * Version 2 adds the app library table. The migration keeps all existing data.
 */
@Database(
    entities = [
        LogEntity::class,
        TaskEntity::class,
        MemoryEntity::class,
        AppEntity::class
    ],
    version = 2,
    exportSchema = false
)
abstract class NovaDatabase : RoomDatabase() {

    abstract fun logDao(): LogDao
    abstract fun taskDao(): TaskDao
    abstract fun memoryDao(): MemoryDao
    abstract fun appDao(): AppDao

    companion object {
        private const val DB_NAME: String = "nova_ai.db"

        /** Version 1 to 2: create the app library table. */
        private val MIGRATION_1_2: Migration = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `nova_apps` (" +
                        "`package_name` TEXT NOT NULL, " +
                        "`label` TEXT NOT NULL, " +
                        "`aliases` TEXT NOT NULL, " +
                        "`added_at_ms` INTEGER NOT NULL, " +
                        "PRIMARY KEY(`package_name`))"
                )
            }
        }

        @Volatile
        private var instance: NovaDatabase? = null

        /** Returns the single shared database instance, creating it if needed. */
        fun getInstance(context: Context): NovaDatabase {
            return instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    NovaDatabase::class.java,
                    DB_NAME
                ).addMigrations(MIGRATION_1_2).build().also { instance = it }
            }
        }
    }
}
EOF

# ---------- 4. AppModels.kt ----------
cat > "$BASE/apps/AppModels.kt" <<'EOF'
package com.nova.ai.apps

/** An app found on the phone that can be launched. */
data class InstalledApp(val packageName: String, val label: String)

/** An app the user allowed NOVA to control, with the nicknames the user gave it. */
data class RegisteredApp(
    val packageName: String,
    val label: String,
    val aliases: List<String> = emptyList()
) {
    /** The app's real name followed by every nickname. */
    fun allNames(): List<String> = listOf(label) + aliases
}

/** One candidate app with how well its name matched what the user said. */
data class AppMatch(val app: RegisteredApp, val score: Float, val matchedName: String)

/** The decision after matching a spoken name against the app library. */
sealed class MatchOutcome {
    /** One clear winner: open it directly. */
    data class Single(val app: RegisteredApp) : MatchOutcome()

    /** One likely app, but not sure enough: ask the user first. */
    data class Confirm(val app: RegisteredApp) : MatchOutcome()

    /** Several apps fit equally: let the user choose. */
    data class Ambiguous(val apps: List<RegisteredApp>) : MatchOutcome()

    /** Nothing in the library fits. */
    object None : MatchOutcome()
}
EOF

# ---------- 5. PhoneticKey.kt ----------
cat > "$BASE/apps/PhoneticKey.kt" <<'EOF'
package com.nova.ai.apps

import com.nova.ai.nlp.DigitConverter
import java.text.Normalizer
import java.util.Locale

/**
 * Turns app names (Bangla or English) into comparable sound-alike keys, so that
 * "ফ্রী ফায়ার" and "Free Fire" can be matched. Pure logic, no Android needed.
 */
internal object PhoneticKey {

    private const val HASANTA: Char = '\u09CD'
    private const val NUKTA: Char = '\u09BC'
    private const val YA: Char = '\u09AF'

    private val NON_NAME_CHARS: Regex = Regex("[^\\p{L}\\p{N}\\p{M}]+")
    private val SOFT_C: Regex = Regex("c(?!h)")
    private val VOWEL_LIKE: Set<Char> = setOf('a', 'e', 'i', 'o', 'u', 'y', 'w')

    private val SOUND_RULES: List<Pair<String, String>> = listOf(
        "ph" to "f", "ck" to "k", "qu" to "kw", "x" to "ks",
        "q" to "k", "z" to "j", "v" to "b", "ee" to "i", "oo" to "u"
    )

    private val BANGLA_TO_LATIN: Map<Char, String> = mapOf(
        'অ' to "o", 'আ' to "a", 'ই' to "i", 'ঈ' to "i", 'উ' to "u", 'ঊ' to "u", 'ঋ' to "ri",
        'এ' to "e", 'ঐ' to "oi", 'ও' to "o", 'ঔ' to "ou",
        'া' to "a", 'ি' to "i", 'ী' to "i", 'ু' to "u", 'ূ' to "u", 'ৃ' to "ri",
        'ে' to "e", 'ৈ' to "oi", 'ো' to "o", 'ৌ' to "ou",
        'ং' to "ng", 'ঃ' to "", 'ঁ' to "",
        'ক' to "k", 'খ' to "kh", 'গ' to "g", 'ঘ' to "gh", 'ঙ' to "ng",
        'চ' to "ch", 'ছ' to "ch", 'জ' to "j", 'ঝ' to "jh", 'ঞ' to "n",
        'ট' to "t", 'ঠ' to "th", 'ড' to "d", 'ঢ' to "dh", 'ণ' to "n",
        'ত' to "t", 'থ' to "th", 'দ' to "d", 'ধ' to "dh", 'ন' to "n",
        'প' to "p", 'ফ' to "f", 'ব' to "b", 'ভ' to "v", 'ম' to "m",
        'য' to "j", 'র' to "r", 'ল' to "l", 'শ' to "sh", 'ষ' to "sh", 'স' to "s", 'হ' to "h",
        '\u09DC' to "r", '\u09DD' to "r", '\u09DF' to "y", 'ৎ' to "t"
    )

    /** Letters and digits only, lowercase. Used for exact comparison. */
    fun nameKey(text: String): String =
        NON_NAME_CHARS.replace(
            Normalizer.normalize(text, Normalizer.Form.NFC).lowercase(Locale.ROOT),
            ""
        )

    /** Bangla letters written in Latin letters; Latin and digits are kept. */
    fun toLatin(text: String): String {
        val input: String = Normalizer.normalize(DigitConverter.toAscii(text), Normalizer.Form.NFC)
        val out = StringBuilder(input.length + 8)
        var afterHasanta = false

        for (character in input) {
            if (character == HASANTA) {
                afterHasanta = true
                continue
            }
            when {
                character == NUKTA -> applyNukta(out)
                character == YA && afterHasanta -> out.append("y")
                character in BANGLA_TO_LATIN -> out.append(BANGLA_TO_LATIN.getValue(character))
                character in 'a'..'z' || character in 'A'..'Z' || character in '0'..'9' ->
                    out.append(character.lowercaseChar())
                else -> Unit
            }
            afterHasanta = false
        }
        return out.toString()
    }

    /** Sound-alike key: same sound gives the same key, in Bangla or English. */
    fun phonetic(text: String): String {
        var sound: String = toLatin(text)
        for ((from, to) in SOUND_RULES) {
            sound = sound.replace(from, to)
        }
        sound = SOFT_C.replace(sound, "k")
        return collapseRepeats(sound)
    }

    /** Consonants of the sound-alike key. Ignores vowel differences ("fire" and "fayar"). */
    fun skeleton(text: String): String =
        collapseRepeats(phonetic(text).filter { it !in VOWEL_LIKE })

    /** 1.0 for equal text, 0.0 for completely different. */
    fun similarity(first: String, second: String): Float {
        if (first.isEmpty() && second.isEmpty()) return 0f
        val longest: Int = maxOf(first.length, second.length)
        return 1f - distance(first, second).toFloat() / longest.toFloat()
    }

    private fun applyNukta(out: StringBuilder) {
        when {
            out.endsWith("dh") -> replaceTail(out, 2, "r")
            out.endsWith("d") -> replaceTail(out, 1, "r")
            out.endsWith("j") -> replaceTail(out, 1, "y")
            else -> Unit
        }
    }

    private fun replaceTail(out: StringBuilder, length: Int, replacement: String) {
        out.setLength(out.length - length)
        out.append(replacement)
    }

    private fun collapseRepeats(text: String): String {
        val out = StringBuilder(text.length)
        for (character in text) {
            if (out.isEmpty() || out[out.length - 1] != character) out.append(character)
        }
        return out.toString()
    }

    /** Number of single-letter edits needed to turn [first] into [second]. */
    private fun distance(first: String, second: String): Int {
        if (first == second) return 0
        var previous = IntArray(second.length + 1) { it }
        var current = IntArray(second.length + 1)

        for (row in 1..first.length) {
            current[0] = row
            for (column in 1..second.length) {
                val cost: Int = if (first[row - 1] == second[column - 1]) 0 else 1
                current[column] = minOf(
                    previous[column] + 1,
                    current[column - 1] + 1,
                    previous[column - 1] + cost
                )
            }
            val swap: IntArray = previous
            previous = current
            current = swap
        }
        return previous[second.length]
    }
}
EOF

# ---------- 6. AppNameMatcher.kt ----------
cat > "$BASE/apps/AppNameMatcher.kt" <<'EOF'
package com.nova.ai.apps

/**
 * Matches the app name the user said against the apps in the library.
 * Order of trust: exact name, same sound, name inside name, similar sound.
 * Pure logic, no Android needed.
 */
object AppNameMatcher {

    const val MIN_SCORE: Float = 0.72f
    const val STRONG_SCORE: Float = 0.9f
    const val CLEAR_GAP: Float = 0.08f

    private const val MAX_AMBIGUOUS: Int = 3
    private const val SCORE_EXACT: Float = 1.0f
    private const val SCORE_SAME_SOUND: Float = 0.95f
    private const val SCORE_CONTAINS: Float = 0.92f
    private const val MIN_CONTAINS_LENGTH: Int = 3
    private const val MIN_CONTAINS_RATIO: Float = 0.5f
    private const val MIN_SKELETON_LENGTH: Int = 2
    private const val SOUND_WEIGHT: Float = 0.35f
    private const val SKELETON_WEIGHT: Float = 0.65f

    /** Standard names from the command parser, mapped to the names phones really use. */
    private val STANDARD_SYNONYMS: Map<String, List<String>> = mapOf(
        "dialer" to listOf("Phone", "Dialer", "ফোন"),
        "gallery" to listOf("Photos", "Gallery"),
        "files" to listOf("My Files", "Files by Google", "File Manager", "Files"),
        "x" to listOf("Twitter", "X"),
        "contacts" to listOf("Contacts", "People"),
        "google" to listOf("Google", "Google app"),
        "clock" to listOf("Clock", "Alarm", "ঘড়ি"),
        "calendar" to listOf("Calendar", "Google Calendar"),
        "maps" to listOf("Maps", "Google Maps")
    )

    /** Matches [spoken] against [apps] and decides what to do. */
    fun match(spoken: String, apps: List<RegisteredApp>): MatchOutcome =
        decide(rank(spoken, apps))

    /** All apps that fit [spoken] well enough, best first. */
    fun rank(spoken: String, apps: List<RegisteredApp>): List<AppMatch> {
        val variants: List<String> = spokenVariants(spoken)
        if (variants.isEmpty()) return emptyList()

        val matches = ArrayList<AppMatch>()
        for (app in apps) {
            var bestScore = 0f
            var bestName: String = app.label
            for (name in app.allNames()) {
                for (variant in variants) {
                    val score: Float = scoreNames(variant, name)
                    if (score > bestScore) {
                        bestScore = score
                        bestName = name
                    }
                }
            }
            if (bestScore >= MIN_SCORE) matches.add(AppMatch(app, bestScore, bestName))
        }
        return matches.sortedByDescending { it.score }
    }

    /** Turns a ranked list into one decision. */
    fun decide(ranked: List<AppMatch>): MatchOutcome {
        val top: AppMatch = ranked.firstOrNull() ?: return MatchOutcome.None
        val close: List<AppMatch> = ranked.filter { top.score - it.score < CLEAR_GAP }
        return when {
            close.size >= 2 -> MatchOutcome.Ambiguous(close.take(MAX_AMBIGUOUS).map { it.app })
            top.score >= STRONG_SCORE -> MatchOutcome.Single(top.app)
            else -> MatchOutcome.Confirm(top.app)
        }
    }

    private fun spokenVariants(spoken: String): List<String> {
        val trimmed: String = spoken.trim()
        val key: String = PhoneticKey.nameKey(trimmed)
        if (key.isEmpty()) return emptyList()
        return listOf(trimmed) + STANDARD_SYNONYMS[key].orEmpty()
    }

    private fun scoreNames(spoken: String, name: String): Float {
        val spokenKey: String = PhoneticKey.nameKey(spoken)
        val nameKey: String = PhoneticKey.nameKey(name)
        if (spokenKey.isEmpty() || nameKey.isEmpty()) return 0f
        if (spokenKey == nameKey) return SCORE_EXACT

        val spokenSound: String = PhoneticKey.phonetic(spoken)
        val nameSound: String = PhoneticKey.phonetic(name)
        if (spokenSound.isNotEmpty() && spokenSound == nameSound) return SCORE_SAME_SOUND

        val contains: Float = containsScore(spokenSound, nameSound)

        val spokenSkeleton: String = PhoneticKey.skeleton(spoken)
        val nameSkeleton: String = PhoneticKey.skeleton(name)
        val soundSimilarity: Float = PhoneticKey.similarity(spokenSound, nameSound)
        val similarity: Float =
            if (spokenSkeleton.length >= MIN_SKELETON_LENGTH && nameSkeleton.length >= MIN_SKELETON_LENGTH) {
                SOUND_WEIGHT * soundSimilarity +
                    SKELETON_WEIGHT * PhoneticKey.similarity(spokenSkeleton, nameSkeleton)
            } else {
                soundSimilarity
            }
        return maxOf(contains, similarity)
    }

    /** High score when one sound key sits inside the other and is a big enough part of it. */
    private fun containsScore(first: String, second: String): Float {
        val shorter: String = if (first.length <= second.length) first else second
        val longer: String = if (first.length <= second.length) second else first
        if (shorter.length < MIN_CONTAINS_LENGTH) return 0f
        if (!longer.contains(shorter)) return 0f
        val ratio: Float = shorter.length.toFloat() / longer.length.toFloat()
        return if (ratio >= MIN_CONTAINS_RATIO) SCORE_CONTAINS else 0f
    }
}
EOF

# ---------- 7. AliasCodec.kt ----------
cat > "$BASE/apps/AliasCodec.kt" <<'EOF'
package com.nova.ai.apps

/** Saves and cleans nicknames. Nicknames are stored one per line. */
object AliasCodec {

    private const val SEPARATOR: String = "\n"
    private const val MAX_ALIASES: Int = 10
    private const val MAX_ALIAS_LENGTH: Int = 40
    private val WHITESPACE: Regex = Regex("\\s+")

    fun encode(aliases: List<String>): String = aliases.joinToString(SEPARATOR)

    fun decode(stored: String): List<String> =
        stored.split(SEPARATOR).map { it.trim() }.filter { it.isNotEmpty() }

    /** Splits what the user typed (commas or new lines) into separate nicknames. */
    fun parseInput(text: String): List<String> =
        text.split(',', ';', '\n').map { it.trim() }.filter { it.isNotEmpty() }

    /**
     * Cleans a nickname list: trims, limits length and count, removes empty and
     * repeated names, and drops nicknames equal to the app's real [label].
     */
    fun sanitize(raw: List<String>, label: String): List<String> {
        val seen = HashSet<String>()
        seen.add(PhoneticKey.nameKey(label))

        val result = ArrayList<String>()
        for (item in raw) {
            val clean: String = item.replace(WHITESPACE, " ").trim().take(MAX_ALIAS_LENGTH)
            if (clean.isEmpty()) continue
            val key: String = PhoneticKey.nameKey(clean)
            if (key.isEmpty() || !seen.add(key)) continue
            result.add(clean)
            if (result.size >= MAX_ALIASES) break
        }
        return result
    }
}
EOF

# ---------- 8. InstalledAppScanner.kt ----------
cat > "$BASE/apps/InstalledAppScanner.kt" <<'EOF'
package com.nova.ai.apps

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.os.Build
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Reads the apps that appear in the phone's app drawer. */
class InstalledAppScanner(context: Context) {

    private val appContext: Context = context.applicationContext

    /** Lists launchable apps, sorted by name. NOVA itself is not included. */
    suspend fun scan(): NovaResult<List<InstalledApp>> = withContext(Dispatchers.IO) {
        try {
            val packageManager: PackageManager = appContext.packageManager
            val launcherIntent: Intent =
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)

            val apps: List<InstalledApp> = queryLaunchers(packageManager, launcherIntent)
                .mapNotNull { info ->
                    val packageName: String? = info.activityInfo?.packageName
                    if (packageName == null) {
                        null
                    } else {
                        InstalledApp(packageName, info.loadLabel(packageManager).toString().trim())
                    }
                }
                .filter { it.packageName != appContext.packageName && it.label.isNotEmpty() }
                .distinctBy { it.packageName }
                .sortedBy { it.label.lowercase(Locale.ROOT) }

            NovaResult.Success(apps)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to scan installed apps", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "ফোনের অ্যাপের তালিকা পড়া যায়নি।", e)
        }
    }

    @Suppress("DEPRECATION")
    private fun queryLaunchers(packageManager: PackageManager, intent: Intent): List<ResolveInfo> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0L))
        } else {
            packageManager.queryIntentActivities(intent, 0)
        }

    private companion object {
        const val TAG: String = "InstalledAppScanner"
    }
}
EOF

# ---------- 9. AppLauncher.kt ----------
cat > "$BASE/apps/AppLauncher.kt" <<'EOF'
package com.nova.ai.apps

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/** Opens an app by its package name. */
class AppLauncher(context: Context) {

    private val appContext: Context = context.applicationContext

    /** Opens the app. A failure result carries a Bangla message for the user. */
    fun launch(packageName: String): NovaResult<Unit> {
        return try {
            val intent: Intent = appContext.packageManager.getLaunchIntentForPackage(packageName)
                ?: return NovaResult.failure(ErrorCode.NOT_FOUND, "এই অ্যাপ ফোনে পাওয়া যায়নি।")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appContext.startActivity(intent)
            NovaLogger.i(TAG, "App launched")
            NovaResult.Success(Unit)
        } catch (e: ActivityNotFoundException) {
            NovaLogger.e(TAG, "No activity to launch", e)
            NovaResult.failure(ErrorCode.NOT_FOUND, "এই অ্যাপ খোলা যাচ্ছে না।", e)
        } catch (e: SecurityException) {
            NovaLogger.e(TAG, "Launch blocked", e)
            NovaResult.failure(ErrorCode.PERMISSION_DENIED, "ফোন এই অ্যাপ খুলতে দিচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Launch failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "অ্যাপ খুলতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "AppLauncher"
    }
}
EOF

# ---------- 10. AppRegistry.kt ----------
cat > "$BASE/apps/AppRegistry.kt" <<'EOF'
package com.nova.ai.apps

import android.content.Context
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.data.dao.AppDao
import com.nova.ai.data.db.NovaDatabase
import com.nova.ai.data.entity.AppEntity
import com.nova.ai.logging.NovaLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The user's app library: which apps NOVA may control, and their nicknames.
 * Saved only on this phone. Every call runs on a background thread and
 * reports problems as a failure result instead of crashing.
 */
class AppRegistry(context: Context) {

    private val dao: AppDao = NovaDatabase.getInstance(context).appDao()

    /** Every app in the library, sorted by name. */
    suspend fun getAll(): NovaResult<List<RegisteredApp>> = io("read apps") {
        dao.getAll().map { entity ->
            RegisteredApp(entity.packageName, entity.label, AliasCodec.decode(entity.aliases))
        }
    }

    /** Adds one app (and optional nicknames). An app already in the library stays as it is. */
    suspend fun add(app: InstalledApp, aliases: List<String> = emptyList()): NovaResult<Unit> =
        io("add app") {
            dao.insertIfAbsent(
                AppEntity(app.packageName, app.label, "", System.currentTimeMillis())
            )
            if (aliases.isNotEmpty()) mergeAliases(app.packageName, aliases)
            Unit
        }

    /** Adds many apps at once. Returns how many were new. */
    suspend fun addAll(apps: List<InstalledApp>): NovaResult<Int> = io("add apps") {
        val now: Long = System.currentTimeMillis()
        var added = 0
        for (app in apps) {
            val rowId: Long = dao.insertIfAbsent(AppEntity(app.packageName, app.label, "", now))
            if (rowId != INSERT_IGNORED) added += 1
        }
        added
    }

    /** Removes an app from the library. */
    suspend fun remove(packageName: String): NovaResult<Unit> = io("remove app") {
        dao.delete(packageName)
        Unit
    }

    /** Replaces all nicknames of an app. */
    suspend fun setAliases(packageName: String, aliases: List<String>): NovaResult<Unit> =
        io("save nicknames") {
            val entity: AppEntity? = dao.get(packageName)
            if (entity != null) {
                val clean: List<String> = AliasCodec.sanitize(aliases, entity.label)
                dao.updateAliases(packageName, AliasCodec.encode(clean))
            }
            Unit
        }

    /** Adds one nickname to an app, keeping the existing ones. */
    suspend fun addAlias(packageName: String, alias: String): NovaResult<Unit> =
        io("add nickname") {
            mergeAliases(packageName, listOf(alias))
            Unit
        }

    private fun mergeAliases(packageName: String, newAliases: List<String>) {
        val entity: AppEntity = dao.get(packageName) ?: return
        val merged: List<String> = AliasCodec.sanitize(
            AliasCodec.decode(entity.aliases) + newAliases,
            entity.label
        )
        dao.updateAliases(packageName, AliasCodec.encode(merged))
    }

    private suspend fun <T> io(action: String, block: () -> T): NovaResult<T> =
        withContext(Dispatchers.IO) {
            try {
                NovaResult.Success(block())
            } catch (e: Exception) {
                NovaLogger.e(TAG, "Failed to $action", e)
                NovaResult.failure(ErrorCode.EXECUTION_FAILED, "অ্যাপ তালিকা সংরক্ষণে সমস্যা হয়েছে।", e)
            }
        }

    private companion object {
        const val TAG: String = "AppRegistry"
        const val INSERT_IGNORED: Long = -1L
    }
}
EOF

# ---------- 11. AppLibraryController.kt ----------
cat > "$BASE/apps/AppLibraryController.kt" <<'EOF'
package com.nova.ai.apps

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.core.NovaResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Screen-side holder for the app library. Screens read [registered], [installed],
 * [isLoading] and [errorMessage]; the functions below change the library and reload.
 */
class AppLibraryController(
    context: Context,
    private val scope: CoroutineScope
) {

    private val registry = AppRegistry(context)
    private val scanner = InstalledAppScanner(context)

    var registered: List<RegisteredApp> by mutableStateOf<List<RegisteredApp>>(emptyList())
        private set

    var installed: List<InstalledApp> by mutableStateOf<List<InstalledApp>>(emptyList())
        private set

    var isLoading: Boolean by mutableStateOf(false)
        private set

    var errorMessage: String? by mutableStateOf<String?>(null)
        private set

    /** Reloads the library and the phone's app list. */
    fun refresh() {
        scope.launch {
            isLoading = true
            errorMessage = null
            load()
            isLoading = false
        }
    }

    /** Adds the chosen apps to the library. */
    fun addApps(apps: List<InstalledApp>) {
        if (apps.isEmpty()) return
        scope.launch {
            report(registry.addAll(apps))
            load()
        }
    }

    /** Removes an app from the library. */
    fun removeApp(packageName: String) {
        scope.launch {
            report(registry.remove(packageName))
            load()
        }
    }

    /** Saves the nicknames typed by the user. */
    fun saveAliases(packageName: String, rawAliases: List<String>) {
        scope.launch {
            report(registry.setAliases(packageName, rawAliases))
            load()
        }
    }

    private suspend fun load() {
        when (val result: NovaResult<List<RegisteredApp>> = registry.getAll()) {
            is NovaResult.Success -> registered = result.value
            is NovaResult.Failure -> errorMessage = result.error.message
        }
        when (val result: NovaResult<List<InstalledApp>> = scanner.scan()) {
            is NovaResult.Success -> installed = result.value
            is NovaResult.Failure -> errorMessage = result.error.message
        }
    }

    private fun report(result: NovaResult<*>) {
        if (result is NovaResult.Failure) errorMessage = result.error.message
    }
}
EOF

# ---------- 12. AppCommandController.kt ----------
cat > "$BASE/apps/AppCommandController.kt" <<'EOF'
package com.nova.ai.apps

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.nlp.IntentEntity
import com.nova.ai.voice.LanguageDetector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** What the Home screen shows about the last "open app" command. */
sealed class AppActionUi {
    object Idle : AppActionUi()
    data class Opened(val appLabel: String) : AppActionUi()
    data class Confirm(val spoken: String, val app: RegisteredApp) : AppActionUi()
    data class Choose(val spoken: String, val apps: List<RegisteredApp>) : AppActionUi()
    data class Suggest(val spoken: String, val apps: List<InstalledApp>) : AppActionUi()
    data class NotFound(val spoken: String) : AppActionUi()
    data class Failed(val message: String) : AppActionUi()
}

/**
 * Turns an "open app" command into a real app launch.
 * Only apps in the user's library are opened directly. Unsure names are
 * confirmed with the user, and the confirmed name is saved as a nickname.
 * Use from the main thread.
 */
class AppCommandController(
    context: Context,
    private val scope: CoroutineScope
) {

    private val registry = AppRegistry(context)
    private val scanner = InstalledAppScanner(context)
    private val launcher = AppLauncher(context)
    private val brain = RuleBasedBrain()

    var state: AppActionUi by mutableStateOf<AppActionUi>(AppActionUi.Idle)
        private set

    /** Looks at [text]; if it asks to open an app, finds and opens it. */
    fun handleCommand(text: String) {
        val spoken: String? = extractAppName(text)
        if (spoken == null) {
            state = AppActionUi.Idle
            return
        }
        resolveAndAct(spoken)
    }

    /** The user said "yes" to the suggested app. */
    fun confirm() {
        val current: AppActionUi.Confirm = state as? AppActionUi.Confirm ?: return
        learnAndOpen(current.spoken, current.app)
    }

    /** The user picked one app from a list. */
    fun choose(app: RegisteredApp) {
        val spoken: String = when (val current: AppActionUi = state) {
            is AppActionUi.Choose -> current.spoken
            is AppActionUi.Confirm -> current.spoken
            else -> return
        }
        learnAndOpen(spoken, app)
    }

    /** The user picked an installed app that was not in the library yet. */
    fun addAndOpen(app: InstalledApp) {
        val current: AppActionUi.Suggest = state as? AppActionUi.Suggest ?: return
        scope.launch {
            val added: NovaResult<Unit> = registry.add(app, listOf(current.spoken))
            if (added is NovaResult.Failure) {
                state = AppActionUi.Failed(added.error.message)
                return@launch
            }
            open(app.packageName, app.label)
        }
    }

    /** Hides the card. */
    fun dismiss() {
        state = AppActionUi.Idle
    }

    private fun extractAppName(text: String): String? {
        if (text.isBlank()) return null
        val command = VoiceCommand(
            rawText = text,
            language = LanguageDetector.detect(text),
            timestampMs = System.currentTimeMillis()
        )
        val intent: NovaIntent = (brain.analyze(command, emptyList()) as? NovaResult.Success)
            ?.value
            ?: return null
        if (intent.type != IntentType.OPEN_APP) return null
        return intent.entities[IntentEntity.APP]
    }

    private fun resolveAndAct(spoken: String) {
        scope.launch {
            val registeredApps: List<RegisteredApp> = when (val result = registry.getAll()) {
                is NovaResult.Success -> result.value
                is NovaResult.Failure -> {
                    state = AppActionUi.Failed(result.error.message)
                    return@launch
                }
            }
            val installedApps: List<InstalledApp> = when (val result = scanner.scan()) {
                is NovaResult.Success -> result.value
                is NovaResult.Failure -> {
                    state = AppActionUi.Failed(result.error.message)
                    return@launch
                }
            }

            // Only apps that are still on the phone can be opened.
            val installedPackages: Set<String> = installedApps.map { it.packageName }.toSet()
            val usable: List<RegisteredApp> =
                registeredApps.filter { it.packageName in installedPackages }

            when (val outcome: MatchOutcome = AppNameMatcher.match(spoken, usable)) {
                is MatchOutcome.Single -> open(outcome.app.packageName, outcome.app.label)
                is MatchOutcome.Confirm -> state = AppActionUi.Confirm(spoken, outcome.app)
                is MatchOutcome.Ambiguous -> state = AppActionUi.Choose(spoken, outcome.apps)
                is MatchOutcome.None -> suggestFromInstalled(spoken, installedApps, registeredApps)
            }
        }
    }

    /** Not in the library: look for it among the other apps on the phone. */
    private fun suggestFromInstalled(
        spoken: String,
        installedApps: List<InstalledApp>,
        registeredApps: List<RegisteredApp>
    ) {
        val registeredPackages: Set<String> = registeredApps.map { it.packageName }.toSet()
        val candidates: List<RegisteredApp> = installedApps
            .filter { it.packageName !in registeredPackages }
            .map { RegisteredApp(it.packageName, it.label) }

        val ranked: List<AppMatch> = AppNameMatcher.rank(spoken, candidates).take(MAX_SUGGESTIONS)
        state = if (ranked.isEmpty()) {
            AppActionUi.NotFound(spoken)
        } else {
            AppActionUi.Suggest(
                spoken,
                ranked.map { InstalledApp(it.app.packageName, it.app.label) }
            )
        }
    }

    private fun learnAndOpen(spoken: String, app: RegisteredApp) {
        scope.launch {
            val learned: NovaResult<Unit> = registry.addAlias(app.packageName, spoken)
            if (learned is NovaResult.Failure) {
                NovaLogger.w(TAG, "Could not save nickname: ${learned.error.message}")
            }
            open(app.packageName, app.label)
        }
    }

    private fun open(packageName: String, label: String) {
        state = when (val result: NovaResult<Unit> = launcher.launch(packageName)) {
            is NovaResult.Success -> AppActionUi.Opened(label)
            is NovaResult.Failure -> AppActionUi.Failed(result.error.message)
        }
    }

    private companion object {
        const val TAG: String = "AppCommandController"
        const val MAX_SUGGESTIONS: Int = 3
    }
}
EOF

# ---------- 13. AppIcon.kt ----------
cat > "$BASE/ui/components/AppIcon.kt" <<'EOF'
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
EOF

# ---------- 14. AppDialogs.kt ----------
cat > "$BASE/ui/components/AppDialogs.kt" <<'EOF'
package com.nova.ai.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.apps.AliasCodec
import com.nova.ai.apps.InstalledApp
import com.nova.ai.apps.RegisteredApp

private val PICKER_LIST_MAX_HEIGHT: Dp = 360.dp

/**
 * Lets the user tick the apps NOVA may control.
 * Apps already in the library are shown ticked and cannot be changed here.
 */
@Composable
fun AppPickerDialog(
    installed: List<InstalledApp>,
    registeredPackages: Set<String>,
    onConfirm: (List<InstalledApp>) -> Unit,
    onDismiss: () -> Unit
) {
    var query: String by rememberSaveable { mutableStateOf("") }
    val selected = remember { mutableStateListOf<String>() }

    val filtered: List<InstalledApp> = remember(installed, query) {
        val needle: String = query.trim()
        if (needle.isEmpty()) {
            installed
        } else {
            installed.filter { it.label.contains(needle, ignoreCase = true) }
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.picker_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    label = { Text(stringResource(R.string.picker_search)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                if (filtered.isEmpty()) {
                    Text(
                        text = stringResource(R.string.picker_empty),
                        style = MaterialTheme.typography.bodySmall
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = PICKER_LIST_MAX_HEIGHT)
                    ) {
                        items(filtered, key = { it.packageName }) { app ->
                            val alreadyAdded: Boolean = app.packageName in registeredPackages
                            val isChecked: Boolean = alreadyAdded || app.packageName in selected
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable(enabled = !alreadyAdded) {
                                        if (app.packageName in selected) {
                                            selected.remove(app.packageName)
                                        } else {
                                            selected.add(app.packageName)
                                        }
                                    }
                                    .padding(vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                AppIcon(packageName = app.packageName, size = 36.dp)
                                Spacer(modifier = Modifier.width(12.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = app.label,
                                        style = MaterialTheme.typography.bodyMedium
                                    )
                                    if (alreadyAdded) {
                                        Text(
                                            text = stringResource(R.string.picker_already),
                                            style = MaterialTheme.typography.bodySmall
                                        )
                                    }
                                }
                                Checkbox(
                                    checked = isChecked,
                                    onCheckedChange = null,
                                    enabled = !alreadyAdded
                                )
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = { onConfirm(installed.filter { it.packageName in selected }) },
                enabled = selected.isNotEmpty()
            ) {
                Text(stringResource(R.string.picker_confirm, selected.size))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.picker_cancel))
            }
        }
    )
}

/** Lets the user type nicknames for one app, separated by commas. */
@Composable
fun AliasEditDialog(
    app: RegisteredApp,
    onSave: (List<String>) -> Unit,
    onDismiss: () -> Unit
) {
    var text: String by remember(app.packageName) {
        mutableStateOf(app.aliases.joinToString(", "))
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.alias_title, app.label)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = stringResource(R.string.alias_help),
                    style = MaterialTheme.typography.bodySmall
                )
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    label = { Text(stringResource(R.string.alias_hint)) },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            Button(onClick = { onSave(AliasCodec.parseInput(text)) }) {
                Text(stringResource(R.string.alias_save))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.picker_cancel))
            }
        }
    )
}
EOF

# ---------- 15. AppLibrarySection.kt ----------
cat > "$BASE/ui/components/AppLibrarySection.kt" <<'EOF'
package com.nova.ai.ui.components

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.apps.AppLibraryController
import com.nova.ai.apps.RegisteredApp
import kotlinx.coroutines.CoroutineScope

/**
 * "NOVA's apps": the list of apps NOVA may control. The user adds apps from the
 * phone's app list, gives them nicknames, and removes them. Shown in the Access tab.
 */
@Composable
fun AppLibrarySection(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val scope: CoroutineScope = rememberCoroutineScope()
    val controller: AppLibraryController = remember { AppLibraryController(context, scope) }

    var showPicker: Boolean by remember { mutableStateOf(false) }
    var editingApp: RegisteredApp? by remember { mutableStateOf<RegisteredApp?>(null) }

    LaunchedEffect(controller) { controller.refresh() }

    val installedPackages: Set<String> =
        remember(controller.installed) { controller.installed.map { it.packageName }.toSet() }
    val registeredPackages: Set<String> =
        remember(controller.registered) { controller.registered.map { it.packageName }.toSet() }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.apps_title),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = stringResource(R.string.apps_note),
            style = MaterialTheme.typography.bodySmall
        )

        val error: String? = controller.errorMessage
        if (error != null) {
            Text(
                text = stringResource(R.string.apps_error, error),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error
            )
        }

        Text(
            text = stringResource(R.string.apps_count, controller.registered.size),
            style = MaterialTheme.typography.bodyMedium
        )
        Button(
            onClick = { showPicker = true },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(stringResource(R.string.apps_add_button))
        }

        if (controller.registered.isEmpty() && !controller.isLoading) {
            NovaInfoCard(
                title = stringResource(R.string.apps_title),
                body = stringResource(R.string.apps_empty)
            )
        }

        controller.registered.forEach { app ->
            key(app.packageName) {
                RegisteredAppCard(
                    app = app,
                    missing = installedPackages.isNotEmpty() && app.packageName !in installedPackages,
                    onEdit = { editingApp = app },
                    onRemove = { controller.removeApp(app.packageName) }
                )
            }
        }
    }

    if (showPicker) {
        AppPickerDialog(
            installed = controller.installed,
            registeredPackages = registeredPackages,
            onConfirm = { chosen ->
                controller.addApps(chosen)
                showPicker = false
            },
            onDismiss = { showPicker = false }
        )
    }

    editingApp?.let { app ->
        AliasEditDialog(
            app = app,
            onSave = { aliases ->
                controller.saveAliases(app.packageName, aliases)
                editingApp = null
            },
            onDismiss = { editingApp = null }
        )
    }
}

@Composable
private fun RegisteredAppCard(
    app: RegisteredApp,
    missing: Boolean,
    onEdit: () -> Unit,
    onRemove: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AppIcon(packageName = app.packageName, size = 40.dp)
                Spacer(modifier = Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(text = app.label, style = MaterialTheme.typography.titleMedium)
                    Text(
                        text = if (app.aliases.isEmpty()) {
                            stringResource(R.string.apps_alias_none)
                        } else {
                            stringResource(R.string.apps_alias_label, app.aliases.joinToString(", "))
                        },
                        style = MaterialTheme.typography.bodySmall
                    )
                    if (missing) {
                        Text(
                            text = stringResource(R.string.apps_not_installed),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onEdit, modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.apps_edit))
                }
                OutlinedButton(onClick = onRemove, modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.apps_remove))
                }
            }
        }
    }
}
EOF

# ---------- 16. AppActionCard.kt ----------
cat > "$BASE/ui/components/AppActionCard.kt" <<'EOF'
package com.nova.ai.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.apps.AppActionUi
import com.nova.ai.apps.AppCommandController

/**
 * Shows the result of an "open app" command on the Home screen: opened,
 * a question to confirm or choose, an offer to add an app, or a problem.
 * Shows nothing while there is nothing to report.
 */
@Composable
fun AppActionCard(
    controller: AppCommandController,
    modifier: Modifier = Modifier
) {
    val current: AppActionUi = controller.state
    if (current is AppActionUi.Idle) return

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.action_title),
                style = MaterialTheme.typography.titleMedium
            )

            when (current) {
                is AppActionUi.Idle -> Unit

                is AppActionUi.Opened -> {
                    Text(stringResource(R.string.action_opened, current.appLabel))
                }

                is AppActionUi.Confirm -> {
                    Text(stringResource(R.string.action_confirm, current.spoken, current.app.label))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = { controller.confirm() },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(stringResource(R.string.action_confirm_yes))
                        }
                        OutlinedButton(
                            onClick = { controller.dismiss() },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(stringResource(R.string.action_confirm_no))
                        }
                    }
                }

                is AppActionUi.Choose -> {
                    Text(stringResource(R.string.action_choose, current.spoken))
                    current.apps.forEach { app ->
                        Button(
                            onClick = { controller.choose(app) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(app.label)
                        }
                    }
                }

                is AppActionUi.Suggest -> {
                    Text(stringResource(R.string.action_suggest, current.spoken))
                    current.apps.forEach { app ->
                        Button(
                            onClick = { controller.addAndOpen(app) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(stringResource(R.string.action_suggest_button, app.label))
                        }
                    }
                }

                is AppActionUi.NotFound -> {
                    Text(stringResource(R.string.action_not_found, current.spoken))
                }

                is AppActionUi.Failed -> {
                    Text(stringResource(R.string.action_failed, current.message))
                }
            }

            if (current !is AppActionUi.Confirm) {
                TextButton(onClick = { controller.dismiss() }) {
                    Text(stringResource(R.string.action_dismiss))
                }
            }
        }
    }
}
EOF

# ---------- 17. PermissionsScreen.kt (3 original cards kept + app library added) ----------
cat > "$BASE/ui/screens/PermissionsScreen.kt" <<'EOF'
package com.nova.ai.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.ui.components.AppLibrarySection
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout

/** Permissions: explains why each permission is needed, and manages NOVA's app list. */
@Composable
fun PermissionsScreen(modifier: Modifier = Modifier) {
    val pending: String = stringResource(R.string.perm_status_pending)

    NovaScreenLayout(
        title = stringResource(R.string.permissions_title),
        subtitle = stringResource(R.string.permissions_subtitle),
        modifier = modifier
    ) {
        NovaInfoCard(
            title = stringResource(R.string.perm_accessibility_title),
            body = stringResource(R.string.perm_accessibility_body) + "\n" + pending
        )
        NovaInfoCard(
            title = stringResource(R.string.perm_microphone_title),
            body = stringResource(R.string.perm_microphone_body) + "\n" + pending
        )
        NovaInfoCard(
            title = stringResource(R.string.perm_notification_title),
            body = stringResource(R.string.perm_notification_body) + "\n" + pending
        )

        AppLibrarySection()
    }
}
EOF

# ---------- 18. OnboardingScreen.kt (3 original steps kept + app step added) ----------
cat > "$BASE/ui/screens/OnboardingScreen.kt" <<'EOF'
package com.nova.ai.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nova.ai.R
import com.nova.ai.apps.AppLibraryController
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.ThemeMode
import com.nova.ai.ui.components.AppPickerDialog
import com.nova.ai.ui.components.NovaChoiceGroup
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.languageLabel
import com.nova.ai.ui.components.themeModeLabel
import kotlinx.coroutines.CoroutineScope

private const val TOTAL_STEPS: Int = 4

/**
 * First-run guide: welcome, feature overview, language and theme choice,
 * then choosing the apps NOVA may control.
 * Calls [onFinished] with the chosen settings when the user taps Start.
 */
@Composable
fun OnboardingScreen(
    onFinished: (AppLanguage, ThemeMode) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val scope: CoroutineScope = rememberCoroutineScope()
    val library: AppLibraryController = remember { AppLibraryController(context, scope) }
    LaunchedEffect(library) { library.refresh() }

    var step: Int by rememberSaveable { mutableStateOf(0) }
    var language: AppLanguage by rememberSaveable { mutableStateOf(AppLanguage.BANGLA) }
    var theme: ThemeMode by rememberSaveable { mutableStateOf(ThemeMode.SYSTEM) }
    var showPicker: Boolean by rememberSaveable { mutableStateOf(false) }
    val lastStep: Int = TOTAL_STEPS - 1

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp)
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = stringResource(R.string.onboarding_step_format, step + 1, TOTAL_STEPS),
                style = MaterialTheme.typography.bodySmall
            )
            when (step) {
                0 -> WelcomeStep()
                1 -> FeaturesStep()
                2 -> PreferencesStep(
                    language = language,
                    theme = theme,
                    onLanguageChange = { language = it },
                    onThemeChange = { theme = it }
                )
                else -> AppsStep(
                    selectedCount = library.registered.size,
                    onPickApps = { showPicker = true }
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (step > 0) {
                OutlinedButton(
                    onClick = { step -= 1 },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.onboarding_back))
                }
            }
            Button(
                onClick = {
                    if (step < lastStep) step += 1 else onFinished(language, theme)
                },
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    stringResource(
                        if (step < lastStep) R.string.onboarding_next else R.string.onboarding_start
                    )
                )
            }
        }
    }

    if (showPicker) {
        AppPickerDialog(
            installed = library.installed,
            registeredPackages = library.registered.map { it.packageName }.toSet(),
            onConfirm = { chosen ->
                library.addApps(chosen)
                showPicker = false
            },
            onDismiss = { showPicker = false }
        )
    }
}

@Composable
private fun WelcomeStep() {
    Text(text = stringResource(R.string.onboarding_welcome_emoji), fontSize = 64.sp)
    Text(
        text = stringResource(R.string.onboarding_welcome_title),
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold
    )
    Text(
        text = stringResource(R.string.onboarding_welcome_body),
        style = MaterialTheme.typography.bodyMedium
    )
}

@Composable
private fun FeaturesStep() {
    Text(
        text = stringResource(R.string.onboarding_features_title),
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold
    )
    NovaInfoCard(
        title = stringResource(R.string.onboarding_feature_voice_title),
        body = stringResource(R.string.onboarding_feature_voice_body)
    )
    NovaInfoCard(
        title = stringResource(R.string.onboarding_feature_apps_title),
        body = stringResource(R.string.onboarding_feature_apps_body)
    )
    NovaInfoCard(
        title = stringResource(R.string.onboarding_feature_privacy_title),
        body = stringResource(R.string.onboarding_feature_privacy_body)
    )
}

@Composable
private fun PreferencesStep(
    language: AppLanguage,
    theme: ThemeMode,
    onLanguageChange: (AppLanguage) -> Unit,
    onThemeChange: (ThemeMode) -> Unit
) {
    Text(
        text = stringResource(R.string.onboarding_prefs_title),
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold
    )
    NovaChoiceGroup(
        title = stringResource(R.string.settings_language_title),
        options = AppLanguage.values().toList(),
        selected = language,
        labelOf = { languageLabel(it) },
        onSelected = onLanguageChange
    )
    NovaChoiceGroup(
        title = stringResource(R.string.settings_theme_title),
        options = ThemeMode.values().toList(),
        selected = theme,
        labelOf = { themeModeLabel(it) },
        onSelected = onThemeChange
    )
    Text(
        text = stringResource(R.string.onboarding_prefs_note),
        style = MaterialTheme.typography.bodySmall
    )
}

@Composable
private fun AppsStep(
    selectedCount: Int,
    onPickApps: () -> Unit
) {
    Text(
        text = stringResource(R.string.onboarding_apps_title),
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold
    )
    Text(
        text = stringResource(R.string.onboarding_apps_body),
        style = MaterialTheme.typography.bodyMedium
    )
    Button(
        onClick = onPickApps,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(stringResource(R.string.onboarding_apps_button))
    }
    Text(
        text = stringResource(R.string.onboarding_apps_selected, selectedCount),
        style = MaterialTheme.typography.titleMedium
    )
    Text(
        text = stringResource(R.string.onboarding_apps_skip_note),
        style = MaterialTheme.typography.bodySmall
    )
}
EOF

# ---------- 19. HomeScreen.kt (all previous elements kept; opening apps added) ----------
cat > "$BASE/ui/screens/HomeScreen.kt" <<'EOF'
package com.nova.ai.ui.screens

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.nova.ai.R
import com.nova.ai.apps.AppCommandController
import com.nova.ai.core.Language
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.SpeechSpeed
import com.nova.ai.ui.components.AppActionCard
import com.nova.ai.ui.components.CommandInsightCard
import com.nova.ai.ui.components.IntentInsightCard
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout
import com.nova.ai.ui.theme.LocalAppSettings
import com.nova.ai.voice.AndroidVoiceEngine
import com.nova.ai.voice.ConversationController
import com.nova.ai.voice.ConversationEnd
import com.nova.ai.voice.ConversationListener
import com.nova.ai.voice.ConversationState
import com.nova.ai.voice.SpokenReply
import com.nova.ai.voice.toSpeechLanguage
import kotlinx.coroutines.CoroutineScope

private const val TAG: String = "HomeScreen"
private const val TRANSCRIPT_LIMIT: Int = 5

/**
 * Home: voice button, command box, current status and running-task progress.
 * The mic button starts a conversation: the app listens, confirms by voice,
 * and (when continuous mode is on) listens again by itself until the user says
 * stop, stays silent, or leaves the screen. Commands that ask to open an app
 * are carried out using the user's app library.
 */
@Composable
fun HomeScreen(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val scope: CoroutineScope = rememberCoroutineScope()
    val settings = LocalAppSettings.current
    val currentLanguage: AppLanguage by rememberUpdatedState(settings.language)
    val currentSpeed: SpeechSpeed by rememberUpdatedState(settings.speechSpeed)
    val replyEnabled: Boolean by rememberUpdatedState(settings.voiceReplyEnabled)
    val continuousEnabled: Boolean by rememberUpdatedState(settings.continuousConversation)

    var commandText: String by rememberSaveable { mutableStateOf("") }
    var statusOverride: String by rememberSaveable { mutableStateOf("") }
    var conversationState: ConversationState by remember {
        mutableStateOf(ConversationState.IDLE)
    }
    var commandCount: Int by remember { mutableStateOf(0) }
    val transcript = remember { mutableStateListOf<String>() }

    val readyText: String = stringResource(R.string.home_status_ready)
    val idleText: String = stringResource(R.string.home_status_ready_voice)
    val receivedText: String = stringResource(R.string.home_status_command_received)
    val emptyText: String = stringResource(R.string.home_status_empty_command)
    val voiceDescription: String = stringResource(R.string.home_voice_button_desc)
    val stopDescription: String = stringResource(R.string.home_voice_stop_desc)

    // One voice engine per Home screen; released when the screen leaves.
    val voiceEngine: AndroidVoiceEngine = remember {
        AndroidVoiceEngine(
            context = context,
            languageProvider = { currentLanguage },
            speechRateProvider = { currentSpeed.rate }
        )
    }

    // Opens apps from commands, using the user's app library.
    val appController: AppCommandController = remember { AppCommandController(context, scope) }

    // Conversation events arrive on the main thread, so updating UI state here is safe.
    val conversation: ConversationController = remember {
        ConversationController(
            engine = voiceEngine,
            listener = object : ConversationListener {
                override fun onStateChanged(state: ConversationState) {
                    conversationState = state
                    when (state) {
                        ConversationState.LISTENING ->
                            statusOverride = listeningStatus(context, commandCount)
                        ConversationState.SPEAKING ->
                            statusOverride = context.getString(R.string.home_status_speaking)
                        ConversationState.WAITING ->
                            statusOverride = context.getString(R.string.home_status_next_turn)
                        ConversationState.IDLE -> Unit
                    }
                }

                override fun onPartialText(text: String) {
                    commandText = text
                }

                override fun onCommand(command: VoiceCommand) {
                    commandCount += 1
                    commandText = command.rawText
                    statusOverride = context.getString(R.string.home_status_heard, command.rawText)
                    transcript.add("$commandCount. ${command.rawText}")
                    while (transcript.size > TRANSCRIPT_LIMIT) transcript.removeAt(0)
                    appController.handleCommand(command.rawText)
                }

                override fun onEnded(reason: ConversationEnd) {
                    when (reason) {
                        is ConversationEnd.UserStopped ->
                            statusOverride = context.getString(R.string.home_status_ended_user)
                        is ConversationEnd.StopPhrase -> {
                            statusOverride = context.getString(R.string.home_status_ended_phrase)
                            if (replyEnabled) {
                                val english: Boolean = currentLanguage == AppLanguage.ENGLISH
                                val ackRes: Int = if (english) {
                                    R.string.home_voice_stop_ack_en
                                } else {
                                    R.string.home_voice_stop_ack
                                }
                                voiceEngine.speak(
                                    context.getString(ackRes),
                                    currentLanguage.toSpeechLanguage()
                                )
                            }
                        }
                        is ConversationEnd.SilenceTimeout ->
                            statusOverride = context.getString(R.string.home_status_ended_silence)
                        is ConversationEnd.SingleCompleted ->
                            statusOverride =
                                context.getString(R.string.home_status_heard, commandText)
                        is ConversationEnd.Failed ->
                            statusOverride = context.getString(
                                R.string.home_voice_error,
                                reason.error.message
                            )
                    }
                }
            },
            continuousProvider = { continuousEnabled },
            replyProvider = { command ->
                if (replyEnabled) buildReply(context, command, currentLanguage) else null
            }
        )
    }

    // Release everything when the screen leaves, and close the microphone
    // whenever the app goes to the background.
    val lifecycleOwner: LifecycleOwner? = context as? LifecycleOwner
    DisposableEffect(lifecycleOwner, conversation) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) conversation.stop()
        }
        lifecycleOwner?.lifecycle?.addObserver(observer)
        onDispose {
            lifecycleOwner?.lifecycle?.removeObserver(observer)
            conversation.shutdown()
            voiceEngine.shutdown()
        }
    }

    fun startConversation() {
        commandCount = 0
        transcript.clear()
        when (val result: NovaResult<Unit> = conversation.start()) {
            is NovaResult.Success -> Unit
            is NovaResult.Failure -> {
                statusOverride = context.getString(R.string.home_voice_error, result.error.message)
                NovaLogger.w(TAG, "Conversation start failed: ${result.error.message}")
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted: Boolean ->
        if (granted) {
            startConversation()
        } else {
            statusOverride = context.getString(R.string.home_mic_permission_denied)
        }
    }

    val sessionActive: Boolean = conversationState != ConversationState.IDLE
    val currentStatus: String =
        if (statusOverride.isEmpty()) "$readyText\n$idleText" else statusOverride

    NovaScreenLayout(
        title = stringResource(R.string.home_title),
        subtitle = stringResource(R.string.home_subtitle),
        modifier = modifier
    ) {
        Box(
            modifier = Modifier.fillMaxWidth(),
            contentAlignment = Alignment.Center
        ) {
            val buttonDescription: String = if (sessionActive) stopDescription else voiceDescription
            Button(
                onClick = {
                    if (sessionActive) {
                        conversation.stop()
                    } else {
                        val micGranted: Boolean = ContextCompat.checkSelfPermission(
                            context, Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                        if (micGranted) {
                            startConversation()
                        } else {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    }
                },
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (sessionActive) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.primary
                    }
                ),
                modifier = Modifier
                    .size(120.dp)
                    .semantics { contentDescription = buttonDescription }
            ) {
                Text(text = if (sessionActive) "⏹️" else "🎙️", fontSize = 40.sp)
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = stringResource(R.string.home_continuous_label),
                style = MaterialTheme.typography.titleMedium
            )
            Switch(
                checked = settings.continuousConversation,
                onCheckedChange = settings.onContinuousChange
            )
        }
        Text(
            text = stringResource(R.string.home_continuous_hint),
            style = MaterialTheme.typography.bodySmall
        )

        NovaInfoCard(
            title = stringResource(R.string.home_status_label),
            body = currentStatus
        )

        OutlinedTextField(
            value = commandText,
            onValueChange = { commandText = it },
            label = { Text(stringResource(R.string.home_command_hint)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )

        Button(
            onClick = {
                if (commandText.isBlank()) {
                    statusOverride = emptyText
                } else {
                    statusOverride = receivedText
                    appController.handleCommand(commandText)
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(stringResource(R.string.home_send))
        }

        AppActionCard(controller = appController)

        CommandInsightCard(text = commandText)

        IntentInsightCard(text = commandText, history = transcript.toList())

        if (transcript.isNotEmpty()) {
            NovaInfoCard(
                title = stringResource(R.string.home_transcript_title),
                body = transcript.joinToString("\n")
            )
        }

        NovaInfoCard(
            title = stringResource(R.string.home_progress_title),
            body = stringResource(R.string.home_progress_none)
        )
    }
}

/** Status line while listening; shows how many commands this conversation has had. */
private fun listeningStatus(context: Context, count: Int): String =
    if (count == 0) {
        context.getString(R.string.home_status_listening)
    } else {
        context.getString(R.string.home_status_listening_count, count)
    }

/** Builds the spoken confirmation for [command] in the language it was spoken in. */
private fun buildReply(context: Context, command: VoiceCommand, fallback: AppLanguage): SpokenReply {
    val english: Boolean = command.language == Language.ENGLISH
    val replyRes: Int = if (english) R.string.home_voice_ack_en else R.string.home_voice_ack
    val spoken: Language = if (command.language == Language.UNKNOWN) {
        fallback.toSpeechLanguage()
    } else {
        command.language
    }
    return SpokenReply(context.getString(replyRes, command.rawText), spoken)
}
EOF

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "P12: app library (user-chosen apps and nicknames) and opening apps"
git push

echo "P12 files created and pushed."
