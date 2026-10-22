#!/usr/bin/env bash
# NOVA AI - Phase 17 setup script: Accessibility service foundation and the setup wizard.
# Additive: new setup package and service; PermissionsScreen is rewritten (its three
# permission explanations now live in the wizard); HomeScreen gets two additive lines.
set -euo pipefail

BASE="app/src/main/java/com/nova/ai"
MANIFEST="app/src/main/AndroidManifest.xml"
HOME_FILE="$BASE/ui/screens/HomeScreen.kt"

for required in \
  "$BASE/ui/screens/PermissionsScreen.kt" \
  "$BASE/ui/components/AppLibrarySection.kt" \
  "$BASE/accessibility/AccessibilityEngine.kt" \
  "$BASE/system/BrightnessController.kt" \
  "$HOME_FILE" "$MANIFEST"; do
  if [ ! -f "$required" ]; then
    echo "ERROR: $required not found. Run from repo root after P1 to P16 are installed." >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
mkdir -p "$BASE/setup" "$BASE/accessibility" app/src/main/res/xml

# ---------- A. Manifest: notification permission and the Accessibility service ----------
if ! grep -q "android.permission.POST_NOTIFICATIONS" "$MANIFEST"; then
  cat > "$TMP_DIR/manifest_perm.txt" <<'EOF'
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
EOF
  sed -i "/android.permission.RECORD_AUDIO/r $TMP_DIR/manifest_perm.txt" "$MANIFEST"
fi
grep -q "android.permission.POST_NOTIFICATIONS" "$MANIFEST" || { echo "ERROR: manifest edit failed (notifications)" >&2; exit 1; }

if ! grep -q "NovaAccessibilityService" "$MANIFEST"; then
  grep -q '</activity>' "$MANIFEST" || { echo "ERROR: manifest anchor not found" >&2; exit 1; }
  cat > "$TMP_DIR/manifest_service.txt" <<'EOF'

        <service
            android:name=".accessibility.NovaAccessibilityService"
            android:exported="true"
            android:label="@string/app_name"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/accessibility_service_config" />
        </service>
EOF
  sed -i "/<\/activity>/r $TMP_DIR/manifest_service.txt" "$MANIFEST"
fi
grep -q "NovaAccessibilityService" "$MANIFEST" || { echo "ERROR: manifest edit failed (service)" >&2; exit 1; }

# ---------- B. Service configuration ----------
cat > app/src/main/res/xml/accessibility_service_config.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<!--
  NOVA AI accessibility service. The capabilities below are all the project needs
  (read screen, tap and swipe, screenshot for the vision fallback), so the user
  grants them once.
-->
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagDefault|flagIncludeNotImportantViews|flagReportViewIds|flagRetrieveInteractiveWindows"
    android:canPerformGestures="true"
    android:canRetrieveWindowContent="true"
    android:canTakeScreenshot="true"
    android:description="@string/a11y_service_description"
    android:notificationTimeout="100" />
EOF

