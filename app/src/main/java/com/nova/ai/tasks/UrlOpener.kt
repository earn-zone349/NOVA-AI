package com.nova.ai.tasks

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaResult
import com.nova.ai.logging.NovaLogger

/** Opens a web page in the phone's browser. Only https addresses are accepted. */
class UrlOpener(context: Context) {

    private val appContext: Context = context.applicationContext

    /** Opens [url]. A failure result carries a Bangla message for the user. */
    fun open(url: String): NovaResult<Unit> {
        if (!url.startsWith(HTTPS_PREFIX)) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, "এই ঠিকানা খোলা নিরাপদ নয়।")
        }
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appContext.startActivity(intent)
            NovaLogger.i(TAG, "Web page opened")
            NovaResult.Success(Unit)
        } catch (e: ActivityNotFoundException) {
            NovaLogger.e(TAG, "No browser found", e)
            NovaResult.failure(ErrorCode.NOT_FOUND, "ফোনে ব্রাউজার পাওয়া যায়নি।", e)
        } catch (e: SecurityException) {
            NovaLogger.e(TAG, "Opening the page was blocked", e)
            NovaResult.failure(ErrorCode.PERMISSION_DENIED, "ফোন পেজটি খুলতে দিচ্ছে না।", e)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Opening the page failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "পেজ খুলতে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "UrlOpener"
        const val HTTPS_PREFIX: String = "https://"
    }
}
