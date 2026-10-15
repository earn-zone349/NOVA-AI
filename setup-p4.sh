#!/usr/bin/env bash
# NOVA AI - Phase 4 setup script: theme (light/dark), settings storage, onboarding.
# Additive: existing features stay. MainActivity and AiBrainScreen are rewritten
# with every previous element kept, plus the new theme/onboarding/settings parts.
set -euo pipefail

if [ ! -d app/src/main/java/com/nova/ai/ui/screens ]; then
  echo "ERROR: Run from repo root after P1, P2 and P3 are installed." >&2
  exit 1
fi

BASE="app/src/main/java/com/nova/ai"
mkdir -p "$BASE/ui/theme" "$BASE/settings" "$BASE/ui/components"

# ---------- A. New strings file ----------
cat > app/src/main/res/values/strings_p4.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Onboarding -->
    <string name="onboarding_step_format">%1$d / %2$d</string>
    <string name="onboarding_next">পরের ধাপ</string>
    <string name="onboarding_back">আগের ধাপ</string>
    <string name="onboarding_start">শুরু করো</string>

    <string name="onboarding_welcome_emoji">🤖</string>
    <string name="onboarding_welcome_title">NOVA AI-তে স্বাগতম</string>
    <string name="onboarding_welcome_body">আমি তোমার পার্সোনাল ফোন এজেন্ট। তোমার নির্দেশ বুঝে ফোনের কাজ ধাপে ধাপে করব, আর গুরুত্বপূর্ণ কাজের আগে তোমার অনুমতি নেব।</string>

    <string name="onboarding_features_title">যা যা করা যাবে</string>
    <string name="onboarding_feature_voice_title">🎙️ ভয়েস কমান্ড</string>
    <string name="onboarding_feature_voice_body">বাংলা, ইংরেজি ও মিশ্র ভাষায় নির্দেশ দেওয়া যাবে।</string>
    <string name="onboarding_feature_apps_title">📱 অ্যাপ ও স্ক্রিনের কাজ</string>
    <string name="onboarding_feature_apps_body">অ্যাপ খোলা, ক্লিক, লেখা ও একাধিক ধাপের কাজ।</string>
    <string name="onboarding_feature_privacy_title">🛡️ গোপনীয়তা</string>
    <string name="onboarding_feature_privacy_body">তোমার তথ্য ফোনেই থাকবে। কোনো Paid AI API লাগবে না।</string>

    <string name="onboarding_prefs_title">তোমার পছন্দ বেছে নাও</string>
    <string name="onboarding_prefs_note">এগুলো পরে AI Brain ট্যাব থেকে বদলানো যাবে।</string>

    <!-- Settings choices -->
    <string name="settings_theme_title">থিম</string>
    <string name="settings_theme_system">ফোনের সেটিং অনুযায়ী</string>
    <string name="settings_theme_light">লাইট</string>
    <string name="settings_theme_dark">ডার্ক</string>

    <string name="settings_language_title">ভাষা</string>
    <string name="settings_language_bangla">বাংলা</string>
    <string name="settings_language_english">English</string>
    <string name="settings_language_mixed">মিশ্র (বাংলা + English)</string>

    <string name="settings_appearance_card_title">চেহারা ও ভাষা</string>
</resources>
EOF

# ---------- 1. Color.kt ----------
cat > "$BASE/ui/theme/Color.kt" <<'EOF'
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
EOF

# ---------- 2. Type.kt ----------
cat > "$BASE/ui/theme/Type.kt" <<'EOF'
package com.nova.ai.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** App typography. Line heights are generous so Bangla text stays readable. */
val NovaTypography: Typography = Typography(
    headlineMedium = TextStyle(
        fontWeight = FontWeight.Bold,
        fontSize = 28.sp,
        lineHeight = 36.sp
    ),
    titleMedium = TextStyle(
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
        lineHeight = 24.sp
    ),
    bodyMedium = TextStyle(
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 22.sp
    ),
    bodySmall = TextStyle(
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 18.sp
    ),
    labelSmall = TextStyle(
        fontWeight = FontWeight.Medium,
        fontSize = 11.sp,
        lineHeight = 16.sp
    )
)
EOF

# ---------- 3. SettingsRepository.kt ----------
cat > "$BASE/settings/SettingsRepository.kt" <<'EOF'
package com.nova.ai.settings

import android.content.Context
import android.content.SharedPreferences
import android.util.Log

/** Theme choice. */
enum class ThemeMode { SYSTEM, LIGHT, DARK }

