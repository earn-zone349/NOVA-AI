package com.nova.ai.nlp

/** Names of the details (entities) found inside a command. */
object IntentEntity {
    const val APP: String = "app"
    const val APP_SOURCE: String = "app_source"
    const val QUERY: String = "query"
    const val CONTACT: String = "contact"
    const val NUMBER: String = "number"
    const val BODY: String = "body"
    const val ACTION: String = "action"
    const val TARGET: String = "target"
    const val VALUE: String = "value"
    const val MODE: String = "mode"
    const val HOUR: String = "hour"
    const val MINUTE: String = "minute"
    const val PERIOD: String = "period"
    const val HOUR24: String = "hour24"
    const val DURATION_SECONDS: String = "duration_seconds"
}

/** Values of the [IntentEntity.ACTION] detail. */
object IntentAction {
    const val ON: String = "on"
    const val OFF: String = "off"
    const val UP: String = "up"
    const val DOWN: String = "down"
    const val SET: String = "set"
    const val MUTE: String = "mute"
    const val OPEN_SETTINGS: String = "open_settings"
    const val PLAY: String = "play"
    const val PAUSE: String = "pause"
    const val NEXT: String = "next"
    const val PREVIOUS: String = "previous"
}

/** Values of the [IntentEntity.TARGET] detail for system actions. */
object SystemTarget {
    const val WIFI: String = "wifi"
    const val BLUETOOTH: String = "bluetooth"
    const val FLASHLIGHT: String = "flashlight"
    const val VOLUME: String = "volume"
    const val BRIGHTNESS: String = "brightness"
    const val MOBILE_DATA: String = "mobile_data"
}

/** Values of the [IntentEntity.MODE] detail for time based commands. */
object IntentMode {
    const val ALARM: String = "alarm"
    const val TIMER: String = "timer"
    const val REMINDER: String = "reminder"
    const val PHOTO: String = "photo"
    const val VIDEO: String = "video"
}

/** Values of the [IntentEntity.PERIOD] detail. */
object IntentPeriod {
    const val AM: String = "am"
    const val PM: String = "pm"
    const val UNKNOWN: String = "unknown"
}

/** Values of the [IntentEntity.APP_SOURCE] detail. */
object IntentSource {
    const val CONTEXT: String = "context"
}
