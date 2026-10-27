package com.nova.ai.bubble

import android.content.Context
import com.nova.ai.R

/** The bubble texts, read from the string resources. */
internal class ResourceBubbleTexts(context: Context) : BubbleTexts {

    private val appContext: Context = context.applicationContext

    override fun opened(appLabel: String): String = appContext.getString(R.string.bub_opened, appLabel)
    override fun confirmApp(appLabel: String): String = appContext.getString(R.string.bub_confirm_app, appLabel)
    override fun chooseApp(spoken: String): String = appContext.getString(R.string.bub_choose_app, spoken)
    override fun suggestApp(spoken: String): String = appContext.getString(R.string.bub_suggest_app, spoken)
    override fun appNotFound(spoken: String): String = appContext.getString(R.string.bub_app_not_found, spoken)
    override fun chooseContact(spoken: String): String = appContext.getString(R.string.bub_choose_contact, spoken)
    override fun chooseNumber(contactName: String): String =
        appContext.getString(R.string.bub_choose_number, contactName)
    override fun confirmCall(who: String, number: String): String =
        appContext.getString(R.string.bub_confirm_call, who, number)
    override fun contactNotFound(spoken: String): String =
        appContext.getString(R.string.bub_contact_not_found, spoken)
    override fun askPeriod(clockText: String): String = appContext.getString(R.string.bub_ask_period, clockText)
    override fun needsContactsPermission(): String = appContext.getString(R.string.bub_needs_contacts)
    override fun yesOpen(): String = appContext.getString(R.string.bub_yes_open)
    override fun callNow(): String = appContext.getString(R.string.bub_call_now)
    override fun notUnderstood(): String = appContext.getString(R.string.bub_not_understood)
    override fun notDone(): String = appContext.getString(R.string.bub_not_done)
}
