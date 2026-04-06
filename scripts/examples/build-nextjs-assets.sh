#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXAMPLE_DIR="${ROOT_DIR}/example/android-nextjs-shell"
NEXT_APP_DIR="${EXAMPLE_DIR}/next-app"
ASSET_DIR="${EXAMPLE_DIR}/app/src/main/assets"
BUNDLE_DIR="${EXAMPLE_DIR}/.bundle/nextjs-app"
LOCAL_NODE_BIN="${ROOT_DIR}/.cache/tools/node-v24.14.1-linux-x64/bin"
LOCAL_PNPM_BIN="${ROOT_DIR}/.cache/tools/pnpm-10.33.0/bin"

die() {
  printf '[NEXTJS-ASSETS][ERROR] %s\n' "$*" >&2
  exit 1
}

if [[ -d "$LOCAL_NODE_BIN" ]]; then
  export PATH="$LOCAL_NODE_BIN:$PATH"
fi
if [[ -d "$LOCAL_PNPM_BIN" ]]; then
  export PATH="$LOCAL_PNPM_BIN:$PATH"
fi

command -v node >/dev/null 2>&1 || die "missing host node runtime"
command -v pnpm >/dev/null 2>&1 || die "missing pnpm"
command -v zip >/dev/null 2>&1 || die "missing zip"

mkdir -p "$ASSET_DIR"

(
  cd "$NEXT_APP_DIR"
  if [[ -f pnpm-lock.yaml ]]; then
    pnpm install --frozen-lockfile
  else
    pnpm install
  fi
  pnpm run build
)

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/.next"

cp -a "${NEXT_APP_DIR}/.next/standalone/." "$BUNDLE_DIR/"
cp -a "${NEXT_APP_DIR}/.next/static" "${BUNDLE_DIR}/.next/"
if [[ -d "${NEXT_APP_DIR}/public" ]]; then
  cp -a "${NEXT_APP_DIR}/public" "$BUNDLE_DIR/"
fi

printf '%s\n' "$(cat "${NEXT_APP_DIR}/.next/BUILD_ID")" > "${ASSET_DIR}/nextjs-app.version"
rm -f "${ASSET_DIR}/nextjs-app.zip"
(
  cd "$BUNDLE_DIR"
  zip -qr "${ASSET_DIR}/nextjs-app.zip" .
)

printf '[NEXTJS-ASSETS] asset_zip: %s\n' "${ASSET_DIR}/nextjs-app.zip"
printf '[NEXTJS-ASSETS] version: %s\n' "${ASSET_DIR}/nextjs-app.version"
