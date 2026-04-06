# Android Verify Example

This example embeds the repository's Android `libnode.so` into a small
Compose app and exposes a few real Node.js actions from the UI.

## What it demonstrates

- runtime verification on app startup
- start, request, and stop a live Node HTTP server
- `crypto`
- `zlib`
- `fs`
- `Intl` with full ICU
- `URL`
- `timers/promises`

## Usage

1. Open the app.
2. The `Overview` page runs a startup verification pass through the embedded
   Node runtime.
3. Switch to `Playground` and run the interactive examples.

The app package name is:

```text
com.viocha.nodeverify
```

## Build prerequisites

This example expects the repository's Android `libnode.so` to already exist at:

```text
dist/node-v24.14.1-arm64-v8a-api32-full-icu/libnode.so
```

If you have not built it yet, from the repo root run:

```bash
./scripts/build/build-node-android.sh build
```

The example source tree does not commit `libnode.so` or `libc++_shared.so`.
The build helper copies:

- `libnode.so` from `dist/`
- `libc++_shared.so` from the configured Android NDK

into the app's `jniLibs` directory before running Gradle.

## Build the example APK

From the repo root:

```bash
./scripts/examples/build-android-verify-apk.sh
./scripts/examples/build-android-verify-apk.sh --release
```

Manual Gradle build:

```bash
cd example/android-verify
ANDROID_HOME=/opt/android ANDROID_SDK_ROOT=/opt/android ./gradlew assembleDebug
ANDROID_HOME=/opt/android ANDROID_SDK_ROOT=/opt/android ./gradlew assembleRelease
```

APK output:

```text
example/android-verify/app/build/outputs/apk/debug/app-debug.apk
example/android-verify/app/build/outputs/apk/release/app-release.apk
```

## Install

After copying the APK to a machine with `adb`:

```bash
adb install -r example/android-verify/app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.viocha.nodeverify/.MainActivity
```
