# Android Gradle dependency resolution

The Android debug workflow installs a Gradle init script before building. It adds
Maven Central and Google Maven to plugin resolution for the main Android build and
included builds loaded by Flutter.

The Android app uses AGP 9.1.0 with the Kotlin Gradle Plugin pinned to 2.4.0 in
`settings.gradle.kts`. AGP 9's built-in Kotlin mode is disabled temporarily
(`android.builtInKotlin=false`) so Flutter 3.47.2 and Android plugins that still
apply KGP use the same explicitly declared version. This is a compatibility
configuration, not a bypass of Flutter's dependency validation.

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
