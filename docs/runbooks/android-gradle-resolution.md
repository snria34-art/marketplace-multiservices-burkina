# Android Gradle dependency resolution

The Android debug workflow installs a Gradle init script before building. It adds
Maven Central and Google Maven to plugin resolution for the main Android build and
included builds loaded by Flutter.

The Android app uses a conservative toolchain supported by Flutter 3.47.2:
- Android Gradle Plugin 8.11.1
- Gradle 8.14
- Kotlin Gradle Plugin 2.2.20

KGP 2.2.20 satisfies Flutter 3.47.2's minimum version and is compatible with
AGP 8.11.1 and Gradle 8.14. The app explicitly applies
`org.jetbrains.kotlin.android`; this avoids the lower built-in Kotlin version
bundled by AGP 9 in this Flutter release.

For a local Android build, run:

```bash
bash scripts/prepare-android-gradle.sh
flutter pub get --enforce-lockfile
flutter build apk --debug
```

The init script is installed in the user's Gradle home under `init.d`; it does
not change project dependencies, lockfiles, signing configuration, or release
build behavior.

Release builds remain protected by the existing Android signing checks. The
debug workflow creates an unsigned debug APK only.
