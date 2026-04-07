# Android Next.js Shell Example

This example packages a real full-stack Next.js app inside a native Android shell.
The bundled app is `FocusBoard`, a compact task manager with local persistence.

What happens at runtime:

1. The Android app extracts a prebuilt Next.js standalone bundle from assets.
2. The app starts the embedded Node.js runtime from `libnode.so`.
3. Node launches the bundled Next.js production server inside the app process.
4. A small internal proxy exposes the app through a private origin: `http://focusboard.invalid/`.
5. A native `WebView` opens that private origin full-screen.

## What the app demonstrates

- App Router
- server-rendered page content
- API routes backed by the embedded Next.js server
- create/read/update/delete task flows from the WebView client
- filesystem-backed persistence inside app storage

The app includes:

- `GET /api/health`
- `GET /api/tasks`
- `POST /api/tasks`
- `PATCH /api/tasks`
- `DELETE /api/tasks`

## Build prerequisites

This example does not require a local `libnode.so` build.
The helper script resolves the latest core release tag and downloads:

- `node-v24.14.1-android-arm64-v8a-api32-full-icu-libnode.so`
- `android-arm64-v8a-libc++_shared.so`
- `node-v24.14.1-headers.tar.gz`

from:

```text
https://github.com/viocha/node-android/releases/tag/v1.0.0
```

## Build the standalone Next.js asset bundle

From the repo root:

```bash
./scripts/examples/build-nextjs-assets.sh
```

This script:

- installs Next.js dependencies with `pnpm`
- runs `next build`
- assembles the standalone output
- writes:
  - `app/src/main/assets/nextjs-app.zip`
  - `app/src/main/assets/nextjs-app.version`

This example keeps its `pnpm` registry and linker settings in the project
itself:

```text
example/android-nextjs-shell/next-app/.npmrc
```

Current settings used by this example:

```text
registry=https://registry.npmmirror.com/
node-linker=hoisted
```

`node-linker=hoisted` is important here. The default `pnpm` layout can produce a
Next.js standalone bundle that is valid on disk but incomplete after Android
asset packaging, which breaks runtime module resolution inside the embedded app.

Those generated asset files are not committed to git.

## Build the Android APK

From the repo root:

```bash
./scripts/examples/build-android-nextjs-shell-apk.sh
./scripts/examples/build-android-nextjs-shell-apk.sh --release
```

This script:

- builds the Next.js asset bundle
- downloads `libnode.so`
- downloads `libc++_shared.so`
- runs Gradle

Downloaded assets are cached in:

```text
.cache/downloads/
```

The Node headers archive is extracted into:

```text
.work/node-v24.14.1/
```

You can pin a specific release tag if needed:

```bash
RELEASE_TAG=v1.0.0 ./scripts/examples/build-android-nextjs-shell-apk.sh
```

APK output:

```text
example/android-nextjs-shell/app/build/outputs/apk/debug/app-debug.apk
example/android-nextjs-shell/app/build/outputs/apk/release/app-release.apk
```

## Install

```bash
adb install -r example/android-nextjs-shell/app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.viocha.nextshell/.MainActivity
```