# ---------- C. New strings file ----------
cat > app/src/main/res/values/strings_p17.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="a11y_service_description">নোভা তোমার নির্দেশে স্ক্রিনের লেখা পড়ে এবং ক্লিক, লেখা ও স্ক্রলের মতো কাজ করে। পিন বা OTP নিজে লেখে না।</string>

    <string name="setup_title">সেটআপ উইজার্ড</string>
    <string name="setup_note">নোভার কাজের জন্য দরকারি অনুমতিগুলো এক জায়গায়। "পরের অনুমতি নাও" চাপতে থাকো, বাকিটা নোভা দেখিয়ে দেবে।</string>
    <string name="setup_progress">%1$d / %2$d ধাপ সম্পন্ন</string>
    <string name="setup_next">পরের অনুমতি নাও</string>
    <string name="setup_all_done">✅ সব অনুমতি সম্পন্ন</string>
    <string name="setup_grant">চালু করো</string>
    <string name="setup_error">সমস্যা: %1$s</string>

    <string name="setup_mic_title">মাইক্রোফোন</string>
    <string name="setup_mic_why">তোমার ভয়েস কমান্ড শুনতে লাগে।</string>
    <string name="setup_contacts_title">কন্টাক্ট</string>
    <string name="setup_contacts_why">নাম দিয়ে কল বা মেসেজ করতে কন্টাক্ট পড়তে লাগে। কন্টাক্ট ফোনের বাইরে যায় না।</string>
    <string name="setup_call_title">কল করা</string>
    <string name="setup_call_why">তুমি নিশ্চিত করার পর সরাসরি কল শুরু করতে লাগে।</string>
    <string name="setup_notif_title">নোটিফিকেশন দেখানো</string>
    <string name="setup_notif_why">ব্যাকগ্রাউন্ডে মাইক চালু থাকলে তা জানাতে লাগবে (পরের ফেজে কাজে আসবে)।</string>
    <string name="setup_a11y_title">Accessibility (স্ক্রিন পড়া ও ক্লিক)</string>
    <string name="setup_a11y_why">অন্য অ্যাপের স্ক্রিন পড়তে এবং ক্লিক, লেখা ও স্ক্রল করতে লাগে। নোভার সবচেয়ে গুরুত্বপূর্ণ অনুমতি।</string>
    <string name="setup_settings_title">সিস্টেম সেটিংস বদলানো</string>
    <string name="setup_settings_why">ব্রাইটনেস বদলাতে লাগে।</string>

    <string name="setup_a11y_help">সেটিংসে "ইনস্টল করা অ্যাপ" বা "Downloaded apps" থেকে NOVA AI বেছে চালু করো। সুইচ ধূসর থাকলে নিচের বাটনে অ্যাপের তথ্য খুলে ওপরে ডানের ⋮ চেপে "Allow restricted settings" চালু করো, তারপর আবার চেষ্টা করো।</string>
    <string name="setup_app_details">অ্যাপের তথ্য খোলো</string>
    <string name="setup_a11y_connected">Accessibility সার্ভিস: চালু ও সংযুক্ত ✅</string>
    <string name="setup_a11y_not_connected">Accessibility সার্ভিস: সেটিংসে চালু আছে, কিন্তু এখনো সংযুক্ত হয়নি। কয়েক সেকেন্ড অপেক্ষা করো, না হলে সেটিংসে একবার বন্ধ করে আবার চালু করো।</string>
    <string name="setup_last_app">সর্বশেষ দেখা অন্য অ্যাপ: %1$s</string>
    <string name="setup_last_app_none">সর্বশেষ দেখা অন্য অ্যাপ: এখনো কোনোটি না (অন্য একটি অ্যাপ খুলে ফিরে এসো)</string>
    <string name="setup_test_home">পরীক্ষা: হোম স্ক্রিনে যাও</string>

    <string name="setup_reminder_title">সেটআপ বাকি আছে</string>
    <string name="setup_reminder_body">%1$d টি অনুমতি বাকি। Access ট্যাবে গিয়ে "পরের অনুমতি নাও" চাপো।</string>
</resources>
EOF

# ---------- 1. AccessibilityStatus.kt ----------
cat > "$BASE/accessibility/AccessibilityStatus.kt" <<'EOF'
package com.nova.ai.accessibility

import android.content.ComponentName
import android.content.Context
import android.provider.Settings

/** Tells whether the user switched NOVA's accessibility service on in the phone's settings. */
object AccessibilityStatus {

    private const val SERVICE_LIST_SEPARATOR: Char = ':'

    /** True if the service is listed as enabled in the phone's settings. */
    fun isEnabledInSettings(context: Context): Boolean {
        val resolver = context.applicationContext.contentResolver
        val masterSwitch: Int = Settings.Secure.getInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 0)
        if (masterSwitch != 1) return false

        val enabledList: String = Settings.Secure.getString(
            resolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val expected = ComponentName(context.applicationContext, NovaAccessibilityService::class.java)
        return enabledList
            .split(SERVICE_LIST_SEPARATOR)
            .any { entry -> ComponentName.unflattenFromString(entry) == expected }
    }
}
EOF

# ---------- 2. AccessibilityBridge.kt ----------
cat > "$BASE/accessibility/AccessibilityBridge.kt" <<'EOF'
package com.nova.ai.accessibility

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import java.lang.ref.WeakReference

/**
 * Connects the screens and engines of the app with the running accessibility service.
 * The service registers itself here; everything else asks here instead of holding the service.
 */
object AccessibilityBridge {

