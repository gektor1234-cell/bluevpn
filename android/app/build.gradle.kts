import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun quotedBuildConfig(value: String): String {
    return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
}

fun environmentValue(name: String, defaultValue: String): String {
    return (System.getenv(name) ?: defaultValue).trim().ifEmpty { defaultValue }
}

val greenVpnAppVersion = (System.getenv("GREENVPN_APP_VERSION") ?: "0.2.23-trial-only-android-vpn-takeover")
    .trim()
    .ifEmpty { "0.2.23-trial-only-android-vpn-takeover" }
val greenVpnApplicationId = environmentValue("GREENVPN_ANDROID_APPLICATION_ID", "pro.greenvpn.app")
val greenVpnAppLabel = environmentValue("GREENVPN_ANDROID_APP_LABEL", "Green VPN")
val greenVpnApiBaseUrl = environmentValue("GREENVPN_ANDROID_API_BASE_URL", "https://api.greenvpn.pro")
val greenVpnApiFallbackBaseUrls = environmentValue(
    "GREENVPN_ANDROID_API_FALLBACK_BASE_URLS",
    "https://176-113-81-35.sslip.io",
)
val greenVpnAwg2PreviewEnabled =
    environmentValue("GREENVPN_ANDROID_AWG2_PREVIEW_ENABLED", "false").lowercase() in
        setOf("1", "true", "yes", "on")

android {
    namespace = "pro.greenvpn.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = greenVpnApplicationId
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["greenVpnApplicationLabel"] = greenVpnAppLabel
        buildConfigField("String", "GREENVPN_APP_VERSION", quotedBuildConfig(greenVpnAppVersion))
        buildConfigField("String", "GREENVPN_APP_LABEL", quotedBuildConfig(greenVpnAppLabel))
        buildConfigField("String", "GREENVPN_API_BASE_URL", quotedBuildConfig(greenVpnApiBaseUrl))
        buildConfigField(
            "String",
            "GREENVPN_API_FALLBACK_BASE_URLS",
            quotedBuildConfig(greenVpnApiFallbackBaseUrls),
        )
        buildConfigField("boolean", "GREENVPN_AWG2_PREVIEW_ENABLED", greenVpnAwg2PreviewEnabled.toString())
    }

    if (hasReleaseKeystore) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("com.wireguard.android:tunnel:1.0.20260102")
    if (greenVpnAwg2PreviewEnabled) {
        implementation(project(":awg_tunnel_preview"))
    }
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
