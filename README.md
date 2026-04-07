# node-android

Build Node.js 24 as an Android shared library for:

- ABI: `arm64-v8a`
- API: `32`
- ICU: `full-icu`

This repository produces a usable Android `libnode.so`, plus Android example
apps that show how to embed it on device.

## Output

The main build output is:

```text
dist/node-v24.14.1-arm64-v8a-api32-full-icu/libnode.so
```

Build metadata is written to:

```text
dist/node-v24.14.1-arm64-v8a-api32-full-icu/build-info.txt
```

## Build Environment

On a fresh Ubuntu x86_64 machine, set up the toolchain with:

```bash
sudo ./scripts/env/setup-node-android-build-env.sh
source /etc/profile.d/node-android-env.sh
```

That installs and configures the environment used by this repository,
including:

- LLVM/Clang 20
- OpenJDK 21
- Android NDK r29
- zellij

## Build `libnode.so`

Build in the foreground:

```bash
./scripts/build/build-node-android.sh build
```

The script defaults to:

- Node.js `24.x`
- `arm64-v8a`
- API `32`
- `full-icu`

Useful overrides:

```bash
NODE_VERSION=v24.14.1 BUILD_JOBS=16 ./scripts/build/build-node-android.sh build
```

Other supported actions:

```bash
./scripts/build/build-node-android.sh setup
./scripts/build/build-node-android.sh clean
```

## Background Build

If you want the build to keep running after SSH disconnects:

```bash
./node-android-build-control.sh start
./node-android-build-control.sh status
./node-android-build-control.sh logs
./node-android-build-control.sh attach
./node-android-build-control.sh stop
```

This wrapper runs the build inside `zellij`, writes logs to `logs/`, and
supports optional email notification through environment variables.

## Using the Built Artifact

For Android app integration, the runtime pieces you need are:

- `libnode.so` from `dist/...`
- `libc++_shared.so` from the Android NDK

For `arm64-v8a`, the NDK runtime library is typically:

```text
/opt/android/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so
```

Place both files in your app's native library packaging path, for example:

```text
app/src/main/jniLibs/arm64-v8a/
```

At load time, make sure `c++_shared` is loaded before your JNI bridge:

```kotlin
companion object {
    init {
        System.loadLibrary("c++_shared")
        System.loadLibrary("nodeverify")
    }
}
```

This repository's working embedder example uses Node's official embedder APIs
from C++, instead of repeatedly calling the CLI-style `node::Start()`.

## Example Apps

Two working Android examples are included:

- [`example/android-verify`](./example/android-verify)
  - a Compose-based native verification app for `fs`, `crypto`, `zlib`, `Intl`, `URL`, and timers
- [`example/android-nextjs-shell`](./example/android-nextjs-shell)
  - a native Android shell that boots a bundled full-stack Next.js app inside WebView
  - the embedded Next.js app uses `pnpm`

Build the native verification example:

```bash
./scripts/examples/build-android-verify-apk.sh
./scripts/examples/build-android-verify-apk.sh --release
```

Build the Next.js shell example:

```bash
./scripts/examples/build-android-nextjs-shell-apk.sh
./scripts/examples/build-android-nextjs-shell-apk.sh --release
```

The Next.js example keeps its `pnpm` settings inside the example project:

```text
example/android-nextjs-shell/next-app/.npmrc
```

When using `pnpm` with the Next.js example, configure:

```text
registry=https://registry.npmmirror.com/
node-linker=hoisted
```

APK outputs:

```text
example/android-verify/app/build/outputs/apk/debug/app-debug.apk
example/android-verify/app/build/outputs/apk/release/app-release.apk
example/android-nextjs-shell/app/build/outputs/apk/debug/app-debug.apk
example/android-nextjs-shell/app/build/outputs/apk/release/app-release.apk
```

Both helper scripts automatically resolve the latest core release tag and download:

- `node-v24.14.1-android-arm64-v8a-api32-full-icu-libnode.so`
- `android-arm64-v8a-libc++_shared.so`
- `node-v24.14.1-headers.tar.gz`

from the configured GitHub release. Downloaded assets are cached in
`.cache/downloads/`; the shared libraries are copied into the target example
app and the headers archive is extracted into `.work/` before running Gradle.

## Release Assets

The core GitHub release for this repository ships:

- `node-v24.14.1-android-arm64-v8a-api32-full-icu-libnode.so`
- `android-arm64-v8a-libc++_shared.so`
- `node-v24.14.1-android-arm64-v8a-api32-full-icu-build-info.txt`
- `node-v24.14.1-headers.tar.gz`

If you want to publish a new release from the current repo state:

```bash
./scripts/release/release-github.sh
```

You can override the resolved core release tag when needed:

```bash
RELEASE_TAG=v1.0.0 ./scripts/examples/build-android-verify-apk.sh
RELEASE_TAG=v1.0.0 ./scripts/examples/build-android-nextjs-shell-apk.sh
```
