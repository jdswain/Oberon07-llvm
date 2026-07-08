// OberonTUI — Kotlin/Compose host for Oberon programs on Android.
// Parallel to oc/ios/'s Swift Package: gives an app a ready-made
// terminal cell-grid view plus the JNI bridge that runtime/android/
// _rt.c files call up to.
//
// This is an Android Gradle library module. Consumed by the app in
// oed/android/ via `implementation(project(":oc-android"))` after
// including this directory as a Gradle subproject.

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace  = "com.oneav.oberon.tui"
    compileSdk = 34

    defaultConfig {
        minSdk = 24               // Android 7 Nougat — covers all live devices
        consumerProguardFiles("consumer-rules.pro")
    }

    buildFeatures {
        compose = true
    }
    composeOptions {
        // Composer plugin picks the right version for the Kotlin
        // release automatically — no explicit kotlinCompilerExtension
        // needed with the plugin approach.
    }

    kotlinOptions {
        jvmTarget = "17"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.03")
    implementation(composeBom)
    api(composeBom)

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.2")

    // Compose — foundation + material to keep the surface small.
    // Material3 pulls in unneeded theming; foundation gives us
    // Text / Box / GeometryLayout / Canvas etc.
    api("androidx.compose.foundation:foundation")
    api("androidx.compose.ui:ui")
    api("androidx.compose.ui:ui-tooling-preview")
}