    // Windows of the system itself are not "apps the user switched to".
    private val IGNORED_PACKAGES: Set<String> = setOf("com.android.systemui")

    @Volatile
    private var serviceRef: WeakReference<NovaAccessibilityService>? = null

    /** True while the service is running and connected. */
    var isConnected: Boolean by mutableStateOf(false)
        private set

    /** The package of the last app, other than NOVA, that came to the front. */
    var lastOtherPackage: String? by mutableStateOf<String?>(null)
        private set

    /** Called by the service when it connects. */
    fun attach(service: NovaAccessibilityService) {
        serviceRef = WeakReference(service)
        isConnected = true
    }

    /** Called by the service when it stops. */
    fun detach(service: NovaAccessibilityService) {
        if (serviceRef?.get() === service) {
            serviceRef = null
            isConnected = false
        }
    }

    /** Called by the service whenever a window comes to the front. */
    fun onForegroundPackage(foregroundPackage: String, ownPackage: String) {
        if (foregroundPackage == ownPackage || foregroundPackage in IGNORED_PACKAGES) return
        lastOtherPackage = foregroundPackage
    }

    /** The running service, or null if it is not connected. */
    fun service(): NovaAccessibilityService? = serviceRef?.get()

    /** Performs a global action such as Home or Back (see AccessibilityService.GLOBAL_ACTION_*). */
    fun performGlobal(action: Int): NovaResult<Unit> {
        val current: NovaAccessibilityService = serviceRef?.get()
            ?: return NovaResult.failure(ErrorCode.NOT_AVAILABLE, "Accessibility সার্ভিস সংযুক্ত নেই।")
        return if (current.performGlobalAction(action)) {
            NovaResult.Success(Unit)
        } else {
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "কাজটি করা যায়নি।")
        }
    }
}
EOF

# ---------- 3. NovaAccessibilityService.kt ----------
cat > "$BASE/accessibility/NovaAccessibilityService.kt" <<'EOF'
package com.nova.ai.accessibility

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import com.nova.ai.logging.NovaLogger

/**
 * NOVA's accessibility service. In this phase it only learns which app is in front.
 * Reading the screen, clicking, typing and scrolling are added in the next phases.
 * It never logs or stores anything that appears on the screen.
 */
class NovaAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        AccessibilityBridge.attach(this)
        NovaLogger.i(TAG, "Accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val eventPackage: String = event.packageName?.toString() ?: return
        AccessibilityBridge.onForegroundPackage(eventPackage, packageName)
    }

    override fun onInterrupt() {
        NovaLogger.i(TAG, "Accessibility service interrupted")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        AccessibilityBridge.detach(this)
        NovaLogger.i(TAG, "Accessibility service disconnected")
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        AccessibilityBridge.detach(this)
        super.onDestroy()
    }

    private companion object {
        const val TAG: String = "NovaAccessibility"
    }
}
EOF

# ---------- 4. SetupItem.kt ----------
cat > "$BASE/setup/SetupItem.kt" <<'EOF'
package com.nova.ai.setup

import android.Manifest
import androidx.annotation.StringRes
import com.nova.ai.R

/** The permissions NOVA needs the user to grant. Later phases add more. */
enum class SetupItemId {
    MICROPHONE,
    CONTACTS,
    CALL,
    NOTIFICATIONS,
    ACCESSIBILITY,
    SYSTEM_SETTINGS
}

/**
 * One permission in the setup wizard. [runtimePermission] is the Android permission
 * asked with a pop-up; it is null for special permissions the user switches on in Settings.
 */
data class SetupItem(
    val id: SetupItemId,
    @StringRes val titleRes: Int,
    @StringRes val whyRes: Int,
    val runtimePermission: String? = null
)

/** The list shown in the setup wizard, in the order they are asked. */
object SetupCatalog {

