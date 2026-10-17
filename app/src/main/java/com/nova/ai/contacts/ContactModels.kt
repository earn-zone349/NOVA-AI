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
