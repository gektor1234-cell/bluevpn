plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val configuredApplicationId =
    (System.getenv("GREENVPN_ANDROID_TRANSPORT_PROBE_APPLICATION_ID")
        ?: "pro.greenvpn.transportprobe").trim()
require(configuredApplicationId.matches(Regex("^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+$"))) {
    "Invalid transport probe application ID"
}

android {
    namespace = "pro.greenvpn.transportprobe"
    compileSdk = 35

    defaultConfig {
        applicationId = configuredApplicationId
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}
