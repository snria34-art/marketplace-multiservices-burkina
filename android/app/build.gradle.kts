import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val requiredSigningProperties = listOf(
    "keyAlias",
    "keyPassword",
    "storeFile",
    "storePassword",
)

fun validateReleaseSigningConfiguration() {
    if (!keystorePropertiesFile.isFile) {
        throw GradleException(
            "Release signing is not configured. Create android/key.properties " +
                "and provide a protected upload keystore before building a release."
        )
    }

    val missingSigningProperties = requiredSigningProperties.filter {
        keystoreProperties.getProperty(it).isNullOrBlank()
    }
    if (missingSigningProperties.isNotEmpty()) {
        throw GradleException(
            "Missing Android release signing properties: " +
                missingSigningProperties.joinToString(", ")
        )
    }

    val releaseKeystore = project.file(keystoreProperties.getProperty("storeFile"))
    if (!releaseKeystore.isFile) {
        throw GradleException(
            "Android release keystore does not exist at: ${releaseKeystore.path}"
        )
    }
}

// Validate signing from the requested task names. Android evaluates every build
// type during configuration, including Debug; a guard inside buildTypes.release
// would therefore incorrectly block an unsigned Debug build.
val requestedGradleTasks = gradle.startParameter.taskNames.map { taskName ->
    taskName.substringAfterLast(':').lowercase()
}
val releasePackagingRequested = requestedGradleTasks.any { taskName ->
    taskName in setOf("build", "assemble", "bundle") ||
        (taskName.contains("release") &&
            (taskName.startsWith("assemble") ||
                taskName.startsWith("bundle") ||
                taskName.startsWith("package")))
}
if (releasePackagingRequested) {
    validateReleaseSigningConfiguration()
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
        if (keystorePropertiesFile.isFile) {
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
            // Debug builds do not need a release keystore. Release packaging is
            // blocked by validateReleaseSigningConfiguration() when credentials
            // are missing or incomplete.
            if (keystorePropertiesFile.isFile) {
                signingConfig = signingConfigs.getByName("release")
            }
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
