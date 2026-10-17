#!/usr/bin/env bash
# NOVA AI - Phase 14 setup script: calls and SMS by name or number, mobile data screen.
# Additive: new contacts package; small additive lines in a few existing files.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
MANIFEST="app/src/main/AndroidManifest.xml"
HOME_FILE="$BASE/ui/screens/HomeScreen.kt"
PARSER_FILE="$BASE/nlp/IntentParser.kt"
ENTITY_FILE="$BASE/nlp/IntentEntity.kt"
VOCAB_FILE="$BASE/nlp/IntentVocabulary.kt"
EXECUTOR_FILE="$BASE/system/SystemActionExecutor.kt"
INSIGHT_FILE="$BASE/ui/components/IntentInsightCard.kt"

for required in \
  "$BASE/system/SystemCommandController.kt" \
  "$HOME_FILE" "$PARSER_FILE" "$ENTITY_FILE" "$VOCAB_FILE" \
  "$EXECUTOR_FILE" "$INSIGHT_FILE" "$MANIFEST"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after P1 to P13 are installed." >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
mkdir -p "$BASE/contacts"

# ---------- A. Manifest: contacts and call permissions ----------
if ! grep -q "android.permission.READ_CONTACTS" "$MANIFEST"; then
  cat > "$TMP_DIR/manifest_add.txt" <<'EOF'
    <uses-permission android:name="android.permission.READ_CONTACTS" />
    <uses-permission android:name="android.permission.CALL_PHONE" />
    <uses-feature android:name="android.hardware.telephony" android:required="false" />
EOF
  sed -i "/android.permission.RECORD_AUDIO/r $TMP_DIR/manifest_add.txt" "$MANIFEST"
fi
grep -q "android.permission.READ_CONTACTS" "$MANIFEST" || { echo "ERROR: manifest edit failed (contacts)" >&2; exit 1; }
grep -q "android.permission.CALL_PHONE" "$MANIFEST" || { echo "ERROR: manifest edit failed (call)" >&2; exit 1; }

# ---------- B. Mobile data target in the command parser (additive) ----------
if ! grep -q "MOBILE_DATA" "$ENTITY_FILE"; then
  grep -q 'const val BRIGHTNESS: String = "brightness"' "$ENTITY_FILE" \
    || { echo "ERROR: IntentEntity anchor not found" >&2; exit 1; }
  cat > "$TMP_DIR/entity_add.txt" <<'EOF'
    const val MOBILE_DATA: String = "mobile_data"
EOF
  sed -i "/const val BRIGHTNESS: String = \"brightness\"/r $TMP_DIR/entity_add.txt" "$ENTITY_FILE"
fi
grep -q "MOBILE_DATA" "$ENTITY_FILE" || { echo "ERROR: IntentEntity edit failed" >&2; exit 1; }

if ! grep -q "MOBILE_DATA" "$VOCAB_FILE"; then
  grep -q 'SystemTarget.BRIGHTNESS to listOf(' "$VOCAB_FILE" \
    || { echo "ERROR: IntentVocabulary anchor not found" >&2; exit 1; }
  sed -i 's|^\( *SystemTarget\.BRIGHTNESS to listOf(.*)\)$|\1,\n        SystemTarget.MOBILE_DATA to listOf("mobile data", "মোবাইল ডেটা", "ডেটা", "ডাটা", "data")|' "$VOCAB_FILE"
fi
grep -q "MOBILE_DATA" "$VOCAB_FILE" || { echo "ERROR: IntentVocabulary edit failed" >&2; exit 1; }

# ---------- C. Parser: "ফোন খোলো" opens the phone app, it is not a call ----------
if ! grep -q "nova-open-phone-guard" "$PARSER_FILE"; then
  grep -q 'if (!v.hasAny(IntentVocabulary.CALL_WORDS)) return null' "$PARSER_FILE" \
    || { echo "ERROR: IntentParser anchor not found" >&2; exit 1; }
  cat > "$TMP_DIR/parser_add.txt" <<'EOF'
        // nova-open-phone-guard: an "open" word without a number means opening the phone app.
        if (v.hasAny(IntentVocabulary.OPEN_VERBS_STRONG) && findPhoneNumber(v) == null) return null
EOF
  sed -i "/if (!v.hasAny(IntentVocabulary.CALL_WORDS)) return null/r $TMP_DIR/parser_add.txt" "$PARSER_FILE"
