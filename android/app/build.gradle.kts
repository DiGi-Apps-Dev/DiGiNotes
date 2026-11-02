import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.digiapps.diginotes"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.digiapps.diginotes"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 10: da li il pacchetto record scrive Opus.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Chiave di firma: android/key.properties, mai nel repository. Senza quel file si firma con la chiave di debug di Flutter.
    val keyProps = Properties()
    val keyFile = rootProject.file("key.properties")
    if (keyFile.exists()) keyFile.inputStream().use { keyProps.load(it) }
    else logger.warn("Manca android/key.properties: si firma con la chiave di debug")

    signingConfigs {
        if (keyFile.exists()) create("release") {
            keyAlias = keyProps.getProperty("keyAlias")
            keyPassword = keyProps.getProperty("keyPassword")
            storeFile = keyProps.getProperty("storeFile")?.let { rootProject.file(it) }
            storePassword = keyProps.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