/** Preferred interaction language. Used by voice features from Phase 6. */
enum class AppLanguage { BANGLA, ENGLISH, MIXED }

/**
 * Stores app settings on the device only (SharedPreferences).
 * Every read falls back to a safe default, and every write is guarded,
 * so storage problems never crash the app.
 */
class SettingsRepository(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getThemeMode(): ThemeMode = readEnum(KEY_THEME, ThemeMode.SYSTEM)

    fun setThemeMode(mode: ThemeMode) = writeString(KEY_THEME, mode.name)

    fun getLanguage(): AppLanguage = readEnum(KEY_LANGUAGE, AppLanguage.BANGLA)

    fun setLanguage(language: AppLanguage) = writeString(KEY_LANGUAGE, language.name)

    fun isOnboardingDone(): Boolean = try {
        prefs.getBoolean(KEY_ONBOARDING_DONE, false)
    } catch (e: Exception) {
        Log.e(TAG, "Failed to read onboarding flag", e)
        false
    }

    fun setOnboardingDone(done: Boolean) {
        try {
            prefs.edit().putBoolean(KEY_ONBOARDING_DONE, done).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save onboarding flag", e)
        }
    }

    private inline fun <reified T : Enum<T>> readEnum(key: String, default: T): T {
        return try {
            val stored: String? = prefs.getString(key, null)
            if (stored == null) default else enumValueOf<T>(stored)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read $key, using default", e)
            default
        }
    }

    private fun writeString(key: String, value: String) {
        try {
            prefs.edit().putString(key, value).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save $key", e)
        }
    }

    private companion object {
        const val TAG: String = "SettingsRepository"
        const val PREFS_NAME: String = "nova_settings"
        const val KEY_THEME: String = "theme_mode"
        const val KEY_LANGUAGE: String = "app_language"
        const val KEY_ONBOARDING_DONE: String = "onboarding_done"
    }
}
EOF

# ---------- 4. AppSettings.kt (settings shared with every screen) ----------
cat > "$BASE/ui/theme/AppSettings.kt" <<'EOF'
package com.nova.ai.ui.theme

import androidx.compose.runtime.compositionLocalOf
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.ThemeMode

/** Current settings plus the callbacks screens use to change them. */
data class AppSettingsState(
    val themeMode: ThemeMode,
    val language: AppLanguage,
    val onThemeModeChange: (ThemeMode) -> Unit,
    val onLanguageChange: (AppLanguage) -> Unit
)

/** Gives every screen access to [AppSettingsState] without passing it manually. */
val LocalAppSettings = compositionLocalOf {
    AppSettingsState(
        themeMode = ThemeMode.SYSTEM,
        language = AppLanguage.BANGLA,
        onThemeModeChange = { },
        onLanguageChange = { }
    )
}
EOF

# ---------- 5. Theme.kt ----------
cat > "$BASE/ui/theme/Theme.kt" <<'EOF'
package com.nova.ai.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import com.nova.ai.settings.ThemeMode

/** App theme. [themeMode] decides light, dark, or follow the phone. */
@Composable
fun NovaTheme(
    themeMode: ThemeMode = ThemeMode.SYSTEM,
    content: @Composable () -> Unit
) {
    val systemDark: Boolean = isSystemInDarkTheme()
    val useDark: Boolean = when (themeMode) {
        ThemeMode.SYSTEM -> systemDark
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }
    val colors: ColorScheme = if (useDark) NovaDarkColors else NovaLightColors

    MaterialTheme(
        colorScheme = colors,
        typography = NovaTypography,
        content = content
    )
}
EOF

# ---------- 6. NovaChoiceGroup.kt (reusable radio group + labels) ----------
cat > "$BASE/ui/components/NovaChoiceGroup.kt" <<'EOF'
package com.nova.ai.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.ThemeMode

