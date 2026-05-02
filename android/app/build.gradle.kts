import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load signing credentials from android/key.properties (not committed to git).
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.nudgr.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_1_8.toString()
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"] as String? ?: ""
            keyPassword = keyProperties["keyPassword"] as String? ?: ""
            storeFile = keyProperties["storeFile"]?.let { file(it as String) }
            storePassword = keyProperties["storePassword"] as String? ?: ""
        }
    }

    defaultConfig {
        applicationId = "com.nudgr.app"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            // Strip non-arm64 native libs from plugin AARs for release only
            // (e.g. flutter_gemma ships pre-built x86_64 libs that add ~53 MB).
            // Debug builds keep x86_64 for emulator support.
        }
    }

    buildTypes {
        debug {
            ndk {
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
        release {
            signingConfig = if (keyPropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            isMinifyEnabled = true
            isShrinkResources = true
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
            packaging {
                jniLibs {
                    excludes += setOf("lib/x86_64/**", "lib/x86/**", "lib/armeabi-v7a/**")
                }
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
