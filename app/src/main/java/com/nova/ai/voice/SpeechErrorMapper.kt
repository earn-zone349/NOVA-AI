package com.nova.ai.voice

import android.speech.SpeechRecognizer
import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaError

/**
 * Converts Android speech-recognizer error numbers into [NovaError] with a Bangla message.
 * Short-lived service problems get [ErrorCode.TEMPORARY_FAILURE] so the conversation
 * can retry instead of giving up.
 */
internal object SpeechErrorMapper {

    fun toNovaError(speechError: Int): NovaError {
        val mapped: Pair<ErrorCode, String> = when (speechError) {
            SpeechRecognizer.ERROR_AUDIO ->
                ErrorCode.NOT_AVAILABLE to "অডিও রেকর্ড করতে সমস্যা হয়েছে।"
            SpeechRecognizer.ERROR_CLIENT ->
                ErrorCode.TEMPORARY_FAILURE to "ভয়েস সিস্টেমে ছোট একটি সমস্যা হয়েছে। আবার চেষ্টা করো।"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                ErrorCode.PERMISSION_DENIED to "মাইক্রোফোনের অনুমতি নেই।"
            SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                ErrorCode.NOT_AVAILABLE to "ইন্টারনেট সমস্যা। এই ভাষার অফলাইন ভয়েস নাও থাকতে পারে।"
            SpeechRecognizer.ERROR_NO_MATCH ->
                ErrorCode.NOT_FOUND to "কথা বোঝা যায়নি। আবার পরিষ্কার করে বলো।"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                ErrorCode.TIMEOUT to "কিছু শোনা যায়নি। আবার চেষ্টা করো।"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY ->
                ErrorCode.TEMPORARY_FAILURE to "ভয়েস সিস্টেম ব্যস্ত আছে। একটু পরে চেষ্টা করো।"
            SpeechRecognizer.ERROR_SERVER, SpeechRecognizer.ERROR_SERVER_DISCONNECTED ->
                ErrorCode.TEMPORARY_FAILURE to "ভয়েস সার্ভিসে সমস্যা হয়েছে। আবার চেষ্টা করো।"
            SpeechRecognizer.ERROR_TOO_MANY_REQUESTS ->
                ErrorCode.TEMPORARY_FAILURE to "অনেকবার চেষ্টা হয়েছে। একটু পরে আবার চেষ্টা করো।"
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
            SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
                ErrorCode.NOT_AVAILABLE to "এই ভাষা ফোনে চালু নেই। AI Brain ট্যাব থেকে ভাষা বদলে দেখো।"
            else ->
                ErrorCode.UNKNOWN to "অজানা ভয়েস সমস্যা (কোড $speechError)।"
        }
        return NovaError(code = mapped.first, message = mapped.second)
    }
}