fi
grep -q "nova-open-phone-guard" "$PARSER_FILE" || { echo "ERROR: IntentParser edit failed" >&2; exit 1; }

# ---------- D. Intent card: readable name for the mobile data target ----------
if ! grep -q "intent_value_mobile_data" "$INSIGHT_FILE"; then
  grep -q 'SystemTarget.BRIGHTNESS -> R.string.intent_value_brightness' "$INSIGHT_FILE" \
    || { echo "ERROR: IntentInsightCard anchor not found" >&2; exit 1; }
  cat > "$TMP_DIR/insight_add.txt" <<'EOF'
            SystemTarget.MOBILE_DATA -> R.string.intent_value_mobile_data
EOF
  sed -i "/SystemTarget.BRIGHTNESS -> R.string.intent_value_brightness/r $TMP_DIR/insight_add.txt" "$INSIGHT_FILE"
fi
grep -q "intent_value_mobile_data" "$INSIGHT_FILE" || { echo "ERROR: IntentInsightCard edit failed" >&2; exit 1; }

# ---------- E. System executor: mobile data branch (additive) ----------
if ! grep -q "mobileData(action)" "$EXECUTOR_FILE"; then
  grep -q 'SystemTarget.BLUETOOTH -> bluetooth(action)' "$EXECUTOR_FILE" \
    || { echo "ERROR: SystemActionExecutor anchor (branch) not found" >&2; exit 1; }
  grep -q 'private fun done(message: String) = SystemActionOutcome(OutcomeKind.DONE, message)' "$EXECUTOR_FILE" \
    || { echo "ERROR: SystemActionExecutor anchor (function) not found" >&2; exit 1; }

  cat > "$TMP_DIR/exec_branch.txt" <<'EOF'
                SystemTarget.MOBILE_DATA -> mobileData(action)
EOF
  cat > "$TMP_DIR/exec_function.txt" <<'EOF'

    private fun mobileData(action: String?): SystemActionOutcome =
        when (val result: NovaResult<Unit> = settingsOpener.openMobileData()) {
            is NovaResult.Success ->
                if (action == IntentAction.ON || action == IntentAction.OFF) {
                    SystemActionOutcome(OutcomeKind.GUIDED, text(R.string.sys_data_guided))
                } else {
                    done(text(R.string.sys_data_settings))
                }
            is NovaResult.Failure -> failed(result.error.message)
        }
EOF
  sed -i "/SystemTarget.BLUETOOTH -> bluetooth(action)/r $TMP_DIR/exec_branch.txt" "$EXECUTOR_FILE"
  sed -i "/private fun done(message: String) = SystemActionOutcome(OutcomeKind.DONE, message)/r $TMP_DIR/exec_function.txt" "$EXECUTOR_FILE"
fi
grep -q "SystemTarget.MOBILE_DATA -> mobileData(action)" "$EXECUTOR_FILE" || { echo "ERROR: SystemActionExecutor edit failed (branch)" >&2; exit 1; }
grep -q "private fun mobileData" "$EXECUTOR_FILE" || { echo "ERROR: SystemActionExecutor edit failed (function)" >&2; exit 1; }

