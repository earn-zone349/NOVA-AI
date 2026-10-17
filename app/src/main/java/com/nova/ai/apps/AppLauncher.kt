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
