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
