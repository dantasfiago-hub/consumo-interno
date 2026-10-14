import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingFile = rootProject.file("key.properties")
if (signingFile.exists()) signingFile.inputStream().use { signingProperties.load(it) }
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", true) || it in listOf("assemble", "build", "bundle") }
if (releaseRequested && !signingFile.exists()) throw GradleException("Configure android/key.properties com a chave definitiva antes de gerar a versão release.")

android {
    namespace = "br.com.consumointerno.consumo_interno"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "br.com.consumointerno.consumo_interno"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Prevent native dependencies from advertising unsupported ABIs in a single-ABI APK.
        if (project.findProperty("target-platform") == "android-arm64") {
            ndk { abiFilters += "arm64-v8a" }
        }
    }

    signingConfigs {
        if (signingFile.exists()) {
            create("production") {
                storeFile = rootProject.file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("production")
            if (project.findProperty("target-platform") == "android-arm64") {
                ndk {
                    abiFilters.clear()
                    abiFilters += "arm64-v8a"
                }
            }
        }
    }
}

flutter {
    source = "../.."
}
