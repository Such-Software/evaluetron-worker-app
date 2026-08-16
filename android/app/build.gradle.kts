import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material lives outside the repository. When it is absent the
// release build stays unsigned on purpose: a debug-signed release must never
// leave this machine.
val releaseKeyFile = rootProject.file("key.properties")
val releaseKey = Properties()
if (releaseKeyFile.exists()) {
    releaseKeyFile.inputStream().use(releaseKey::load)
} else if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
    logger.warn(
        "WARNING: android/key.properties is missing, so this release build is UNSIGNED. " +
            "It cannot be installed or uploaded until it is signed. " +
            "See README.md, 'Android release signing'."
    )
}

android {
    namespace = "com.suchsoftware.evaluetron.worker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.suchsoftware.evaluetron.worker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeyFile.exists()) {
            create("release") {
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
                storeFile = releaseKey.getProperty("storeFile")?.let(::file)
                storePassword = releaseKey.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Null when no operator key is configured, which produces an
            // unsigned artifact. It is never the debug config.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

flutter {
    source = "../.."
}
