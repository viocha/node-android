#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

NODE_MAJOR="${NODE_MAJOR:-24}"
NODE_VERSION="${NODE_VERSION:-}"
NODE_VERSION_FALLBACK="${NODE_VERSION_FALLBACK:-v24.14.1}"

ANDROID_API="${ANDROID_API:-32}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_ARCH="${ANDROID_ARCH:-arm64}"
ICU_MODE="${ICU_MODE:-full-icu}"

ANDROID_NDK_RELEASE="${ANDROID_NDK_RELEASE:-r29}"
ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-29.0.14206865}"
ANDROID_NDK_SHA1="${ANDROID_NDK_SHA1:-87e2bb7e9be5d6a1c6cdf5ec40dd4e0c6d07c30b}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"

WORK_ROOT="${WORK_ROOT:-$ROOT_DIR/.work}"
CACHE_ROOT="${CACHE_ROOT:-$ROOT_DIR/.cache}"
DIST_ROOT="${DIST_ROOT:-$ROOT_DIR/dist}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"

TARGET_TRIPLE=""
TARGET_CC=""
TARGET_CXX=""
TARGET_AR=""
TARGET_LD=""
TARGET_NM=""
TARGET_RANLIB=""
TARGET_READELF=""
TARGET_STRIP=""
HOST_CC=""
HOST_CXX=""
HOST_AR=""
HOST_NM=""
HOST_RANLIB=""
SOURCE_TARBALL=""
BUILD_DIR=""
NODE_DIST_DIR=""
NODE_SOURCE_DIR=""

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build/build-node-android.sh [build|setup|clean]

Default action:
  build

What it builds:
  Node.js 24 -> Android libnode.so
  ABI      : arm64-v8a
  API      : 32
  ICU      : full-icu

Useful environment overrides:
  NODE_VERSION=v24.14.1
  BUILD_JOBS=16
  ANDROID_API=32
  ANDROID_NDK_HOME=/opt/android/ndk
  WORK_ROOT=/data/node-android/work
  CACHE_ROOT=/data/node-android/cache
  DIST_ROOT=/data/node-android/dist

Examples:
  ./scripts/build/build-node-android.sh
  NODE_VERSION=v24.14.1 BUILD_JOBS=32 ./scripts/build/build-node-android.sh build
  ./scripts/build/build-node-android.sh setup
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

ensure_prereqs() {
  local cmds=(
    curl git jq make python3 tar xz unzip sha1sum file patch
  )
  local cmd
  for cmd in "${cmds[@]}"; do
    need_cmd "$cmd"
  done
}

normalize_config() {
  case "$ANDROID_ABI" in
    arm64-v8a)
      ANDROID_ARCH="arm64"
      TARGET_TRIPLE="aarch64-linux-android"
      ;;
    *)
      die "only ANDROID_ABI=arm64-v8a is supported by this script right now"
      ;;
  esac

  [[ "$ANDROID_API" == "32" ]] || warn "this script is tuned for API 32; current ANDROID_API=$ANDROID_API"
  [[ "$ICU_MODE" == "full-icu" ]] || die "only ICU_MODE=full-icu is supported"
}

pick_host_toolchain() {
  local version
  for version in 20 19 18 17; do
    if command -v "clang-$version" >/dev/null 2>&1 && command -v "clang++-$version" >/dev/null 2>&1; then
      HOST_CC="$(command -v "clang-$version")"
      HOST_CXX="$(command -v "clang++-$version")"
      HOST_AR="$(command -v "llvm-ar-$version" || command -v llvm-ar)"
      HOST_NM="$(command -v "llvm-nm-$version" || command -v llvm-nm || command -v nm)"
      HOST_RANLIB="$(command -v "llvm-ranlib-$version" || command -v llvm-ranlib || command -v ranlib)"
      break
    fi
  done

  if [[ -z "$HOST_CC" || -z "$HOST_CXX" ]]; then
    if command -v clang >/dev/null 2>&1 && command -v clang++ >/dev/null 2>&1; then
      HOST_CC="$(command -v clang)"
      HOST_CXX="$(command -v clang++)"
      HOST_AR="$(command -v llvm-ar || command -v ar)"
      HOST_NM="$(command -v llvm-nm || command -v nm)"
      HOST_RANLIB="$(command -v llvm-ranlib || command -v ranlib)"
    fi
  fi

  [[ -n "$HOST_CC" && -n "$HOST_CXX" ]] || die "unable to find a usable host clang toolchain"
  [[ -n "$HOST_AR" && -n "$HOST_NM" && -n "$HOST_RANLIB" ]] || die "unable to find host llvm binutils"
}

