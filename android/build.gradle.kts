buildscript {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    dependencies {
        // AGP 9 built-in Kotlin defaults to 2.2.10; Flutter 3.47.2 needs >= 2.2.20.
        // Kotlin Gradle Plugin 2.4.0 is compatible with AGP 9.1 and Gradle 9.x.
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin") {
            version {
                strictly("2.4.0")
            }
        }
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
