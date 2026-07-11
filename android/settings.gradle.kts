pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")

val awg2PreviewEnabled =
    (System.getenv("GREENVPN_ANDROID_AWG2_PREVIEW_ENABLED") ?: "false")
        .trim()
        .lowercase() in setOf("1", "true", "yes", "on")
if (awg2PreviewEnabled) {
    val awg2ModuleDir = file("transport_preview/awg_tunnel")
    require(awg2ModuleDir.isDirectory) {
        "AWG2 preview module is missing. Run scripts/windows/prepare_android_awg2_preview.ps1 first."
    }
    include(":awg_tunnel_preview")
    project(":awg_tunnel_preview").projectDir = awg2ModuleDir
}
