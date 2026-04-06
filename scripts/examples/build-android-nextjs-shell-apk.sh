#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="${ROOT_DIR}/example/android-nextjs-shell"
APK_PATH="${APP_DIR}/app/build/outputs/apk/debug/app-debug.apk"
RELEASE_APK_PATH="${APP_DIR}/app/build/outputs/apk/release/app-release.apk"
GRADLE_BIN="${APP_DIR}/gradlew"
ASSET_SCRIPT="${ROOT_DIR}/scripts/examples/build-nextjs-assets.sh"
DIST_LIBNODE="${ROOT_DIR}/dist/node-v24.14.1-arm64-v8a-api32-full-icu/libnode.so"
NDK_ROOT="${ANDROID_NDK_ROOT:-/opt/android/ndk}"
APP_LIB_DIR="${APP_DIR}/app/src/main/jniLibs/arm64-v8a"
APP_LIBNODE="${APP_LIB_DIR}/libnode.so"
NDK_LIBCXX="${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
APP_LIBCXX="${APP_LIB_DIR}/libc++_shared.so"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/examples/build-android-nextjs-shell-apk.sh
  ./scripts/examples/build-android-nextjs-shell-apk.sh --release

What it does:
  1. builds the Next.js standalone asset bundle
  2. copies libnode.so and libc++_shared.so into jniLibs
  3. builds the requested APK variant
  4. prints the APK path
EOF
}

die() {
  printf '[NEXTJS-SHELL][ERROR] %s\n' "$*" >&2
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
  usage
  exit 0
fi

BUILD_VARIANT="debug"
GRADLE_TASK="assembleDebug"
TARGET_APK_PATH="$APK_PATH"

if [[ "${1:-}" == "--release" ]]; then
  BUILD_VARIANT="release"
  GRADLE_TASK="assembleRelease"
  TARGET_APK_PATH="$RELEASE_APK_PATH"
fi

[[ -x "$GRADLE_BIN" ]] || die "missing gradle wrapper: $GRADLE_BIN"
[[ -x "$ASSET_SCRIPT" ]] || die "missing asset build script: $ASSET_SCRIPT"
[[ -f "$DIST_LIBNODE" ]] || die "missing libnode.so: $DIST_LIBNODE"
[[ -f "$NDK_LIBCXX" ]] || die "missing libc++_shared.so from NDK: $NDK_LIBCXX"

"$ASSET_SCRIPT"

mkdir -p "$APP_LIB_DIR"
cp -f "$DIST_LIBNODE" "$APP_LIBNODE"
cp -f "$NDK_LIBCXX" "$APP_LIBCXX"

(
  cd "$APP_DIR"
  ANDROID_HOME=/opt/android ANDROID_SDK_ROOT=/opt/android "$GRADLE_BIN" "$GRADLE_TASK"
)

[[ -f "$TARGET_APK_PATH" ]] || die "APK not found: $TARGET_APK_PATH"
printf '[NEXTJS-SHELL] variant: %s\n' "$BUILD_VARIANT"
printf '[NEXTJS-SHELL] apk: %s\n' "$TARGET_APK_PATH"
