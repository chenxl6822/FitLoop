plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val compatibilitySigning =
    System.getenv("FITLOOP_COMPAT_SIGNING")?.equals("true", ignoreCase = true) == true
val releaseStorePath = System.getenv("FITLOOP_RELEASE_STORE_FILE")
val releaseStorePassword = System.getenv("FITLOOP_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = System.getenv("FITLOOP_RELEASE_KEY_ALIAS")
val releaseKeyPassword = System.getenv("FITLOOP_RELEASE_KEY_PASSWORD")
val officialSigningReady = listOf(
    releaseStorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (releaseTaskRequested && !compatibilitySigning && !officialSigningReady) {
    throw GradleException(
        "Official release signing requires FITLOOP_RELEASE_STORE_FILE, " +
            "FITLOOP_RELEASE_STORE_PASSWORD, FITLOOP_RELEASE_KEY_ALIAS, and " +
            "FITLOOP_RELEASE_KEY_PASSWORD. Set FITLOOP_COMPAT_SIGNING=true only " +
            "for the explicitly approved legacy compatibility release.",
    )
}

android {
    namespace = "com.fitloop.fitloop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (officialSigningReady) {
            create("officialRelease") {
                storeFile = file(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    defaultConfig {
        applicationId = "com.fitloop.fitloop"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = when {
                compatibilitySigning -> signingConfigs.getByName("debug")
                officialSigningReady -> signingConfigs.getByName("officialRelease")
                else -> null
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
