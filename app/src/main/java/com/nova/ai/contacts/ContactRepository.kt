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