    val items: List<SetupItem> = listOf(
        SetupItem(
            SetupItemId.MICROPHONE,
            R.string.setup_mic_title,
            R.string.setup_mic_why,
            Manifest.permission.RECORD_AUDIO
        ),
        SetupItem(
            SetupItemId.CONTACTS,
            R.string.setup_contacts_title,
            R.string.setup_contacts_why,
            Manifest.permission.READ_CONTACTS
        ),
        SetupItem(
            SetupItemId.CALL,
            R.string.setup_call_title,
            R.string.setup_call_why,
            Manifest.permission.CALL_PHONE
        ),
        SetupItem(
            SetupItemId.NOTIFICATIONS,
            R.string.setup_notif_title,
            R.string.setup_notif_why,
            Manifest.permission.POST_NOTIFICATIONS
        ),
        SetupItem(
            SetupItemId.ACCESSIBILITY,
            R.string.setup_a11y_title,
            R.string.setup_a11y_why
        ),
        SetupItem(
            SetupItemId.SYSTEM_SETTINGS,
            R.string.setup_settings_title,
            R.string.setup_settings_why
        )
    )
}
EOF

# ---------- 5. SetupChecker.kt ----------
cat > "$BASE/setup/SetupChecker.kt" <<'EOF'
package com.nova.ai.setup

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.nova.ai.accessibility.AccessibilityStatus

/** Checks which permissions of the setup wizard the user has already granted. */
class SetupChecker(context: Context) {

    private val appContext: Context = context.applicationContext

    /** True if [item] is granted. */
    fun isGranted(item: SetupItem): Boolean = when (item.id) {
        SetupItemId.ACCESSIBILITY -> AccessibilityStatus.isEnabledInSettings(appContext)
        SetupItemId.SYSTEM_SETTINGS -> Settings.System.canWrite(appContext)
        // Before Android 13 notifications need no permission.
        SetupItemId.NOTIFICATIONS ->
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                hasRuntimePermission(item.runtimePermission)
        else -> hasRuntimePermission(item.runtimePermission)
    }

    /** The pop-up permissions that are still missing. They can be asked all at once. */
    fun missingRuntimePermissions(): List<String> =
        SetupCatalog.items
            .filter { it.runtimePermission != null && !isGranted(it) }
            .mapNotNull { it.runtimePermission }

    /** How many permissions are still missing. */
    fun missingCount(): Int = SetupCatalog.items.count { !isGranted(it) }

    private fun hasRuntimePermission(permission: String?): Boolean =
        permission != null &&
            ContextCompat.checkSelfPermission(appContext, permission) == PackageManager.PERMISSION_GRANTED
}
EOF

# ---------- 6. SetupLauncher.kt ----------
cat > "$BASE/setup/SetupLauncher.kt" <<'EOF'
package com.nova.ai.setup

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/** Opens the phone's settings screens where the user grants special permissions. */
object SetupLauncher {

    private const val TAG: String = "SetupLauncher"

    /** Opens the Accessibility settings list. */
    fun openAccessibilitySettings(context: Context): NovaResult<Unit> =
        start(context, Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))

    /** Opens the screen where the user allows NOVA to change system settings (brightness). */
    fun openWriteSettings(context: Context): NovaResult<Unit> =
        start(
            context,
            Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:${context.packageName}"))
        )

    /** Opens NOVA's own app information page (for "Allow restricted settings" and permissions). */
    fun openAppDetails(context: Context): NovaResult<Unit> =
        start(
            context,
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
        )

    private fun start(context: Context, intent: Intent): NovaResult<Unit> {
        return try {
            if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            NovaResult.Success(Unit)
        } catch (e: ActivityNotFoundException) {
            NovaLogger.e(TAG, "Settings screen not found", e)
            NovaResult.failure(ErrorCode.NOT_FOUND, "সেটিংস স্ক্রিন খোলা যাচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Failed to open a settings screen", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "সেটিংস খুলতে সমস্যা হয়েছে।", e)
        }
    }
}
EOF

# ---------- 7. SetupWizardCard.kt ----------
cat > "$BASE/ui/components/SetupWizardCard.kt" <<'EOF'
package com.nova.ai.ui.components

import android.accessibilityservice.AccessibilityService
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.nova.ai.R
import com.nova.ai.accessibility.AccessibilityBridge
import com.nova.ai.core.NovaResult
import com.nova.ai.setup.SetupCatalog
import com.nova.ai.setup.SetupChecker
import com.nova.ai.setup.SetupItem
import com.nova.ai.setup.SetupItemId
import com.nova.ai.setup.SetupLauncher

/**
 * The setup wizard: every permission NOVA needs, its status, and one button that
 * asks for the next missing one. Pop-up permissions are asked all together;
 * special permissions open the right settings screen. The card refreshes when
 * the user comes back from settings.
 */