# ---------- F. New strings file ----------
cat > app/src/main/res/values/strings_p14.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="intent_value_mobile_data">মোবাইল ডেটা</string>
    <string name="sys_data_guided">মোবাইল ডেটার প্যানেল খুলেছি। Android নিয়ম অনুযায়ী অ্যাপ নিজে ডেটা চালু বা বন্ধ করতে পারে না, তাই সুইচটি তুমি চাপো।</string>
    <string name="sys_data_settings">মোবাইল ডেটার সেটিংস খুলেছি।</string>

    <string name="contact_title">কল ও মেসেজ</string>
    <string name="contact_permission_needed">নাম দিয়ে কল বা মেসেজ করতে কন্টাক্ট পড়ার অনুমতি লাগে। নম্বর বলে কল করতে এই অনুমতি লাগে না।</string>
    <string name="contact_permission_button">কন্টাক্টের অনুমতি দাও</string>
    <string name="contact_permission_denied">কন্টাক্টের অনুমতি ছাড়া নাম দিয়ে খোঁজা যাবে না। নম্বর বলে চেষ্টা করো।</string>
    <string name="contact_not_found">\"%1$s\" নামে কোনো কন্টাক্ট পেলাম না। নামটি অন্যভাবে বলো বা নম্বর বলো।</string>
    <string name="contact_choose">\"%1$s\": কোন কন্টাক্ট?</string>
    <string name="contact_choose_number">%1$s: কোন নম্বর?</string>
    <string name="contact_confirm_call">কল করব: %1$s (%2$s)?</string>
    <string name="contact_confirm_call_number">কল করব: %1$s?</string>
    <string name="contact_call_button">কল করো</string>
    <string name="contact_dial_button">ডায়ালারে খোলো</string>
    <string name="contact_cancel">বাতিল</string>
    <string name="contact_call_started">কল শুরু হচ্ছে।</string>
    <string name="contact_dialer_opened">ডায়ালার খুলেছি। কল করার বাটন তুমি চাপো।</string>
    <string name="contact_call_denied">কল করার অনুমতি দাওনি, তাই ডায়ালার খুলেছি। কল করার বাটন তুমি চাপো।</string>
    <string name="contact_sms_opened">%1$s-কে মেসেজ লেখার স্ক্রিন খুলেছি। বার্তা দেখে নিয়ে পাঠানোর বাটন তুমি চাপো।</string>
    <string name="contact_who_call">কাকে কল করব? যেমন: সুমনকে কল করো।</string>
    <string name="contact_who_sms">কাকে মেসেজ পাঠাব? যেমন: সুমনকে মেসেজ পাঠাও আমি আসছি।</string>
    <string name="contact_app_later">অ্যাপের মাধ্যমে (WhatsApp, Messenger ইত্যাদি) কল বা মেসেজ পরের ফেজে আসছে। এখন অ্যাপের নাম ছাড়া বলো, যেমন: সুমনকে মেসেজ পাঠাও।</string>
    <string name="contact_failed">সমস্যা: %1$s</string>
</resources>
EOF

# ---------- 1. SystemSettingsOpener.kt (P13 content kept; mobile data added) ----------
cat > "$BASE/system/SystemSettingsOpener.kt" <<'EOF'
package com.nova.ai.system

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * Opens the phone's Wi-Fi, Bluetooth and mobile data screens. Android does not
 * let ordinary apps switch these on or off, so the user taps the final switch.
 */
class SystemSettingsOpener(context: Context) {

    private val appContext: Context = context.applicationContext

