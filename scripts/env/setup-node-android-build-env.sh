#!/usr/bin/env bash
set -Eeuo pipefail

LLVM_VERSION="${LLVM_VERSION:-20}"
ZELLIJ_VERSION="${ZELLIJ_VERSION:-0.44.0}"
ANDROID_ROOT="${ANDROID_ROOT:-/opt/android}"
ANDROID_NDK_RELEASE="${ANDROID_NDK_RELEASE:-r29}"
ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-29.0.14206865}"
ANDROID_NDK_SHA1="${ANDROID_NDK_SHA1:-87e2bb7e9be5d6a1c6cdf5ec40dd4e0c6d07c30b}"
PROFILE_FILE="${PROFILE_FILE:-/etc/profile.d/node-android-env.sh}"

APT_FRONTEND="${APT_FRONTEND:-noninteractive}"
APT_GET=(apt-get -y -o Dpkg::Use-Pty=0)

log() {
  printf '[SETUP] %s\n' "$*"
}

die() {
  printf '[SETUP][ERROR] %s\n' "$*" >&2
  exit 1
}

need_root() {
  [[ "${EUID}" == "0" ]] || die "please run this script as root"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

host_arch() {
  uname -m
}

ubuntu_codename() {
  . /etc/os-release
  printf '%s\n' "${VERSION_CODENAME:-}"
}

assert_supported_host() {
  [[ -f /etc/os-release ]] || die "missing /etc/os-release"

  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "this script currently supports Ubuntu only"
  [[ "$(host_arch)" == "x86_64" ]] || die "this script currently supports x86_64 hosts only"
}

apt_update() {
  DEBIAN_FRONTEND="$APT_FRONTEND" "${APT_GET[@]}" update
}

install_bootstrap_packages() {
  DEBIAN_FRONTEND="$APT_FRONTEND" "${APT_GET[@]}" install \
    ca-certificates \
    curl \
    gpg \
    lsb-release \
    software-properties-common
}

ensure_bootstrap_commands() {
  local missing=0
  local cmd

  for cmd in curl gpg lsb_release add-apt-repository; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing=1
      break
    fi
  done

  if [[ "$missing" == "1" ]]; then
    install_bootstrap_packages
  fi

  need_cmd curl
  need_cmd gpg
  need_cmd lsb_release
  need_cmd add-apt-repository
}

ensure_universe_repo() {
  local universe_entry=""

  universe_entry="$(grep -RhsE '(^deb .* universe( .*)?$)|(^Suites: .*$)' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null | grep -i universe || true)"
  if [[ -n "$universe_entry" ]]; then
    return
  fi

  need_cmd add-apt-repository
  log "enabling Ubuntu universe repository"
  add-apt-repository -y universe
}

ensure_llvm_repo() {
  local codename keyring list_file repo_line source_file

  codename="$(ubuntu_codename)"
  [[ -n "$codename" ]] || die "failed to detect Ubuntu codename"

  keyring="/etc/apt/keyrings/apt.llvm.org.gpg"
  list_file="/etc/apt/sources.list.d/apt-llvm-${codename}-${LLVM_VERSION}.list"
  repo_line="deb [signed-by=${keyring}] http://apt.llvm.org/${codename}/ llvm-toolchain-${codename}-${LLVM_VERSION} main"

  mkdir -p /etc/apt/keyrings

  if [[ ! -s "$keyring" ]]; then
    log "installing apt.llvm.org keyring"
    curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor -o "$keyring"
  fi

  for source_file in /etc/apt/sources.list.d/*; do
    [[ -f "$source_file" ]] || continue
    [[ "$source_file" == "$list_file" ]] && continue
    if grep -q 'apt\.llvm\.org/' "$source_file" 2>/dev/null; then
      log "disabling conflicting LLVM apt source: ${source_file}"
      mv -f "$source_file" "${source_file}.disabled"
    fi
  done

  if [[ ! -f "$list_file" ]] || ! grep -Fxq "$repo_line" "$list_file"; then
    log "configuring LLVM ${LLVM_VERSION} apt repository"
    printf '%s\n' "$repo_line" > "$list_file"
  fi
}

install_system_packages() {
  DEBIAN_FRONTEND="$APT_FRONTEND" "${APT_GET[@]}" install \
    build-essential \
    ca-certificates \
    clang-"${LLVM_VERSION}" \
    curl \
    file \
    g++-11 \
    gcc-11 \
    git \
    jq \
    libstdc++-11-dev \
    lld-"${LLVM_VERSION}" \
    llvm-"${LLVM_VERSION}" \
    make \
    ninja-build \
    openjdk-21-jdk-headless \
    patch \
    pkg-config \
    python3 \
    python3-distutils \
    unzip \
    xz-utils \
    zip \
    zlib1g-dev
}

zellij_asset_name() {
  case "$(host_arch)" in
    x86_64)
      printf 'zellij-x86_64-unknown-linux-musl\n'
      ;;
    aarch64|arm64)
      printf 'zellij-aarch64-unknown-linux-musl\n'
      ;;
    *)
      die "unsupported zellij host architecture: $(host_arch)"
      ;;
  esac
}

install_zellij() {
  local installed_version="" asset base_url tmpdir archive checksum

  if command -v zellij >/dev/null 2>&1; then
    installed_version="$(zellij --version 2>/dev/null | awk '{print $2}')"
  fi

  if [[ "$installed_version" == "$ZELLIJ_VERSION" ]]; then
    log "zellij ${ZELLIJ_VERSION} already installed"
    return
  fi

  asset="$(zellij_asset_name)"
  base_url="https://github.com/zellij-org/zellij/releases/download/v${ZELLIJ_VERSION}"
  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/${asset}.tar.gz"
  checksum="${tmpdir}/${asset}.sha256sum"

  log "installing zellij ${ZELLIJ_VERSION}"
  curl -fL --retry 3 --retry-all-errors "${base_url}/${asset}.tar.gz" -o "$archive"
  curl -fL --retry 3 --retry-all-errors "${base_url}/${asset}.sha256sum" -o "$checksum"
  (
    cd "$tmpdir"
    sha256sum -c "$(basename "$checksum")"
  )
  tar -xzf "$archive" -C "$tmpdir" zellij
  install -m 0755 "$tmpdir/zellij" /usr/local/bin/zellij
  rm -rf "$tmpdir"
}

install_android_ndk() {
  local ndk_root ndk_dir ndk_zip

  ndk_root="$ANDROID_ROOT"
  ndk_dir="${ndk_root}/android-ndk-${ANDROID_NDK_RELEASE}"
  ndk_zip="${ndk_root}/android-ndk-${ANDROID_NDK_RELEASE}-linux.zip"

  mkdir -p "$ndk_root"

  if [[ ! -d "$ndk_dir/toolchains/llvm/prebuilt/linux-x86_64/bin" ]]; then
    log "installing Android NDK ${ANDROID_NDK_RELEASE} (${ANDROID_NDK_VERSION})"
    rm -f "$ndk_zip"
    curl -fL --retry 3 --retry-all-errors \
      "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_RELEASE}-linux.zip" \
      -o "$ndk_zip"
    echo "${ANDROID_NDK_SHA1}  ${ndk_zip}" | sha1sum -c -
    rm -rf "$ndk_dir"
    unzip -q "$ndk_zip" -d "$ndk_root"
  else
    log "Android NDK ${ANDROID_NDK_RELEASE} already installed"
  fi

  ln -sfn "$ndk_dir" "${ndk_root}/ndk"
}

write_profile_env() {
  log "writing ${PROFILE_FILE}"
  install -d "$(dirname "$PROFILE_FILE")"
  cat > "$PROFILE_FILE" <<EOF
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=${ANDROID_ROOT}
export ANDROID_SDK_ROOT=${ANDROID_ROOT}
export ANDROID_NDK_HOME=${ANDROID_ROOT}/ndk
export ANDROID_NDK_ROOT=${ANDROID_ROOT}/ndk
export NODE_ANDROID_HOST_CC=/usr/bin/clang-${LLVM_VERSION}
export NODE_ANDROID_HOST_CXX=/usr/bin/clang++-${LLVM_VERSION}

case ":\$PATH:" in
  *":\$JAVA_HOME/bin:"*) ;;
  *) export PATH="\$JAVA_HOME/bin:\$PATH" ;;
esac

case ":\$PATH:" in
  *":\$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:"*) ;;
  *) export PATH="\$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:\$PATH" ;;
esac
EOF
  chmod 0644 "$PROFILE_FILE"
}

print_summary() {
  cat <<EOF
[SETUP] environment is ready
[SETUP] LLVM          : $(/usr/bin/clang-"${LLVM_VERSION}" --version | head -n 1)
[SETUP] Java          : $(/usr/lib/jvm/java-21-openjdk-amd64/bin/java -version 2>&1 | head -n 1)
[SETUP] Zellij        : $(zellij --version)
[SETUP] Android NDK   : ${ANDROID_NDK_RELEASE} (${ANDROID_NDK_VERSION}) -> ${ANDROID_ROOT}/ndk
[SETUP] Profile       : ${PROFILE_FILE}

Next steps:
  source ${PROFILE_FILE}
  cd /root/node-android
  ./scripts/build/build-node-android.sh build
EOF
}

main() {
  need_root
  assert_supported_host
  ensure_bootstrap_commands
  ensure_universe_repo
  ensure_llvm_repo
  apt_update
  install_bootstrap_packages
  install_system_packages
  install_zellij
  install_android_ndk
  write_profile_env
  print_summary
}

main "$@"