@Composable
fun SetupWizardCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val checker: SetupChecker = remember { SetupChecker(context) }
    var refreshTick: Int by remember { mutableStateOf(0) }
    var message: String? by remember { mutableStateOf<String?>(null) }

    val lifecycleOwner: LifecycleOwner? = context as? LifecycleOwner
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refreshTick += 1
        }
        lifecycleOwner?.lifecycle?.addObserver(observer)
        onDispose { lifecycleOwner?.lifecycle?.removeObserver(observer) }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { _: Map<String, Boolean> -> refreshTick += 1 }

    val statuses: Map<SetupItemId, Boolean> = remember(refreshTick) {
        SetupCatalog.items.associate { item -> item.id to checker.isGranted(item) }
    }
    val doneCount: Int = statuses.values.count { it }
    val total: Int = statuses.size
    val accessibilityEnabled: Boolean = statuses[SetupItemId.ACCESSIBILITY] == true

    fun report(result: NovaResult<Unit>) {
        message = (result as? NovaResult.Failure)?.error?.message
    }

    fun grant(item: SetupItem) {
        message = null
        val permission: String? = item.runtimePermission
        when {
            permission != null -> permissionLauncher.launch(arrayOf(permission))
            item.id == SetupItemId.ACCESSIBILITY -> report(SetupLauncher.openAccessibilitySettings(context))
            item.id == SetupItemId.SYSTEM_SETTINGS -> report(SetupLauncher.openWriteSettings(context))
        }
    }

    fun grantNext() {
        message = null
        val missingRuntime: List<String> = checker.missingRuntimePermissions()
        if (missingRuntime.isNotEmpty()) {
            permissionLauncher.launch(missingRuntime.toTypedArray())
            return
        }
        val next: SetupItem = SetupCatalog.items.firstOrNull { statuses[it.id] != true } ?: return
        grant(next)
    }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = stringResource(R.string.setup_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.setup_note),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.setup_progress, doneCount, total),
                style = MaterialTheme.typography.titleMedium
            )
            LinearProgressIndicator(
                progress = { if (total == 0) 0f else doneCount / total.toFloat() },
                modifier = Modifier.fillMaxWidth()
            )

            if (doneCount < total) {
                Button(onClick = { grantNext() }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.setup_next))
                }
            } else {
                Text(text = stringResource(R.string.setup_all_done))
            }

            SetupCatalog.items.forEach { item ->
                key(item.id) {
                    SetupItemRow(
                        item = item,
                        granted = statuses[item.id] == true,
                        onGrant = { grant(item) }
                    )
                }
            }

            if (accessibilityEnabled) {
                AccessibilitySection(context) { error -> message = error }
            } else {
                Text(
                    text = stringResource(R.string.setup_a11y_help),
                    style = MaterialTheme.typography.bodySmall
                )
            }

            OutlinedButton(
                onClick = { report(SetupLauncher.openAppDetails(context)) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.setup_app_details))
            }

            message?.let { text ->
                Text(
                    text = stringResource(R.string.setup_error, text),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }
        }
    }
}

@Composable
private fun SetupItemRow(item: SetupItem, granted: Boolean, onGrant: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top
    ) {
        Text(text = if (granted) "✅" else "⚪")
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = stringResource(item.titleRes),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(item.whyRes),
                style = MaterialTheme.typography.bodySmall
            )
        }
        if (!granted) {
            OutlinedButton(onClick = onGrant) {
                Text(stringResource(R.string.setup_grant))
            }
        }
    }
}

/** Shown once Accessibility is on: is the service connected, what app was seen, and a Home test. */
@Composable
private fun AccessibilitySection(context: Context, onError: (String?) -> Unit) {
    val connected: Boolean = AccessibilityBridge.isConnected
    val lastPackage: String? = AccessibilityBridge.lastOtherPackage
    val lastLabel: String? = remember(lastPackage) { lastPackage?.let { appLabelOf(context, it) } }

    Text(
        text = stringResource(
            if (connected) R.string.setup_a11y_connected else R.string.setup_a11y_not_connected
        ),
        style = MaterialTheme.typography.bodySmall
    )
    Text(
        text = if (lastLabel != null) {
            stringResource(R.string.setup_last_app, lastLabel)
        } else {
            stringResource(R.string.setup_last_app_none)
        },
        style = MaterialTheme.typography.bodySmall
    )
    OutlinedButton(
        onClick = {
            val result: NovaResult<Unit> =
                AccessibilityBridge.performGlobal(AccessibilityService.GLOBAL_ACTION_HOME)
            onError((result as? NovaResult.Failure)?.error?.message)
        },
        enabled = connected,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(stringResource(R.string.setup_test_home))
    }
}

