#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_ROOT="${DIST_ROOT:-${ROOT_DIR}/dist}"
DIST_DIR="${DIST_DIR:-}"
REPO="${REPO:-}"
TARGET="${TARGET:-}"
DRAFT="${DRAFT:-0}"
PRERELEASE="${PRERELEASE:-0}"
GENERATE_NOTES="${GENERATE_NOTES:-0}"
TAG="${TAG:-}"
TITLE="${TITLE:-}"
NOTES_FILE="${NOTES_FILE:-}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/release/release-github.sh [dist-dir]

Default behavior:
  - picks the latest dist/* directory containing build-info.txt
  - uploads libnode, libc++_shared, build-info, and headers to a GitHub Release
  - derives tag/title/notes from build-info.txt

Optional environment variables:
  DIST_DIR=/root/node-android/dist/node-v24.14.1-arm64-v8a-api32-full-icu
  TAG=v1.0.0
  TITLE='node-android v1.0.0'
  REPO=viocha/node-android
  TARGET=main
  DRAFT=1
  PRERELEASE=1
  GENERATE_NOTES=1
  NOTES_FILE=/path/to/release-notes.md

Examples:
  ./scripts/release/release-github.sh
  TAG=v1.0.1 TITLE='node-android v1.0.1' ./scripts/release/release-github.sh
  DRAFT=1 GENERATE_NOTES=1 ./scripts/release/release-github.sh dist/node-v24.14.1-arm64-v8a-api32-full-icu
EOF
}

log() {
  printf '[RELEASE] %s\n' "$*"
}

die() {
  printf '[RELEASE][ERROR] %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

latest_dist_dir() {
  find "$DIST_ROOT" -mindepth 1 -maxdepth 1 -type d -exec test -f '{}/build-info.txt' ';' -print \
    | sort \
    | tail -n 1
}

resolve_dist_dir() {
  if [[ -z "$DIST_DIR" && $# -gt 0 ]]; then
    DIST_DIR="$1"
  fi

  if [[ -z "$DIST_DIR" ]]; then
    DIST_DIR="$(latest_dist_dir)"
  fi

  [[ -n "$DIST_DIR" ]] || die "failed to find a dist directory"
  [[ -d "$DIST_DIR" ]] || die "dist directory not found: $DIST_DIR"
}

load_build_info() {
  local info_file

  info_file="${DIST_DIR}/build-info.txt"
  [[ -f "$info_file" ]] || die "missing build info: $info_file"

  # shellcheck disable=SC1090
  source "$info_file"

  [[ -n "${NODE_VERSION:-}" ]] || die "build-info.txt is missing NODE_VERSION"
  [[ -n "${ANDROID_ABI:-}" ]] || die "build-info.txt is missing ANDROID_ABI"
  [[ -n "${ANDROID_API:-}" ]] || die "build-info.txt is missing ANDROID_API"
  [[ -n "${ICU_MODE:-}" ]] || die "build-info.txt is missing ICU_MODE"
}

resolve_release_metadata() {
  if [[ -z "$TAG" ]]; then
    TAG="v1.0.0"
  fi

  if [[ -z "$TITLE" ]]; then
    TITLE="node-android ${TAG}"
  fi
}

ensure_assets() {
  local release_prefix headers_name

  release_prefix="node-${NODE_VERSION#v}-android-${ANDROID_ABI}-api${ANDROID_API}-${ICU_MODE}"
  headers_name="node-${NODE_VERSION#v}-headers.tar.gz"

  LIBNODE_PATH="${DIST_ROOT}/${release_prefix}-libnode.so"
  LIBCXX_PATH="${DIST_ROOT}/android-${ANDROID_ABI}-libc++_shared.so"
  BUILD_INFO_PATH="${DIST_ROOT}/${release_prefix}-build-info.txt"
  HEADERS_PATH="${DIST_ROOT}/${headers_name}"

  [[ -f "$LIBNODE_PATH" ]] || die "missing asset: $LIBNODE_PATH"
  [[ -f "$LIBCXX_PATH" ]] || die "missing asset: $LIBCXX_PATH"
  [[ -f "$BUILD_INFO_PATH" ]] || die "missing asset: $BUILD_INFO_PATH"
  [[ -f "$HEADERS_PATH" ]] || die "missing asset: $HEADERS_PATH"
}

ensure_gh_ready() {
  need_cmd gh
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated, run: gh auth login"
}

build_notes_file() {
  local tmp_file commit_sha repo_url

  if [[ -n "$NOTES_FILE" ]]; then
    [[ -f "$NOTES_FILE" ]] || die "notes file not found: $NOTES_FILE"
    RELEASE_NOTES_FILE="$NOTES_FILE"
    return
  fi

  tmp_file="$(mktemp)"
  commit_sha="$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  repo_url="$(git remote get-url origin 2>/dev/null || printf 'unknown')"

  cat > "$tmp_file" <<EOF
Build artifact release for Android.

Node version: ${NODE_VERSION}
Android ABI: ${ANDROID_ABI}
Android API: ${ANDROID_API}
ICU mode: ${ICU_MODE}
NDK release: ${ANDROID_NDK_RELEASE:-unknown}
NDK version: ${ANDROID_NDK_VERSION:-unknown}
Host compiler: ${HOST_CXX:-unknown}
Git commit: ${commit_sha}
Repository: ${repo_url}

Included assets:
- $(basename "$LIBNODE_PATH")
- $(basename "$LIBCXX_PATH")
- $(basename "$BUILD_INFO_PATH")
- $(basename "$HEADERS_PATH")
EOF

  RELEASE_NOTES_FILE="$tmp_file"
}

create_release() {
  local -a cmd

  cmd=(gh release create "$TAG")
  if [[ -n "$REPO" ]]; then
    cmd+=(-R "$REPO")
  fi
  if [[ -n "$TARGET" ]]; then
    cmd+=(--target "$TARGET")
  fi
  if [[ "$DRAFT" == "1" ]]; then
    cmd+=(--draft)
  fi
  if [[ "$PRERELEASE" == "1" ]]; then
    cmd+=(--prerelease)
  fi
  if [[ "$GENERATE_NOTES" == "1" ]]; then
    cmd+=(--generate-notes)
  fi
  if [[ -n "$TITLE" ]]; then
    cmd+=(--title "$TITLE")
  fi
  if [[ -n "$RELEASE_NOTES_FILE" ]]; then
    cmd+=(-F "$RELEASE_NOTES_FILE")
  fi

  cmd+=(
    "$LIBNODE_PATH"
    "$LIBCXX_PATH"
    "$BUILD_INFO_PATH"
    "$HEADERS_PATH"
  )

  log "dist dir   : $DIST_DIR"
  log "tag        : $TAG"
  log "title      : $TITLE"
  log "repo       : ${REPO:-<default>}"
  log "target     : ${TARGET:-<default>}"
  log "draft      : $DRAFT"
  log "prerelease : $PRERELEASE"

  "${cmd[@]}"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
    usage
    exit 0
  fi

  resolve_dist_dir "${1:-}"
  load_build_info
  resolve_release_metadata
  ensure_assets
  ensure_gh_ready
  build_notes_file
  create_release
}

main "$@"