/** Single-choice list with radio buttons. Whole row is tappable. */
@Composable
fun <T> NovaChoiceGroup(
    title: String,
    options: List<T>,
    selected: T,
    labelOf: @Composable (T) -> String,
    onSelected: (T) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxWidth().selectableGroup()) {
        Text(text = title, style = MaterialTheme.typography.titleMedium)
        options.forEach { option ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .selectable(
                        selected = option == selected,
                        onClick = { onSelected(option) },
                        role = Role.RadioButton
                    )
                    .padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                RadioButton(selected = option == selected, onClick = null)
                Spacer(modifier = Modifier.width(12.dp))
                Text(text = labelOf(option), style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

/** Display text for a [ThemeMode]. */
@Composable
fun themeModeLabel(mode: ThemeMode): String = stringResource(
    when (mode) {
        ThemeMode.SYSTEM -> R.string.settings_theme_system
        ThemeMode.LIGHT -> R.string.settings_theme_light
        ThemeMode.DARK -> R.string.settings_theme_dark
    }
)

/** Display text for an [AppLanguage]. */
@Composable
fun languageLabel(language: AppLanguage): String = stringResource(
    when (language) {
        AppLanguage.BANGLA -> R.string.settings_language_bangla
        AppLanguage.ENGLISH -> R.string.settings_language_english
        AppLanguage.MIXED -> R.string.settings_language_mixed
    }
)
EOF

# ---------- 7. OnboardingScreen.kt ----------
cat > "$BASE/ui/screens/OnboardingScreen.kt" <<'EOF'
package com.nova.ai.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nova.ai.R
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.ThemeMode
import com.nova.ai.ui.components.NovaChoiceGroup
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.languageLabel
import com.nova.ai.ui.components.themeModeLabel

private const val TOTAL_STEPS: Int = 3

/**
 * First-run guide: welcome, feature overview, then language and theme choice.
 * Calls [onFinished] with the chosen settings when the user taps Start.
 */
@Composable
fun OnboardingScreen(
    onFinished: (AppLanguage, ThemeMode) -> Unit,
    modifier: Modifier = Modifier
) {
    var step: Int by rememberSaveable { mutableStateOf(0) }
    var language: AppLanguage by rememberSaveable { mutableStateOf(AppLanguage.BANGLA) }
    var theme: ThemeMode by rememberSaveable { mutableStateOf(ThemeMode.SYSTEM) }
    val lastStep: Int = TOTAL_STEPS - 1

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp)
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = stringResource(R.string.onboarding_step_format, step + 1, TOTAL_STEPS),
                style = MaterialTheme.typography.bodySmall
            )
            when (step) {
                0 -> WelcomeStep()
                1 -> FeaturesStep()
                else -> PreferencesStep(
                    language = language,
                    theme = theme,
                    onLanguageChange = { language = it },
                    onThemeChange = { theme = it }
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (step > 0) {
                OutlinedButton(
                    onClick = { step -= 1 },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.onboarding_back))
                }
            }
            Button(
                onClick = {
                    if (step < lastStep) step += 1 else onFinished(language, theme)
                },
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    stringResource(
                        if (step < lastStep) R.string.onboarding_next else R.string.onboarding_start
                    )
                )
            }
        }
    }
}

@Composable
private fun WelcomeStep() {
    Text(text = stringResource(R.string.onboarding_welcome_emoji), fontSize = 64.sp)
    Text(
        text = stringResource(R.string.onboarding_welcome_title),
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold
    )
    Text(
        text = stringResource(R.string.onboarding_welcome_body),
        style = MaterialTheme.typography.bodyMedium
    )
}

@Composable
private fun FeaturesStep() {
    Text(
        text = stringResource(R.string.onboarding_features_title),
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold
    )
    NovaInfoCard(
        title = stringResource(R.string.onboarding_feature_voice_title),
        body = stringResource(R.string.onboarding_feature_voice_body)
    )
    NovaInfoCard(
        title = stringResource(R.string.onboarding_feature_apps_title),
        body = stringResource(R.string.onboarding_feature_apps_body)
    )
    NovaInfoCard(
        title = stringResource(R.string.onboarding_feature_privacy_title),
        body = stringResource(R.string.onboarding_feature_privacy_body)
    )
}

@Composable
private fun PreferencesStep(
    language: AppLanguage,
    theme: ThemeMode,
    onLanguageChange: (AppLanguage) -> Unit,
    onThemeChange: (ThemeMode) -> Unit
) {
    Text(
        text = stringResource(R.string.onboarding_prefs_title),
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold
    )
    NovaChoiceGroup(
        title = stringResource(R.string.settings_language_title),
        options = AppLanguage.values().toList(),
        selected = language,
        labelOf = { languageLabel(it) },
        onSelected = onLanguageChange
    )
    NovaChoiceGroup(
        title = stringResource(R.string.settings_theme_title),
        options = ThemeMode.values().toList(),
        selected = theme,
        labelOf = { themeModeLabel(it) },
        onSelected = onThemeChange
    )
    Text(
        text = stringResource(R.string.onboarding_prefs_note),
        style = MaterialTheme.typography.bodySmall
    )
}
EOF

