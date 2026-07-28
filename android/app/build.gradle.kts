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
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (releaseTaskRequested && !hasReleaseKeystore) {
    throw GradleException(
        "Release signing is required: android/key.properties is missing. " +
            "A release APK must never fall back to the debug certificate.",
    )
}
if (hasReleaseKeystore) {
    val requiredSigningKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
    val missingSigningKeys = requiredSigningKeys.filter {
        keystoreProperties.getProperty(it).isNullOrBlank()
    }
    if (missingSigningKeys.isNotEmpty()) {
        throw GradleException(
            "Release signing configuration is incomplete: ${missingSigningKeys.joinToString()}",
        )
    }
    val configuredStore = rootProject.file(keystoreProperties.getProperty("storeFile"))
    if (!configuredStore.isFile) {
        throw GradleException("Release keystore does not exist: ${configuredStore.absolutePath}")
    }
}

fun quotedBuildConfig(value: String): String {
    return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
}

fun environmentValue(name: String, defaultValue: String): String {
    return (System.getenv(name) ?: defaultValue).trim().ifEmpty { defaultValue }
}

val pubspecVersion =
    rootProject.file("../pubspec.yaml").useLines { lines ->
        lines.firstOrNull { it.trimStart().startsWith("version:") }
            ?.substringAfter("version:")
            ?.trim()
            ?.substringBefore("+")
    } ?: throw GradleException("Unable to read the application version from pubspec.yaml")
val greenVpnAppVersion = (System.getenv("GREENVPN_APP_VERSION") ?: pubspecVersion)
    .trim()
    .ifEmpty { pubspecVersion }
val greenVpnApplicationId = environmentValue("GREENVPN_ANDROID_APPLICATION_ID", "pro.greenvpn.app")
val greenVpnAppLabel = environmentValue("GREENVPN_ANDROID_APP_LABEL", "Green VPN")
val greenVpnApiBaseUrl = environmentValue("GREENVPN_ANDROID_API_BASE_URL", "https://api.greenvpn.pro")
val greenVpnApiFallbackBaseUrls = environmentValue(
    "GREENVPN_ANDROID_API_FALLBACK_BASE_URLS",
    "https://176-113-81-35.sslip.io",
)
val greenVpnReleaseChannel = environmentValue("GREENVPN_ANDROID_RELEASE_CHANNEL", "stable")
val greenVpnClientMarker = environmentValue("GREENVPN_ANDROID_CLIENT_MARKER", "")
val greenVpnAwg2PreviewEnabled =
    environmentValue("GREENVPN_ANDROID_AWG2_PREVIEW_ENABLED", "false").lowercase() in
        setOf("1", "true", "yes", "on")
val greenVpnHysteria2PreviewEnabled =
    environmentValue("GREENVPN_ANDROID_HYSTERIA2_PREVIEW_ENABLED", "false").lowercase() in
        setOf("1", "true", "yes", "on")
val greenVpnVlessRealityPreviewEnabled =
    environmentValue("GREENVPN_ANDROID_VLESS_REALITY_PREVIEW_ENABLED", "false").lowercase() in
        setOf("1", "true", "yes", "on")
val greenVpnNaiveHttpsPreviewEnabled =
    environmentValue("GREENVPN_ANDROID_NAIVE_HTTPS_PREVIEW_ENABLED", "false").lowercase() in
        setOf("1", "true", "yes", "on")
val greenVpnDnsttPreviewEnabled =
    environmentValue("GREENVPN_ANDROID_DNSTT_PREVIEW_ENABLED", "false").lowercase() in
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

    packaging {
        jniLibs.excludes += setOf(
            "lib/armeabi-v7a/**",
            "lib/x86/**",
        )
        jniLibs.keepDebugSymbols += setOf("**/libhysteria.so")
        jniLibs.keepDebugSymbols += setOf("**/libxray.so")
        jniLibs.keepDebugSymbols += setOf("**/libnaive.so")
        jniLibs.keepDebugSymbols += setOf("**/libdnstt_client.so")
        if (greenVpnHysteria2PreviewEnabled || greenVpnVlessRealityPreviewEnabled || greenVpnNaiveHttpsPreviewEnabled || greenVpnDnsttPreviewEnabled) {
            jniLibs.useLegacyPackaging = true
        }
    }

    defaultConfig {
        applicationId = greenVpnApplicationId
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
        manifestPlaceholders["greenVpnApplicationLabel"] = greenVpnAppLabel
        buildConfigField("String", "GREENVPN_APP_VERSION", quotedBuildConfig(greenVpnAppVersion))
        buildConfigField("String", "GREENVPN_APP_LABEL", quotedBuildConfig(greenVpnAppLabel))
        buildConfigField("String", "GREENVPN_API_BASE_URL", quotedBuildConfig(greenVpnApiBaseUrl))
        buildConfigField(
            "String",
            "GREENVPN_API_FALLBACK_BASE_URLS",
            quotedBuildConfig(greenVpnApiFallbackBaseUrls),
        )
        buildConfigField("String", "GREENVPN_RELEASE_CHANNEL", quotedBuildConfig(greenVpnReleaseChannel))
        buildConfigField("String", "GREENVPN_CLIENT_MARKER", quotedBuildConfig(greenVpnClientMarker))
        buildConfigField("boolean", "GREENVPN_AWG2_PREVIEW_ENABLED", greenVpnAwg2PreviewEnabled.toString())
        buildConfigField(
            "boolean",
            "GREENVPN_HYSTERIA2_PREVIEW_ENABLED",
            greenVpnHysteria2PreviewEnabled.toString(),
        )
        buildConfigField(
            "boolean",
            "GREENVPN_VLESS_REALITY_PREVIEW_ENABLED",
            greenVpnVlessRealityPreviewEnabled.toString(),
        )
        buildConfigField(
            "boolean",
            "GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED",
            greenVpnNaiveHttpsPreviewEnabled.toString(),
        )
        buildConfigField(
            "boolean",
            "GREENVPN_DNSTT_PREVIEW_ENABLED",
            greenVpnDnsttPreviewEnabled.toString(),
        )
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
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    // Official 1.0.20260102 with diagnostic wgVersion() calls disabled. The
    // native version probe can abort on affected Android 16 runtimes.
    implementation(files("libs/wireguard-tunnel-1.0.20260102-greenvpn.aar"))
    testImplementation("junit:junit:4.13.2")
    if (greenVpnAwg2PreviewEnabled) {
        implementation(project(":awg_tunnel_preview"))
    }
    if (greenVpnHysteria2PreviewEnabled || greenVpnVlessRealityPreviewEnabled || greenVpnNaiveHttpsPreviewEnabled || greenVpnDnsttPreviewEnabled) {
        implementation(project(":hysteria_tunnel_preview"))
    }
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
