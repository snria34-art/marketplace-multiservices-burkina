# Android Gradle dependency resolution

The Android debug workflow installs a Gradle init script before building. It adds
Maven Central and Google Maven to plugin resolution for the main Android build and
included builds loaded by Flutter.

For a local Android build, run this once in the repository:

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
