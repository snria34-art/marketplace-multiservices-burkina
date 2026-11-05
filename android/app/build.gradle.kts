import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.marketplaceburkina.marketplace_multiservices_burkina"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        multiDexEnabled = true
        applicationId = "com.marketplaceburkina.marketplace_multiservices_burkina"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let(::file)
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (!keystorePropertiesFile.isFile) {
                throw GradleException(
                    "Release signing is not configured. Create android/key.properties " +
                        "and provide a protected upload keystore before building a release."
                )
            }

            val requiredSigningProperties = listOf(
                "keyAlias",
                "keyPassword",
                "storeFile",
                "storePassword",
            )
            val missingSigningProperties = requiredSigningProperties.filter {
                keystoreProperties.getProperty(it).isNullOrBlank()
            }
            if (missingSigningProperties.isNotEmpty()) {
                throw GradleException(
                    "Missing Android release signing properties: " +
                        missingSigningProperties.joinToString(", ")
                )
            }

            val releaseKeystore = file(keystoreProperties.getProperty("storeFile"))
            if (!releaseKeystore.isFile) {
                throw GradleException(
                    "Android release keystore does not exist at: ${releaseKeystore.path}"
                )
            }

            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
