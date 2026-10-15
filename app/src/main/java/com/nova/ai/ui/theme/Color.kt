package com.nova.ai.ui.theme

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color

// Brand palette (indigo and teal).
private val Indigo40 = Color(0xFF4F46E5)
private val Indigo80 = Color(0xFFBDC2FF)
private val IndigoContainerLight = Color(0xFFE0E0FF)
private val IndigoContainerDark = Color(0xFF2F2BB0)
private val Teal40 = Color(0xFF00796B)
private val Teal80 = Color(0xFF7FD6C8)

/** Light color scheme. */
val NovaLightColors: ColorScheme = lightColorScheme(
    primary = Indigo40,
    onPrimary = Color.White,
    primaryContainer = IndigoContainerLight,
    onPrimaryContainer = Color(0xFF0B0B6B),
    secondary = Teal40,
    onSecondary = Color.White,
    background = Color(0xFFFBFBFF),
    onBackground = Color(0xFF1B1B1F),
    surface = Color(0xFFFBFBFF),
    onSurface = Color(0xFF1B1B1F),
    surfaceVariant = Color(0xFFE3E1EC),
    onSurfaceVariant = Color(0xFF46464F),
    error = Color(0xFFBA1A1A),
    onError = Color.White
)

/** Dark color scheme. */
val NovaDarkColors: ColorScheme = darkColorScheme(
    primary = Indigo80,
    onPrimary = Color(0xFF1A1F8F),
    primaryContainer = IndigoContainerDark,
    onPrimaryContainer = Color(0xFFE0E0FF),
    secondary = Teal80,
    onSecondary = Color(0xFF003731),
    background = Color(0xFF111318),
    onBackground = Color(0xFFE3E2E9),
    surface = Color(0xFF111318),
    onSurface = Color(0xFFE3E2E9),
    surfaceVariant = Color(0xFF45464F),
    onSurfaceVariant = Color(0xFFC6C5D0),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005)
)
