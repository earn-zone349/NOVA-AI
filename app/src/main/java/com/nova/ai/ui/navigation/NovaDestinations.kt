package com.nova.ai.ui.navigation

import androidx.annotation.StringRes
import com.nova.ai.R

/** Every top-level screen in the app, with its route, label and icon. */
enum class NovaDestination(
    val route: String,
    @StringRes val labelRes: Int,
    val iconEmoji: String
) {
    HOME("home", R.string.nav_home, "🏠"),
    BRAIN("brain", R.string.nav_brain, "🧠"),
    AUTOMATION("automation", R.string.nav_automation, "⚙️"),
    PERMISSIONS("permissions", R.string.nav_permissions, "🔑"),
    MEMORY("memory", R.string.nav_memory, "💾"),
    PRIVACY("privacy", R.string.nav_privacy, "🛡️");

    companion object {
        /** Finds the destination for [route], or null if the route is unknown. */
        fun fromRoute(route: String?): NovaDestination? =
            values().firstOrNull { it.route == route }
    }
}