/** The name of an installed app, or its package name if the name cannot be read. */
@Suppress("DEPRECATION")
private fun appLabelOf(context: Context, packageName: String): String = try {
    val manager = context.packageManager
    manager.getApplicationLabel(manager.getApplicationInfo(packageName, 0)).toString()
} catch (e: Exception) {
    packageName
}
EOF

# ---------- 8. SetupReminderCard.kt ----------
cat > "$BASE/ui/components/SetupReminderCard.kt" <<'EOF'
package com.nova.ai.ui.components

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.nova.ai.R
import com.nova.ai.setup.SetupChecker

/** A short reminder on the Home screen while some permissions are still missing. */
@Composable
fun SetupReminderCard(modifier: Modifier = Modifier) {
    val context: Context = LocalContext.current
    val checker: SetupChecker = remember { SetupChecker(context) }
    var refreshTick: Int by remember { mutableStateOf(0) }

    val lifecycleOwner: LifecycleOwner? = context as? LifecycleOwner
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refreshTick += 1
        }
        lifecycleOwner?.lifecycle?.addObserver(observer)
        onDispose { lifecycleOwner?.lifecycle?.removeObserver(observer) }
    }

    val missing: Int = remember(refreshTick) { checker.missingCount() }
    if (missing == 0) return

    NovaInfoCard(
        title = stringResource(R.string.setup_reminder_title),
        body = stringResource(R.string.setup_reminder_body, missing),
        modifier = modifier
    )
}
EOF

# ---------- 9. PermissionsScreen.kt (the three old explanations now live in the wizard) ----------
cat > "$BASE/ui/screens/PermissionsScreen.kt" <<'EOF'
package com.nova.ai.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.nova.ai.R
import com.nova.ai.ui.components.AppLibrarySection
import com.nova.ai.ui.components.NovaScreenLayout
import com.nova.ai.ui.components.SetupWizardCard

/**
 * Access: the setup wizard (every permission with its reason and live status)
 * and NOVA's app list.
 */
@Composable
fun PermissionsScreen(modifier: Modifier = Modifier) {
    NovaScreenLayout(
        title = stringResource(R.string.permissions_title),
        subtitle = stringResource(R.string.permissions_subtitle),
        modifier = modifier
    ) {
        SetupWizardCard()
        AppLibrarySection()
    }
}
EOF

# ---------- D. HomeScreen.kt: two additive lines (idempotent) ----------
if ! grep -q "SetupReminderCard" "$HOME_FILE"; then
  grep -q '^import com.nova.ai.ui.components.AppActionCard$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (import) not found" >&2; exit 1; }
  grep -q '^        AppActionCard(controller = appController)$' "$HOME_FILE" \
    || { echo "ERROR: HomeScreen anchor (card) not found" >&2; exit 1; }

  cat > "$TMP_DIR/home_import.txt" <<'EOF'
import com.nova.ai.ui.components.SetupReminderCard
EOF
  cat > "$TMP_DIR/home_card.txt" <<'EOF'

        SetupReminderCard()
EOF
  sed -i "/^import com.nova.ai.ui.components.AppActionCard$/r $TMP_DIR/home_import.txt" "$HOME_FILE"
  sed -i "/^        AppActionCard(controller = appController)$/r $TMP_DIR/home_card.txt" "$HOME_FILE"
fi
grep -q "^import com.nova.ai.ui.components.SetupReminderCard$" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (import)" >&2; exit 1; }
grep -q "^        SetupReminderCard()$" "$HOME_FILE" || { echo "ERROR: HomeScreen edit failed (card)" >&2; exit 1; }

rm -rf "$TMP_DIR"

# ---------- Commit and push ----------
git add -A
git commit -m "P17: Accessibility service foundation and the setup wizard"
git push

echo "P17 files created and pushed."