    /** Opens the quick Wi-Fi panel (Android 10 and newer) or the Wi-Fi settings page. */
    fun openWifi(): NovaResult<Unit> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val panel: NovaResult<Unit> = start(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
            if (panel is NovaResult.Success) return panel
        }
        return start(Settings.ACTION_WIFI_SETTINGS)
    }

    /** Opens the Bluetooth settings page. */
    fun openBluetooth(): NovaResult<Unit> = start(Settings.ACTION_BLUETOOTH_SETTINGS)

    /** Opens the internet panel (Android 10 and newer) or the mobile network settings page. */
    fun openMobileData(): NovaResult<Unit> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val panel: NovaResult<Unit> = start(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
            if (panel is NovaResult.Success) return panel
        }
        return start(Settings.ACTION_DATA_ROAMING_SETTINGS)
    }

    private fun start(action: String): NovaResult<Unit> {
        return try {
            appContext.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            NovaResult.Success(Unit)
        } catch (e: ActivityNotFoundException) {
            NovaLogger.e(TAG, "Settings screen not found", e)
            NovaResult.failure(ErrorCode.NOT_AVAILABLE, "সেটিংস স্ক্রিন খোলা যাচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to open settings screen", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "সেটিংস খুলতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "SystemSettingsOpener"
    }
}
EOF

# ---------- 2. ContactModels.kt ----------
cat > "$BASE/contacts/ContactModels.kt" <<'EOF'
package com.nova.ai.contacts

/** A person from the phone's contacts, with every phone number they have. */
data class Contact(val id: Long, val name: String, val numbers: List<String>)

/** What the user wants to do with the contact. */
enum class ContactPurpose { CALL, SMS }

/** One contact with how well its name matched what the user said. */
data class ContactMatch(val contact: Contact, val score: Float)

/** The decision after matching a spoken name against the contacts. */
sealed class ContactOutcome {
    /** One clear match. */
    data class Single(val contact: Contact) : ContactOutcome()

    /** Several contacts fit equally: the user must choose. */
    data class Ambiguous(val contacts: List<Contact>) : ContactOutcome()

    /** No contact fits. */
    object None : ContactOutcome()
}
EOF

# ---------- 3. ContactMatcher.kt ----------
cat > "$BASE/contacts/ContactMatcher.kt" <<'EOF'
package com.nova.ai.contacts

import com.nova.ai.apps.PhoneticKey

/**
 * Finds the contact the user meant. Works across Bangla and English spellings
 * ("সুমন" finds "Sumon"), and a single word matches part of a full name
 * ("সুমন" finds "সুমন আহমেদ"). Pure logic, no Android needed.
 */
object ContactMatcher {

    const val MIN_SCORE: Float = 0.75f
    const val CLEAR_GAP: Float = 0.08f

    private const val MAX_CHOICES: Int = 4
    private const val SCORE_EXACT: Float = 1.0f
    private const val SCORE_SAME_SOUND: Float = 0.95f
    private const val SCORE_CONTAINS: Float = 0.92f
    private const val WORD_FACTOR: Float = 0.97f
    private const val MIN_CONTAINS_LENGTH: Int = 3
    private const val MIN_CONTAINS_RATIO: Float = 0.5f
    private const val MIN_SKELETON_LENGTH: Int = 2
    private const val SOUND_WEIGHT: Float = 0.35f
    private const val SKELETON_WEIGHT: Float = 0.65f

    private val WHITESPACE: Regex = Regex("\\s+")

    /** Matches [spoken] against [contacts] and decides what to do. */
    fun match(spoken: String, contacts: List<Contact>): ContactOutcome =
        decide(rank(spoken, contacts))

    /** All contacts that fit [spoken] well enough, best first. */
    fun rank(spoken: String, contacts: List<Contact>): List<ContactMatch> {
        if (PhoneticKey.nameKey(spoken).isEmpty()) return emptyList()
        return contacts
            .map { ContactMatch(it, scoreName(spoken, it.name)) }
            .filter { it.score >= MIN_SCORE }
            .sortedByDescending { it.score }
    }

    /** Turns a ranked list into one decision. */
    fun decide(ranked: List<ContactMatch>): ContactOutcome {
        val top: ContactMatch = ranked.firstOrNull() ?: return ContactOutcome.None
        val close: List<ContactMatch> = ranked.filter { top.score - it.score < CLEAR_GAP }
        return if (close.size >= 2) {
            ContactOutcome.Ambiguous(close.take(MAX_CHOICES).map { it.contact })
        } else {
            ContactOutcome.Single(top.contact)
        }
    }

    /** Full-name score, or the best single-word score for longer names. */
    private fun scoreName(spoken: String, fullName: String): Float {
        val fullScore: Float = scorePair(spoken, fullName)
        val words: List<String> = fullName.split(WHITESPACE).filter { it.isNotBlank() }
        if (words.size < 2) return fullScore
        val bestWord: Float = words.maxOf { scorePair(spoken, it) } * WORD_FACTOR
        return maxOf(fullScore, bestWord)
    }

    private fun scorePair(spoken: String, name: String): Float {
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

# ---------- 4. ContactRepository.kt ----------
cat > "$BASE/contacts/ContactRepository.kt" <<'EOF'
package com.nova.ai.contacts

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.ContactsContract.CommonDataKinds.Phone
import androidx.core.content.ContextCompat
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val NUMBER_KEY_DIGITS: Int = 10

/**
 * Reads the phone's contacts (names and numbers). Needs the contacts permission.
 * Nothing is saved or sent anywhere, and names and numbers are never logged.
 */
class ContactRepository(context: Context) {

    private val appContext: Context = context.applicationContext

    /** True if the user allowed NOVA to read contacts. */
    fun hasPermission(): Boolean = ContextCompat.checkSelfPermission(
        appContext, Manifest.permission.READ_CONTACTS
    ) == PackageManager.PERMISSION_GRANTED

    /** Reads every contact that has a phone number. Runs on a background thread. */
    suspend fun loadAll(): NovaResult<List<Contact>> = withContext(Dispatchers.IO) {
        if (!hasPermission()) {
            return@withContext NovaResult.failure(
                ErrorCode.PERMISSION_DENIED,
                "কন্টাক্ট পড়ার অনুমতি নেই।"
            )
        }
        try {
            NovaResult.Success(readContacts())
        } catch (e: SecurityException) {
            NovaLogger.w(TAG, "Contacts access refused", e)
            NovaResult.failure(ErrorCode.PERMISSION_DENIED, "কন্টাক্ট পড়ার অনুমতি নেই।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to read contacts", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "কন্টাক্ট পড়তে সমস্যা হয়েছে।", e)
        }
    }

    private fun readContacts(): List<Contact> {
        val drafts = LinkedHashMap<Long, Draft>()
        val projection: Array<String> = arrayOf(Phone.CONTACT_ID, Phone.DISPLAY_NAME, Phone.NUMBER)

        appContext.contentResolver
            .query(Phone.CONTENT_URI, projection, null, null, null)
            ?.use { cursor ->
                val idColumn: Int = cursor.getColumnIndexOrThrow(Phone.CONTACT_ID)
                val nameColumn: Int = cursor.getColumnIndexOrThrow(Phone.DISPLAY_NAME)
                val numberColumn: Int = cursor.getColumnIndexOrThrow(Phone.NUMBER)

                while (cursor.moveToNext()) {
                    val name: String = cursor.getString(nameColumn)?.trim().orEmpty()
                    val number: String = cursor.getString(numberColumn)?.trim().orEmpty()
                    if (name.isEmpty() || number.isEmpty()) continue

                    val id: Long = cursor.getLong(idColumn)
                    drafts.getOrPut(id) { Draft(id, name) }.add(number)
                }
            }

        return drafts.values.map { Contact(it.id, it.name, it.numbers.toList()) }
    }

    /** A contact being built while rows are read; repeated numbers are dropped. */
    private class Draft(val id: Long, val name: String) {
        val numbers: MutableList<String> = ArrayList()
        private val seenKeys: MutableSet<String> = HashSet()

        fun add(number: String) {
            val key: String = number.filter { it.isDigit() }.takeLast(NUMBER_KEY_DIGITS)
            if (key.isNotEmpty() && seenKeys.add(key)) numbers.add(number)
        }
    }

    private companion object {
        const val TAG: String = "ContactRepository"
    }
}
EOF

# ---------- 5. PhoneActions.kt ----------
cat > "$BASE/contacts/PhoneActions.kt" <<'EOF'
package com.nova.ai.contacts

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/**
 * Starts a call, opens the dialer, or opens the SMS app with the message ready.
 * SMS is never sent automatically: the user reviews it and taps send.
 * Numbers and message text are never logged.
 */
class PhoneActions(context: Context) {

    private val appContext: Context = context.applicationContext

    /** Calls [number] at once. Needs the call permission. */
    fun call(number: String): NovaResult<Unit> = launch(callIntent(Intent.ACTION_CALL, number))

    /** Opens the dialer with [number] filled in; the user taps the call button. */
    fun dial(number: String): NovaResult<Unit> = launch(callIntent(Intent.ACTION_DIAL, number))

    /** Opens the SMS app with [number] as the receiver and [body] as the message. */
    fun composeSms(number: String, body: String?): NovaResult<Unit> {
        val intent = Intent(Intent.ACTION_SENDTO, Uri.fromParts("smsto", number, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (!body.isNullOrBlank()) intent.putExtra("sms_body", body)
        return launch(intent)
    }

    private fun callIntent(action: String, number: String): Intent =
        Intent(action, Uri.fromParts("tel", number, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    private fun launch(intent: Intent): NovaResult<Unit> {
        return try {
            appContext.startActivity(intent)
            NovaResult.Success(Unit)
        } catch (e: ActivityNotFoundException) {
            NovaLogger.e(TAG, "No app to handle the action", e)
            NovaResult.failure(ErrorCode.NOT_FOUND, "এই কাজের জন্য ফোনে কোনো অ্যাপ পাওয়া যায়নি।", e)
        } catch (e: SecurityException) {
            NovaLogger.w(TAG, "Action refused by the phone", e)
            NovaResult.failure(ErrorCode.PERMISSION_DENIED, "ফোন এই কাজের অনুমতি দিচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Action failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "কাজটি করতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "PhoneActions"
    }
}
EOF

# ---------- 6. ContactCommandController.kt ----------
cat > "$BASE/contacts/ContactCommandController.kt" <<'EOF'
package com.nova.ai.contacts

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.annotation.StringRes
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.nova.ai.R
import com.nova.ai.brain.RuleBasedBrain
import com.nova.ai.core.IntentType
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.nlp.IntentEntity
import com.nova.ai.voice.LanguageDetector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** What the Home screen shows about the last call or message command. */
sealed class ContactActionUi {
    object Idle : ContactActionUi()
    object NeedsContactsPermission : ContactActionUi()
    data class ChooseContact(
        val purpose: ContactPurpose,
        val spoken: String,
        val contacts: List<Contact>,
        val body: String?
    ) : ContactActionUi()
    data class ChooseNumber(
        val purpose: ContactPurpose,
        val contact: Contact,
        val body: String?
    ) : ContactActionUi()
    data class ConfirmCall(val name: String?, val number: String) : ContactActionUi()
    data class Done(val message: String) : ContactActionUi()
    data class Info(val message: String) : ContactActionUi()
    data class NotFound(val spoken: String) : ContactActionUi()
    data class Failed(val message: String) : ContactActionUi()
}

/**
 * Turns "call" and "send message" commands into real actions.
 * A call always needs the user's confirmation first. A message opens the SMS app
 * with the text ready; the user taps send. Use from the main thread.
 */
class ContactCommandController(
    context: Context,
    private val scope: CoroutineScope
) {

    private val appContext: Context = context.applicationContext
    private val repository = ContactRepository(appContext)
    private val actions = PhoneActions(appContext)
    private val brain = RuleBasedBrain()

    private var pendingIntent: NovaIntent? = null
    private var pendingCallNumber: String? = null

    var state: ContactActionUi by mutableStateOf<ContactActionUi>(ContactActionUi.Idle)
        private set

    /** Looks at [text]; if it asks for a call or a message, starts that flow. */
    fun handleCommand(text: String) {
        pendingIntent = null
        val intent: NovaIntent? = analyze(text)
        val relevant: Boolean = intent != null &&
            (intent.type == IntentType.MAKE_CALL || intent.type == IntentType.SEND_MESSAGE)
        if (intent == null || !relevant) {
            state = ContactActionUi.Idle
            return
        }
        process(intent)
    }

    /** The user answered the contacts permission question. */
    fun onContactsPermissionResult(granted: Boolean) {
        val intent: NovaIntent? = pendingIntent
        pendingIntent = null
        if (granted && intent != null) {
            process(intent)
        } else {
            state = ContactActionUi.Info(text(R.string.contact_permission_denied))
        }
    }

    /** The user picked one of several matching contacts. */
    fun pickContact(contact: Contact) {
        val current: ContactActionUi.ChooseContact = state as? ContactActionUi.ChooseContact ?: return
        chooseNumber(current.purpose, contact, current.body)
    }

    /** The user picked one of several numbers of a contact. */
    fun pickNumber(number: String) {
        val current: ContactActionUi.ChooseNumber = state as? ContactActionUi.ChooseNumber ?: return
        proceedWithNumber(current.purpose, current.contact.name, number, current.body)
    }

    /** True if the user allowed NOVA to place calls directly. */
    fun hasCallPermission(): Boolean = ContextCompat.checkSelfPermission(
        appContext, Manifest.permission.CALL_PHONE
    ) == PackageManager.PERMISSION_GRANTED

    /** Remembers the number while the call permission question is shown. */
    fun rememberPendingCall(number: String) {
        pendingCallNumber = number
    }

    /** The user answered the call permission question. */
    fun onCallPermissionResult(granted: Boolean) {
        val number: String = pendingCallNumber ?: return
        pendingCallNumber = null
        if (granted) {
            placeCall(number)
        } else {
            state = when (val result: NovaResult<Unit> = actions.dial(number)) {
                is NovaResult.Success -> ContactActionUi.Info(text(R.string.contact_call_denied))
                is NovaResult.Failure -> ContactActionUi.Failed(result.error.message)
            }
        }
    }

    /** Places the confirmed call (opens the dialer instead if the permission is missing). */
    fun placeCall(number: String) {
        if (!hasCallPermission()) {
            dial(number)
            return
        }
        state = when (val result: NovaResult<Unit> = actions.call(number)) {
            is NovaResult.Success -> ContactActionUi.Done(text(R.string.contact_call_started))
            is NovaResult.Failure -> ContactActionUi.Failed(result.error.message)
        }
    }

    /** Opens the dialer with the number filled in. */
    fun dial(number: String) {
        state = when (val result: NovaResult<Unit> = actions.dial(number)) {
            is NovaResult.Success -> ContactActionUi.Done(text(R.string.contact_dialer_opened))
            is NovaResult.Failure -> ContactActionUi.Failed(result.error.message)
        }
    }

    /** Hides the card. */
    fun dismiss() {
        pendingIntent = null
        pendingCallNumber = null
        state = ContactActionUi.Idle
    }

    private fun process(intent: NovaIntent) {
        val purpose: ContactPurpose =
            if (intent.type == IntentType.MAKE_CALL) ContactPurpose.CALL else ContactPurpose.SMS

        // Calls and messages through other apps (WhatsApp and so on) come in a later phase.
        val app: String? = intent.entities[IntentEntity.APP]
        if (app != null && !(purpose == ContactPurpose.SMS && app == SMS_APP_NAME)) {
            state = ContactActionUi.Info(text(R.string.contact_app_later))
            return
        }

        val body: String? = intent.entities[IntentEntity.BODY]
        val number: String? = intent.entities[IntentEntity.NUMBER]
        val contactName: String? = intent.entities[IntentEntity.CONTACT]

        when {
            number != null -> proceedWithNumber(purpose, null, number, body)
            contactName != null -> lookUpContact(intent, purpose, contactName, body)
            else -> state = ContactActionUi.Info(
                text(if (purpose == ContactPurpose.CALL) R.string.contact_who_call else R.string.contact_who_sms)
            )
        }
    }

    private fun lookUpContact(
        intent: NovaIntent,
        purpose: ContactPurpose,
        spoken: String,
        body: String?
    ) {
        if (!repository.hasPermission()) {
            pendingIntent = intent
            state = ContactActionUi.NeedsContactsPermission
            return
        }
        scope.launch {
            val contacts: List<Contact> = when (val result = repository.loadAll()) {
                is NovaResult.Success -> result.value
                is NovaResult.Failure -> {
                    state = ContactActionUi.Failed(result.error.message)
                    return@launch
                }
            }
            when (val outcome: ContactOutcome = ContactMatcher.match(spoken, contacts)) {
                is ContactOutcome.Single -> chooseNumber(purpose, outcome.contact, body)
                is ContactOutcome.Ambiguous ->
                    state = ContactActionUi.ChooseContact(purpose, spoken, outcome.contacts, body)
                is ContactOutcome.None -> state = ContactActionUi.NotFound(spoken)
            }
        }
    }

    private fun chooseNumber(purpose: ContactPurpose, contact: Contact, body: String?) {
        if (contact.numbers.size == 1) {
            proceedWithNumber(purpose, contact.name, contact.numbers.first(), body)
        } else {
            state = ContactActionUi.ChooseNumber(purpose, contact, body)
        }
    }

    private fun proceedWithNumber(
        purpose: ContactPurpose,
        name: String?,
        number: String,
        body: String?
    ) {
        when (purpose) {
            ContactPurpose.CALL -> state = ContactActionUi.ConfirmCall(name, number)
            ContactPurpose.SMS -> openSms(name, number, body)
        }
    }

    private fun openSms(name: String?, number: String, body: String?) {
        state = when (val result: NovaResult<Unit> = actions.composeSms(number, body)) {
            is NovaResult.Success -> ContactActionUi.Done(text(R.string.contact_sms_opened, name ?: number))
            is NovaResult.Failure -> ContactActionUi.Failed(result.error.message)
        }
    }

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

    private companion object {
        const val SMS_APP_NAME: String = "SMS"
    }
}
EOF

# ---------- 7. ContactActionCard.kt ----------
cat > "$BASE/ui/components/ContactActionCard.kt" <<'EOF'
package com.nova.ai.ui.components

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import com.nova.ai.contacts.ContactActionUi
import com.nova.ai.contacts.ContactCommandController

/**
 * Shows the steps of a call or message command on the Home screen: permission
 * question, choosing a contact or number, and the call confirmation.
 * Shows nothing while there is nothing to report.
 */
@Composable
fun ContactActionCard(
    controller: ContactCommandController,
    modifier: Modifier = Modifier
) {
    // Permission launchers must exist whatever the card shows.
    val contactsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted: Boolean -> controller.onContactsPermissionResult(granted) }

    val callLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted: Boolean -> controller.onCallPermissionResult(granted) }

    val current: ContactActionUi = controller.state
    if (current is ContactActionUi.Idle) return

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.contact_title),
                style = MaterialTheme.typography.titleMedium
            )

            when (current) {
                is ContactActionUi.Idle -> Unit

                is ContactActionUi.NeedsContactsPermission -> {
                    Text(stringResource(R.string.contact_permission_needed))
                    Button(
                        onClick = { contactsLauncher.launch(Manifest.permission.READ_CONTACTS) },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.contact_permission_button))
                    }
                }

                is ContactActionUi.ChooseContact -> {
                    Text(stringResource(R.string.contact_choose, current.spoken))
                    current.contacts.forEach { contact ->
                        val firstNumber: String = contact.numbers.firstOrNull().orEmpty()
                        Button(
                            onClick = { controller.pickContact(contact) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("${contact.name} $firstNumber".trim())
                        }
                    }
                }

                is ContactActionUi.ChooseNumber -> {
                    Text(stringResource(R.string.contact_choose_number, current.contact.name))
                    current.contact.numbers.forEach { number ->
                        Button(
                            onClick = { controller.pickNumber(number) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(number)
                        }
                    }
                }

                is ContactActionUi.ConfirmCall -> {
                    val name: String? = current.name
                    Text(
                        if (name != null) {
                            stringResource(R.string.contact_confirm_call, name, current.number)
                        } else {
                            stringResource(R.string.contact_confirm_call_number, current.number)
                        }
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = {
                                if (controller.hasCallPermission()) {
                                    controller.placeCall(current.number)
                                } else {
                                    controller.rememberPendingCall(current.number)
                                    callLauncher.launch(Manifest.permission.CALL_PHONE)
                                }
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(stringResource(R.string.contact_call_button))
                        }
                        OutlinedButton(
                            onClick = { controller.dial(current.number) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(stringResource(R.string.contact_dial_button))
                        }
                    }
                }

                is ContactActionUi.Done -> Text("✅ ${current.message}")

                is ContactActionUi.Info -> Text("💡 ${current.message}")

                is ContactActionUi.NotFound ->
                    Text(stringResource(R.string.contact_not_found, current.spoken))

                is ContactActionUi.Failed ->
                    Text(stringResource(R.string.contact_failed, current.message))
            }

            TextButton(onClick = { controller.dismiss() }) {
                Text(stringResource(R.string.contact_cancel))
            }
        }
    }
}
EOF

# ---------- G. HomeScreen.kt: a few additive lines (idempotent) ----------
if ! grep -q "ContactCommandController" "$HOME_FILE"; then
  grep -q '^import com.nova.ai.system.SystemCommandController$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (import) not found" >&2; exit 1; }
  grep -q 'val systemController: SystemCommandController = remember' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (controller) not found" >&2; exit 1; }
  grep -q 'systemController.handleCommand(command.rawText)' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (voice command) not found" >&2; exit 1; }
  grep -q 'systemController.handleCommand(commandText)' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (send button) not found" >&2; exit 1; }
  grep -q '^        SystemActionCard(controller = systemController)$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (card) not found" >&2; exit 1; }

  cat > "$TMP_DIR/home_imports.txt" <<'EOF'
import com.nova.ai.contacts.ContactCommandController
import com.nova.ai.ui.components.ContactActionCard
EOF
  cat > "$TMP_DIR/home_controller.txt" <<'EOF'

    // Runs call and message commands, using the phone's contacts.
    val contactController: ContactCommandController = remember { ContactCommandController(context, scope) }
EOF
  cat > "$TMP_DIR/home_voice.txt" <<'EOF'
                    contactController.handleCommand(command.rawText)
EOF
  cat > "$TMP_DIR/home_send.txt" <<'EOF'
                    contactController.handleCommand(commandText)
EOF
  cat > "$TMP_DIR/home_card.txt" <<'EOF'

        ContactActionCard(controller = contactController)
EOF

  sed -i "/^import com.nova.ai.system.SystemCommandController$/r $TMP_DIR/home_imports.txt" "$HOME_FILE"
  sed -i "/val systemController: SystemCommandController = remember/r $TMP_DIR/home_controller.txt" "$HOME_FILE"
  sed -i "/systemController.handleCommand(command.rawText)/r $TMP_DIR/home_voice.txt" "$HOME_FILE"
  sed -i "/systemController.handleCommand(commandText)/r $TMP_DIR/home_send.txt" "$HOME_FILE"
  sed -i "/^        SystemActionCard(controller = systemController)$/r $TMP_DIR/home_card.txt" "$HOME_FILE"
fi
grep -q "val contactController: ContactCommandController" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (controller)" >&2; exit 1; }
grep -q "contactController.handleCommand(command.rawText)" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (voice)" >&2; exit 1; }
grep -q "contactController.handleCommand(commandText)" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (send)" >&2; exit 1; }
grep -q "ContactActionCard(controller = contactController)" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (card)" >&2; exit 1; }

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "P14: calls and SMS by name or number, mobile data screen"
git push

echo "P14 files created and pushed."
