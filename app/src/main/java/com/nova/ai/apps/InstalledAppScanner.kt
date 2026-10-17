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
