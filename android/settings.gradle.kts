pluginManagement {
    val flutterSdkPath = run {
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
    // 8.9.1 is the floor: androidx.core 1.18, pulled in by the file picker and
    // the foreground service, refuses anything older. 8.11.1 is what Flutter
    // currently wants, and the wrapper's Gradle 8.14 satisfies it.
    id("com.android.application") version "8.11.1" apply false
    // Flutter warns that support for Kotlin below 2.2.20 is being dropped.
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