select_ndk_home() {
  local preferred_ndk="/opt/android/ndk"
  local ambient_ndk="$ANDROID_NDK_HOME"

  if [[ -d "${preferred_ndk}/toolchains/llvm/prebuilt/linux-x86_64/bin" ]]; then
    if [[ -n "$ambient_ndk" && "$ambient_ndk" != "$preferred_ndk" ]]; then
      warn "ignoring ambient ANDROID_NDK_HOME=${ambient_ndk}; using preferred ${preferred_ndk}"
    fi
    ANDROID_NDK_HOME="$preferred_ndk"
    return
  fi

  if [[ -z "$ANDROID_NDK_HOME" ]]; then
    ANDROID_NDK_HOME="$preferred_ndk"
  fi
}

resolve_node_version() {
  if [[ -n "$NODE_VERSION" ]]; then
    [[ "$NODE_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "NODE_VERSION must look like v24.14.1"
    return
  fi

  if NODE_VERSION="$(
    curl -fsSL https://nodejs.org/dist/index.json |
      jq -r --arg major "v${NODE_MAJOR}." '[.[] | select(.version | startswith($major))][0].version'
  )" && [[ "$NODE_VERSION" != "null" && -n "$NODE_VERSION" ]]; then
    return
  fi

  warn "failed to resolve latest Node.js ${NODE_MAJOR}.x from nodejs.org; falling back to ${NODE_VERSION_FALLBACK}"
  NODE_VERSION="$NODE_VERSION_FALLBACK"
}

ensure_ndk() {
  if [[ -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin" ]]; then
    return
  fi

  local ndk_root ndk_zip ndk_dir

  ndk_root="/opt/android"
  ndk_zip="${ndk_root}/android-ndk-${ANDROID_NDK_RELEASE}-linux.zip"
  ndk_dir="${ndk_root}/android-ndk-${ANDROID_NDK_RELEASE}"

  mkdir -p "$ndk_root"

  if [[ ! -d "$ndk_dir" ]]; then
    log "downloading Android NDK ${ANDROID_NDK_RELEASE} (${ANDROID_NDK_VERSION})"
    rm -f "$ndk_zip"
    curl -fL --retry 3 --retry-all-errors \
      "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_RELEASE}-linux.zip" \
      -o "$ndk_zip"
    echo "${ANDROID_NDK_SHA1}  ${ndk_zip}" | sha1sum -c -
    unzip -q "$ndk_zip" -d "$ndk_root"
  fi

  ln -sfn "$ndk_dir" "${ndk_root}/ndk"
  ANDROID_NDK_HOME="${ndk_root}/ndk"
}

prepare_target_toolchain() {
  local toolchain

  toolchain="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64"
  [[ -d "$toolchain/bin" ]] || die "invalid Android NDK: $ANDROID_NDK_HOME"

  TARGET_CC="${toolchain}/bin/${TARGET_TRIPLE}${ANDROID_API}-clang"
  TARGET_CXX="${toolchain}/bin/${TARGET_TRIPLE}${ANDROID_API}-clang++"
  TARGET_AR="${toolchain}/bin/llvm-ar"
  TARGET_LD="${toolchain}/bin/ld.lld"
  TARGET_NM="${toolchain}/bin/llvm-nm"
  TARGET_RANLIB="${toolchain}/bin/llvm-ranlib"
  TARGET_READELF="${toolchain}/bin/llvm-readelf"
  TARGET_STRIP="${toolchain}/bin/llvm-strip"

  [[ -x "$TARGET_CC" && -x "$TARGET_CXX" ]] || die "missing Android clang toolchain in $toolchain"
}

download_node_source() {
  mkdir -p "$CACHE_ROOT/downloads"
  SOURCE_TARBALL="${CACHE_ROOT}/downloads/node-${NODE_VERSION}.tar.xz"

  if [[ ! -f "$SOURCE_TARBALL" ]]; then
    log "downloading ${NODE_VERSION} source tarball"
    curl -fL --retry 3 --retry-all-errors \
      "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}.tar.xz" \
      -o "$SOURCE_TARBALL"
  fi
}

prepare_build_tree() {
  local work_name

  work_name="node-${NODE_VERSION}-${ANDROID_ABI}-api${ANDROID_API}-${ICU_MODE}"
  BUILD_DIR="${WORK_ROOT}/${work_name}"
  NODE_DIST_DIR="${DIST_ROOT}/${work_name}"

  rm -rf "$BUILD_DIR" "${WORK_ROOT}/node-${NODE_VERSION}"
  mkdir -p "$WORK_ROOT" "$DIST_ROOT"
  tar -xJf "$SOURCE_TARBALL" -C "$WORK_ROOT"

  NODE_SOURCE_DIR="${WORK_ROOT}/node-${NODE_VERSION}"
  [[ -d "$NODE_SOURCE_DIR" ]] || die "failed to unpack node-${NODE_VERSION}"

  if [[ "$NODE_SOURCE_DIR" != "$BUILD_DIR" ]]; then
    rm -rf "$BUILD_DIR"
    mv "$NODE_SOURCE_DIR" "$BUILD_DIR"
    NODE_SOURCE_DIR="$BUILD_DIR"
  fi
}

apply_android_patches() {
  local trap_handler_file
  local -a zlib_cpu_features_files

  trap_handler_file="${NODE_SOURCE_DIR}/deps/v8/src/trap-handler/trap-handler.h"
  zlib_cpu_features_files=(
    "${NODE_SOURCE_DIR}/deps/v8/third_party/zlib/cpu_features.c"
    "${NODE_SOURCE_DIR}/deps/zlib/cpu_features.c"
  )

  [[ -f "$trap_handler_file" ]] || die "missing expected file: ${trap_handler_file}"
  for zlib_cpu_features_file in "${zlib_cpu_features_files[@]}"; do
    [[ -f "$zlib_cpu_features_file" ]] || die "missing expected file: ${zlib_cpu_features_file}"
  done

  # Node 24's bundled Android patch no longer matches upstream V8 exactly.
  # Rewrite the trap-handler support block directly so host mksnapshot does not
  # keep Android/simulator-only references alive during cross builds.
  log "forcing Android-specific V8 trap-handler disable patch"
  python3 - "$trap_handler_file" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
pattern = re.compile(
    r'(namespace v8::internal::trap_handler \{\n\n)'
    r'(?:// X64 on Linux, Windows, MacOS, FreeBSD\.\n.*?#endif\n\n)'
    r'(#if V8_OS_ANDROID && V8_TRAP_HANDLER_SUPPORTED\n)',
    re.S,
)
replacement = (
    r'\1'
    r'#define V8_TRAP_HANDLER_SUPPORTED false\n\n'
    r'\2'
)
new_text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit('failed to rewrite V8 trap-handler support block')
path.write_text(new_text)
PY

  if sed -n '1,80p' "$trap_handler_file" | grep -q '^#if V8_HOST_ARCH_X64'; then
    die "Android V8 trap-handler patch verification failed: stale support block still present"
  fi

  sed -n '1,80p' "$trap_handler_file" | grep -q '^#define V8_TRAP_HANDLER_SUPPORTED false$' \
    || die "Android V8 trap-handler patch verification failed: support define not rewritten"

  # Android arm64/arm32 builds of Node 24 can leave android_getCpuFeatures()
  # unresolved in libnode.so through the bundled zlib CPU probing used by
  # both Node's own deps/zlib and V8's vendored copy. Replace the
  # Android-specific path with the same getauxval() based HWCAP probing used
  # on Linux so libnode.so is self-consistent at runtime.
  for zlib_cpu_features_file in "${zlib_cpu_features_files[@]}"; do
    log "forcing Android zlib cpu feature probing to use getauxval() in $(basename "$(dirname "$zlib_cpu_features_file")")/$(basename "$zlib_cpu_features_file")"
    python3 - "$zlib_cpu_features_file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old_include = """#if defined(ARMV8_OS_ANDROID)\n#include <cpu-features.h>\n#elif defined(ARMV8_OS_LINUX)\n#include <asm/hwcap.h>\n#include <sys/auxv.h>\n"""
new_include = """#if defined(ARMV8_OS_ANDROID) || defined(ARMV8_OS_LINUX)\n#include <asm/hwcap.h>\n#include <sys/auxv.h>\n"""
if old_include not in text:
    raise SystemExit("failed to rewrite zlib cpu feature includes")
text = text.replace(old_include, new_include, 1)

old_probe = """#if defined(ARMV8_OS_ANDROID) && defined(__aarch64__)\n    uint64_t features = android_getCpuFeatures();\n    arm_cpu_enable_crc32 = !!(features & ANDROID_CPU_ARM64_FEATURE_CRC32);\n    arm_cpu_enable_pmull = !!(features & ANDROID_CPU_ARM64_FEATURE_PMULL);\n#elif defined(ARMV8_OS_ANDROID) /* aarch32 */\n    uint64_t features = android_getCpuFeatures();\n    arm_cpu_enable_crc32 = !!(features & ANDROID_CPU_ARM_FEATURE_CRC32);\n    arm_cpu_enable_pmull = !!(features & ANDROID_CPU_ARM_FEATURE_PMULL);\n#elif defined(ARMV8_OS_LINUX) && defined(__aarch64__)\n    unsigned long features = getauxval(AT_HWCAP);\n    arm_cpu_enable_crc32 = !!(features & HWCAP_CRC32);\n    arm_cpu_enable_pmull = !!(features & HWCAP_PMULL);\n#elif defined(ARMV8_OS_LINUX) && (defined(__ARM_NEON) || defined(__ARM_NEON__))\n"""
new_probe = """#if (defined(ARMV8_OS_ANDROID) || defined(ARMV8_OS_LINUX)) && defined(__aarch64__)\n    unsigned long features = getauxval(AT_HWCAP);\n    arm_cpu_enable_crc32 = !!(features & HWCAP_CRC32);\n    arm_cpu_enable_pmull = !!(features & HWCAP_PMULL);\n#elif (defined(ARMV8_OS_ANDROID) || defined(ARMV8_OS_LINUX)) && (defined(__ARM_NEON) || defined(__ARM_NEON__))\n"""
if old_probe not in text:
    raise SystemExit("failed to rewrite zlib cpu feature probe logic")
text = text.replace(old_probe, new_probe, 1)

path.write_text(text)
PY

    if grep -q 'android_getCpuFeatures' "$zlib_cpu_features_file"; then
      die "Android zlib cpu feature patch verification failed: android_getCpuFeatures still present in ${zlib_cpu_features_file}"
    fi
  done
}

configure_node() {
  local toolchain
  toolchain="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64"

  log "configuring Node.js ${NODE_VERSION}"
  (
    cd "$NODE_SOURCE_DIR"

    export PATH="${toolchain}/bin:${PATH}"
    export CC="$TARGET_CC"
    export CXX="$TARGET_CXX"
    export AR="$TARGET_AR"
    export AS="$TARGET_CC"
    export LD="$TARGET_LD"
    export NM="$TARGET_NM"
    export RANLIB="$TARGET_RANLIB"
    export READELF="$TARGET_READELF"
    export STRIP="$TARGET_STRIP"

    export CC_host="$HOST_CC"
    export CXX_host="$HOST_CXX"
    export AR_host="$HOST_AR"
    export NM_host="$HOST_NM"
    export RANLIB_host="$HOST_RANLIB"

    export GYP_DEFINES="target_arch=${ANDROID_ARCH} v8_target_arch=${ANDROID_ARCH} android_target_arch=${ANDROID_ARCH} host_os=linux OS=android android_ndk_path=${ANDROID_NDK_HOME}"

    ./configure \
      --dest-os=android \
      --dest-cpu="${ANDROID_ARCH}" \
      --cross-compiling \
      --openssl-no-asm \
      --shared \
      --with-intl="${ICU_MODE}" \
      --without-npm \
      --without-corepack
  )
}

build_node() {
  local toolchain
  toolchain="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64"

  log "building libnode.so with ${BUILD_JOBS} job(s)"
  (
    cd "$NODE_SOURCE_DIR"

    export PATH="${toolchain}/bin:${PATH}"
    export CC="$TARGET_CC"
    export CXX="$TARGET_CXX"
    export AR="$TARGET_AR"
    export AS="$TARGET_CC"
    export LD="$TARGET_LD"
    export NM="$TARGET_NM"
    export RANLIB="$TARGET_RANLIB"
    export READELF="$TARGET_READELF"
    export STRIP="$TARGET_STRIP"

    export CC_host="$HOST_CC"
    export CXX_host="$HOST_CXX"
    export AR_host="$HOST_AR"
    export NM_host="$HOST_NM"
    export RANLIB_host="$HOST_RANLIB"

    export GYP_DEFINES="target_arch=${ANDROID_ARCH} v8_target_arch=${ANDROID_ARCH} android_target_arch=${ANDROID_ARCH} host_os=linux OS=android android_ndk_path=${ANDROID_NDK_HOME}"

    make -C out -j"${BUILD_JOBS}" BUILDTYPE=Release libnode
  )
}

collect_artifacts() {
  local libnode

  libnode="${NODE_SOURCE_DIR}/out/Release/libnode.so"
  [[ -f "$libnode" ]] || die "build finished without ${libnode}"

  mkdir -p "$NODE_DIST_DIR"
  cp -f "$libnode" "${NODE_DIST_DIR}/libnode.so"

  {
    printf 'NODE_VERSION=%s\n' "$NODE_VERSION"
    printf 'ANDROID_ABI=%s\n' "$ANDROID_ABI"
    printf 'ANDROID_API=%s\n' "$ANDROID_API"
    printf 'ICU_MODE=%s\n' "$ICU_MODE"
    printf 'ANDROID_NDK_RELEASE=%s\n' "$ANDROID_NDK_RELEASE"
    printf 'ANDROID_NDK_VERSION=%s\n' "$ANDROID_NDK_VERSION"
    printf 'ANDROID_NDK_HOME=%s\n' "$ANDROID_NDK_HOME"
    printf 'HOST_CC=%s\n' "$HOST_CC"
    printf 'HOST_CXX=%s\n' "$HOST_CXX"
    printf 'TARGET_CC=%s\n' "$TARGET_CC"
    printf 'TARGET_CXX=%s\n' "$TARGET_CXX"
  } > "${NODE_DIST_DIR}/build-info.txt"

  log "artifact ready: ${NODE_DIST_DIR}/libnode.so"
  file "${NODE_DIST_DIR}/libnode.so"
  "$TARGET_READELF" -h "${NODE_DIST_DIR}/libnode.so" | sed -n '1,18p'
}

clean() {
  rm -rf "$WORK_ROOT" "$DIST_ROOT"
  log "removed $WORK_ROOT and $DIST_ROOT"
}

setup() {
  ensure_prereqs
  normalize_config
  pick_host_toolchain
  resolve_node_version
  select_ndk_home
  ensure_ndk
  prepare_target_toolchain
  download_node_source

  log "Node.js version : ${NODE_VERSION}"
  log "Android ABI     : ${ANDROID_ABI}"
  log "Android API     : ${ANDROID_API}"
  log "ICU mode        : ${ICU_MODE}"
  log "NDK             : ${ANDROID_NDK_RELEASE} (${ANDROID_NDK_VERSION})"
  log "Host compiler   : ${HOST_CXX}"
  log "Target compiler : ${TARGET_CXX}"
}

main() {
  local action="${1:-build}"

  case "$action" in
    -h|--help|help)
      usage
      ;;
    clean)
      clean
      ;;
    setup)
      setup
      ;;
    build)
      setup
      prepare_build_tree
      apply_android_patches
      configure_node
      build_node
      collect_artifacts
      ;;
    *)
      die "unknown action: $action"
      ;;
  esac
}

main "$@"
