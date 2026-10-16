package com.nova.ai.voice

import com.nova.ai.core.Language
import com.nova.ai.settings.AppLanguage

/** Converts the language chosen in settings into the language used for speech. */
fun AppLanguage.toSpeechLanguage(): Language = when (this) {
    AppLanguage.BANGLA -> Language.BANGLA
    AppLanguage.ENGLISH -> Language.ENGLISH
    AppLanguage.MIXED -> Language.MIXED
}
