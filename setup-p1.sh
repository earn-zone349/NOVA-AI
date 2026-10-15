#!/usr/bin/env bash
# NOVA AI - Phase 1 setup script. Run from the repo root.
set -euo pipefail

mkdir -p gradle .github/workflows \
  app/src/main/java/com/nova/ai \
  app/src/main/res/values

# ---------- 1. settings.gradle.kts ----------
cat > settings.gradle.kts <<'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "nova-ai"
include(":app")
EOF

# ---------- 2. build.gradle.kts (root) ----------
cat > build.gradle.kts <<'EOF'
// Root build file: plugins are declared here and applied in modules.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
}
EOF

# ---------- 3. gradle.properties ----------
cat > gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
org.gradle.caching=true
android.useAndroidX=true
android.nonTransitiveRClass=true
kotlin.code.style=official
EOF

# ---------- 4. libs.versions.toml ----------
cat > gradle/libs.versions.toml <<'EOF'
[versions]
agp = "8.5.2"
kotlin = "1.9.24"
composeCompiler = "1.5.14"
composeBom = "2024.06.00"
coreKtx = "1.13.1"
lifecycle = "2.8.4"
activityCompose = "1.9.1"

[libraries]
androidx-core-ktx = { group = "androidx.core", name = "core-ktx", version.ref = "coreKtx" }
androidx-lifecycle-runtime-ktx = { group = "androidx.lifecycle", name = "lifecycle-runtime-ktx", version.ref = "lifecycle" }
androidx-activity-compose = { group = "androidx.activity", name = "activity-compose", version.ref = "activityCompose" }
androidx-compose-bom = { group = "androidx.compose", name = "compose-bom", version.ref = "composeBom" }
androidx-compose-ui = { group = "androidx.compose.ui", name = "ui" }
androidx-compose-ui-tooling-preview = { group = "androidx.compose.ui", name = "ui-tooling-preview" }
androidx-compose-material3 = { group = "androidx.compose.material3", name = "material3" }

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
EOF

# ---------- 5. app/build.gradle.kts ----------
cat > app/build.gradle.kts <<'EOF'
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "com.nova.ai"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.nova.ai"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = libs.versions.composeCompiler.get()
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
}
EOF

# ---------- 6. proguard-rules.pro ----------
cat > app/proguard-rules.pro <<'EOF'
# NOVA AI ProGuard / R8 rules.
# Keep line numbers so release crash logs stay readable.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Keep the app's own classes needed by the system (Application, Activities).
-keep class com.nova.ai.NovaApp { *; }
-keep class com.nova.ai.MainActivity { *; }
EOF

# ---------- 7. AndroidManifest.xml ----------
cat > app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:name=".NovaApp"
        android:allowBackup="false"
        android:label="@string/app_name"
        android:supportsRtl="true"
        android:theme="@android:style/Theme.Material.NoActionBar">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

    </application>

</manifest>
EOF

# ---------- 8. strings.xml ----------
cat > app/src/main/res/values/strings.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">NOVA AI</string>
    <string name="home_status_ready">NOVA AI চালু আছে</string>
</resources>
EOF

# ---------- 9. .gitignore ----------
cat > .gitignore <<'EOF'
# Gradle / build output
.gradle/
build/
*/build/
.kotlin/

# Android Studio / IDE
.idea/
*.iml
local.properties
.DS_Store

# Secrets and signing keys (never commit)
*.jks
*.keystore
keystore.properties
google-services.json
EOF

# ---------- 10. GitHub Actions workflow ----------
cat > .github/workflows/build-apk.yml <<'EOF'
name: Build NOVA AI APK

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 30

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Set up Gradle (no wrapper needed)
        uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: '8.7'

      - name: Build debug APK
        run: gradle assembleDebug --stacktrace

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: nova-ai-debug-apk
          path: app/build/outputs/apk/debug/*.apk
          if-no-files-found: error
EOF

# ---------- 11. NovaApp.kt ----------
cat > app/src/main/java/com/nova/ai/NovaApp.kt <<'EOF'
package com.nova.ai

import android.app.Application
import android.util.Log

/**
 * Application entry point. Global, app-wide initialization lives here.
 * Later phases add the logger, database and crash handler.
 */
class NovaApp : Application() {

    override fun onCreate() {
        super.onCreate()
        try {
            Log.i(TAG, "NOVA AI started")
        } catch (e: Exception) {
            // Initialization must never crash the app at startup.
            Log.e(TAG, "Application init failed", e)
        }
    }

    companion object {
        private const val TAG: String = "NovaApp"
    }
}
EOF

# ---------- 12. MainActivity.kt ----------
cat > app/src/main/java/com/nova/ai/MainActivity.kt <<'EOF'
package com.nova.ai

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource

/**
 * Single-activity host. Phase 3 replaces the placeholder with the navigation graph.
 */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            setContent { NovaRoot() }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set content", e)
        }
    }

    companion object {
        private const val TAG: String = "MainActivity"
    }
}

/** Temporary root screen used to verify the first build. */
@Composable
private fun NovaRoot() {
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Text(text = stringResource(id = R.string.home_status_ready))
            }
        }
    }
}
EOF

# ---------- Commit and push ----------
git add -A
git commit -m "P1: project foundation and APK build pipeline"
git push

echo "P1 files created and pushed."
