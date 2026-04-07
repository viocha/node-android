#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="${ROOT_DIR}/example/android-verify"
APK_PATH="${APP_DIR}/app/build/outputs/apk/debug/app-debug.apk"
RELEASE_APK_PATH="${APP_DIR}/app/build/outputs/apk/release/app-release.apk"
GRADLE_BIN="${APP_DIR}/gradlew"
RELEASE_REPO="${RELEASE_REPO:-viocha/node-android}"
RELEASE_TAG="${RELEASE_TAG:-}"
LIBNODE_ASSET="${LIBNODE_ASSET:-node-v24.14.1-android-arm64-v8a-api32-full-icu-libnode.so}"
LIBCXX_ASSET="${LIBCXX_ASSET:-android-arm64-v8a-libc++_shared.so}"
HEADERS_ASSET="${HEADERS_ASSET:-node-v24.14.1-headers.tar.gz}"
CACHE_DIR="${ROOT_DIR}/.cache/downloads"
WORK_DIR="${ROOT_DIR}/.work"
APP_LIB_DIR="${APP_DIR}/app/src/main/jniLibs/arm64-v8a"
APP_LIBNODE="${APP_LIB_DIR}/libnode.so"
APP_LIBCXX="${APP_LIB_DIR}/libc++_shared.so"
LIBNODE_CACHE_PATH="${CACHE_DIR}/${LIBNODE_ASSET}"
LIBCXX_CACHE_PATH="${CACHE_DIR}/${LIBCXX_ASSET}"
HEADERS_CACHE_PATH="${CACHE_DIR}/${HEADERS_ASSET}"
HEADERS_DIR="${WORK_DIR}/node-v24.14.1"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/examples/build-android-verify-apk.sh
  ./scripts/examples/build-android-verify-apk.sh --release

What it does:
  1. downloads libnode.so, libc++_shared.so, and Node headers from GitHub release assets
  2. extracts the Node headers into .work/
  3. builds the requested APK variant
  4. prints the APK path
EOF
}

die() {
  printf '[ANDROID-VERIFY][ERROR] %s\n' "$*" >&2
  exit 1
}

resolve_release_tag() {
  if [[ -n "$RELEASE_TAG" ]]; then
    return
  fi

  if command -v gh >/dev/null 2>&1; then
    RELEASE_TAG="$(gh api "repos/${RELEASE_REPO}/releases/latest" --jq '.tag_name' 2>/dev/null || true)"
  fi

  if [[ -z "$RELEASE_TAG" ]]; then
    RELEASE_TAG="$(curl -fsSL "https://api.github.com/repos/${RELEASE_REPO}/releases/latest" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  fi

  [[ -n "$RELEASE_TAG" ]] || die "failed to resolve latest release tag for ${RELEASE_REPO}"
}

download_if_missing() {
  local url="$1"
  local target_path="$2"

  if [[ -f "$target_path" ]]; then
    return
  fi

  mkdir -p "$(dirname "$target_path")"
  printf '[ANDROID-VERIFY] download: %s\n' "$url"
  curl -fL "$url" -o "${target_path}.part" || die "download failed: $url"
  mv -f "${target_path}.part" "$target_path"
}

extract_headers_if_needed() {
  if [[ -f "${HEADERS_DIR}/include/node/node.h" ]]; then
    return
  fi

  mkdir -p "$WORK_DIR"
  rm -rf "$HEADERS_DIR"
  printf '[ANDROID-VERIFY] extract: %s -> %s\n' "$HEADERS_CACHE_PATH" "$WORK_DIR"
  tar -xzf "$HEADERS_CACHE_PATH" -C "$WORK_DIR"
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
resolve_release_tag

download_if_missing \
  "https://github.com/${RELEASE_REPO}/releases/download/${RELEASE_TAG}/${LIBNODE_ASSET}" \
  "$LIBNODE_CACHE_PATH"
download_if_missing \
  "https://github.com/${RELEASE_REPO}/releases/download/${RELEASE_TAG}/${LIBCXX_ASSET}" \
  "$LIBCXX_CACHE_PATH"
download_if_missing \
  "https://github.com/${RELEASE_REPO}/releases/download/${RELEASE_TAG}/${HEADERS_ASSET}" \
  "$HEADERS_CACHE_PATH"

extract_headers_if_needed

mkdir -p "$APP_LIB_DIR"
cp -f "$LIBNODE_CACHE_PATH" "$APP_LIBNODE"
cp -f "$LIBCXX_CACHE_PATH" "$APP_LIBCXX"

(
  cd "$APP_DIR"
  ANDROID_HOME=/opt/android ANDROID_SDK_ROOT=/opt/android "$GRADLE_BIN" "$GRADLE_TASK"
)

[[ -f "$TARGET_APK_PATH" ]] || die "APK not found: $TARGET_APK_PATH"
printf '[ANDROID-VERIFY] release_tag: %s\n' "$RELEASE_TAG"
printf '[ANDROID-VERIFY] variant: %s\n' "$BUILD_VARIANT"
printf '[ANDROID-VERIFY] apk: %s\n' "$TARGET_APK_PATH"