# ---------- B. AiBrainScreen.kt (all 4 original cards kept + appearance card) ----------
cat > "$BASE/ui/screens/AiBrainScreen.kt" <<'EOF'
package com.nova.ai.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.nova.ai.R
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.ThemeMode
import com.nova.ai.ui.components.NovaChoiceGroup
import com.nova.ai.ui.components.NovaInfoCard
import com.nova.ai.ui.components.NovaScreenLayout
import com.nova.ai.ui.components.languageLabel
import com.nova.ai.ui.components.themeModeLabel
import com.nova.ai.ui.theme.LocalAppSettings

/** AI Brain: model status, memory use, offline status, language, and appearance. */
@Composable
fun AiBrainScreen(modifier: Modifier = Modifier) {
    val settings = LocalAppSettings.current

    NovaScreenLayout(
        title = stringResource(R.string.brain_title),
        subtitle = stringResource(R.string.brain_subtitle),
        modifier = modifier
    ) {
        NovaInfoCard(
            title = stringResource(R.string.brain_model_title),
            body = stringResource(R.string.brain_model_none)
        )
        NovaInfoCard(
            title = stringResource(R.string.brain_ram_title),
            body = stringResource(R.string.brain_ram_none)
        )
        NovaInfoCard(
            title = stringResource(R.string.brain_offline_title),
            body = stringResource(R.string.brain_offline_body)
        )
        NovaInfoCard(
            title = stringResource(R.string.brain_language_title),
            body = stringResource(R.string.brain_language_body)
        )

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                NovaChoiceGroup(
                    title = stringResource(R.string.settings_language_title),
                    options = AppLanguage.values().toList(),
                    selected = settings.language,
                    labelOf = { languageLabel(it) },
                    onSelected = settings.onLanguageChange
                )
                NovaChoiceGroup(
                    title = stringResource(R.string.settings_theme_title),
                    options = ThemeMode.values().toList(),
                    selected = settings.themeMode,
                    labelOf = { themeModeLabel(it) },
                    onSelected = settings.onThemeModeChange
                )
            }
        }
    }
}
EOF

# ---------- C. MainActivity.kt (theme + onboarding + settings wired in) ----------
cat > "$BASE/MainActivity.kt" <<'EOF'
package com.nova.ai

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.nova.ai.settings.AppLanguage
import com.nova.ai.settings.SettingsRepository
import com.nova.ai.settings.ThemeMode
import com.nova.ai.ui.navigation.NovaMainScaffold
import com.nova.ai.ui.screens.OnboardingScreen
import com.nova.ai.ui.theme.AppSettingsState
import com.nova.ai.ui.theme.LocalAppSettings
import com.nova.ai.ui.theme.NovaTheme

/**
 * Single-activity host. Applies the theme, shows onboarding on first launch,
 * then the navigation graph (Home, Brain, Tasks, Access, Memory, Privacy).
 */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val repository = SettingsRepository(applicationContext)
            setContent { NovaRoot(repository) }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set content", e)
        }
    }

    companion object {
        private const val TAG: String = "MainActivity"
    }
}

/** Root composable: settings state, theme, onboarding gate and main scaffold. */
@Composable
private fun NovaRoot(repository: SettingsRepository) {
    var themeMode: ThemeMode by remember { mutableStateOf(repository.getThemeMode()) }
    var language: AppLanguage by remember { mutableStateOf(repository.getLanguage()) }
    var onboardingDone: Boolean by remember { mutableStateOf(repository.isOnboardingDone()) }

    val settingsState = AppSettingsState(
        themeMode = themeMode,
        language = language,
        onThemeModeChange = { newMode ->
            themeMode = newMode
            repository.setThemeMode(newMode)
        },
        onLanguageChange = { newLanguage ->
            language = newLanguage
            repository.setLanguage(newLanguage)
        }
    )

    NovaTheme(themeMode = themeMode) {
        CompositionLocalProvider(LocalAppSettings provides settingsState) {
            Surface(modifier = Modifier.fillMaxSize()) {
                if (onboardingDone) {
                    NovaMainScaffold()
                } else {
                    OnboardingScreen(
                        onFinished = { chosenLanguage, chosenTheme ->
                            language = chosenLanguage
                            themeMode = chosenTheme
                            repository.setLanguage(chosenLanguage)
                            repository.setThemeMode(chosenTheme)
                            repository.setOnboardingDone(true)
                            onboardingDone = true
                        }
                    )
                }
            }
        }
    }
}
EOF

# ---------- Commit and push ----------
git add -A
git commit -m "P4: theme (light/dark), settings storage, onboarding"
git push

echo "P4 files created and pushed."
