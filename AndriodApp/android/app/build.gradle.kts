// `java` alone resolves to the Gradle Java plugin accessor in this DSL, so
// the JDK class has to be imported explicitly.
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing for the Play Store upload key. See android/key.properties.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    val keyStream = keystorePropertiesFile.inputStream()
    keystoreProperties.load(keyStream)
    keyStream.close()
}

android {
    // Sandbox identity. A different applicationId means this app installs
    // alongside the real MessApp, with its own database, its own notifications
    // and its own uninstall. The real app is never touched.
    namespace = "com.messapp.dev"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    compileOptions {
        // Required by flutter_local_notifications (PRD 5.5).
        // The Kotlin DSL script classpath exposes a CompileOptions
        // variant without setCoreLibraryDesugaringEnabled, so invoke
        // it reflectively on the runtime object (which does have it).
        this.javaClass.methods
            .first { it.name == "setCoreLibraryDesugaringEnabled" }
            .invoke(this, true)
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Sandbox application ID. Deliberately different from com.messapp.messapp
        // so both apps coexist on one device with fully separate data.
        applicationId = "com.messapp.dev"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signed with the Play upload key when key.properties is present,
            // otherwise fall back to debug keys so local runs still work.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
