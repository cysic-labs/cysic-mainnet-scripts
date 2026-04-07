#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENUS_DIR="${VENUS_DIR:-$HOME/venus_v0_1_6}"
VENUS_BUNDLE_URL="${VENUS_BUNDLE_URL:-https://public.prover.xyz/vadcop_final/venus_v0_1_6_backend_with_runtime.tar.zst}"
VENUS_BUNDLE_SHA256_URL="${VENUS_BUNDLE_SHA256_URL:-https://public.prover.xyz/vadcop_final/venus_v0_1_6_backend_with_runtime.tar.zst.sha256}"
ZISK_BUNDLE_URL="${ZISK_BUNDLE_URL:-https://public.prover.xyz/vadcop_final/venus_v0_1_6_zisk_bundle}"
ZISK_BUNDLE_SHA256_URL="${ZISK_BUNDLE_SHA256_URL:-https://public.prover.xyz/vadcop_final/venus_v0_1_6_zisk_bundle.sha256}"
DOWNLOAD_TOOL="${DOWNLOAD_TOOL:-curl}"
PORT="${PORT:-7000}"
GPU="${GPU:-}"
INSTALL_NVIDIA_DRIVERS="${INSTALL_NVIDIA_DRIVERS:-auto}"
PROVER_RELEASE_BASE_URL="${PROVER_RELEASE_BASE_URL:-https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/venus-prover-community-v0.1.16}"
PROVER_SERVER_BIN="${PROVER_SERVER_BIN:-$SCRIPT_DIR/venus_prover_server}"
PROVER_DEMO_BIN="${PROVER_DEMO_BIN:-$SCRIPT_DIR/venus_prover_demo}"

if ! command -v apt-get >/dev/null 2>&1; then
  echo "apt-get not found. This script expects Ubuntu/Debian." >&2
  exit 1
fi

download_file() {
  local url="$1"
  local dst="$2"
  if [[ "$DOWNLOAD_TOOL" == "wget" ]]; then
    wget -O "$dst" "$url"
  else
    curl -L --fail --output "$dst" "$url"
  fi
}

has_nvidia_driver() {
  command -v nvidia-smi >/dev/null 2>&1 || ldconfig -p | rg -q 'libcuda\.so'
}

sudo apt-get update
sudo apt-get install -y \
  ca-certificates curl wget tar zstd \
  libssl3 libstdc++6 libgmp10 libsodium23 libomp5 \
  openmpi-bin libopenmpi3 libopenmpi-dev libhwloc15 \
  libz1 libevent-2.1-7 libevent-pthreads-2.1-7 libudev1 libcap2 ripgrep build-essential binutils

if ! ldconfig -p | rg -q 'libcudart.so.13'; then
  wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin
  sudo mv cuda-ubuntu2404.pin /etc/apt/preferences.d/cuda-repository-pin-600
  wget -q https://developer.download.nvidia.com/compute/cuda/13.0.0/local_installers/cuda-repo-ubuntu2404-13-0-local_13.0.0-580.65.06-1_amd64.deb
  sudo dpkg -i cuda-repo-ubuntu2404-13-0-local_13.0.0-580.65.06-1_amd64.deb
  sudo cp /var/cuda-repo-ubuntu2404-13-0-local/cuda-*-keyring.gpg /usr/share/keyrings/
  sudo apt-get update
  cuda_packages=(cuda-toolkit-13-0)
  case "$INSTALL_NVIDIA_DRIVERS" in
    always)
      cuda_packages+=(cuda-drivers)
      ;;
    auto)
      if has_nvidia_driver; then
        echo "Existing NVIDIA driver detected; installing CUDA toolkit only."
      else
        cuda_packages+=(cuda-drivers)
      fi
      ;;
    never)
      echo "Skipping NVIDIA driver installation; installing CUDA toolkit only."
      ;;
    *)
      echo "INSTALL_NVIDIA_DRIVERS must be one of: auto, always, never" >&2
      exit 2
      ;;
  esac
  sudo apt-get install -y "${cuda_packages[@]}"
  if [[ " ${cuda_packages[*]} " == *" cuda-drivers "* ]]; then
    echo "CUDA toolkit and NVIDIA drivers installed. A reboot may be required."
  else
    echo "CUDA toolkit installed."
  fi
fi

if [[ ! -x "$PROVER_SERVER_BIN" ]]; then
  echo "Downloading venus_prover_server..."
  download_file "$PROVER_RELEASE_BASE_URL/venus_prover_server" "$PROVER_SERVER_BIN"
  chmod +x "$PROVER_SERVER_BIN"
fi

if [[ ! -x "$PROVER_DEMO_BIN" ]]; then
  echo "Downloading venus_prover_demo..."
  download_file "$PROVER_RELEASE_BASE_URL/venus_prover_demo" "$PROVER_DEMO_BIN"
  chmod +x "$PROVER_DEMO_BIN"
fi

is_backend_ready() {
  [[ -f "$VENUS_DIR/target/release/cargo-zisk" ]] && \
  [[ -f "$VENUS_DIR/target/release/libziskclib.a" ]] && \
  [[ -d "$VENUS_DIR/emulator-asm" ]] && \
  [[ -f "$VENUS_DIR/lib-c/c/lib/libziskc.a" ]] && \
  [[ -d "$VENUS_DIR/lib-c/c/src" ]] && \
  [[ -f "$VENUS_DIR/build/provingKey/zisk/vadcop_final/vadcop_final.verkey.bin" ]] && \
  [[ -f "$VENUS_DIR/guest/zisk-eth-client/bin/guests/stateless-validator-reth/target/riscv64ima-zisk-zkvm-elf/release/zec-reth" ]]
}

is_zisk_ready() {
  [[ -d "$HOME/.zisk/toolchains" ]]
}

link_zisk_runtime() {
  mkdir -p "$HOME/.zisk/zisk" "$HOME/.zisk/bin"
  rm -rf "$HOME/.zisk/zisk/emulator-asm"
  rm -f "$HOME/.zisk/bin/libziskclib.a"
  ln -sfn "$VENUS_DIR/emulator-asm" "$HOME/.zisk/zisk/emulator-asm"
  ln -sfn "$VENUS_DIR/target/release/libziskclib.a" "$HOME/.zisk/bin/libziskclib.a"
}

if ! is_backend_ready; then
  parent_dir="$(dirname "$VENUS_DIR")"
  mkdir -p "$parent_dir"

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  archive="$tmp_dir/venus_backend_bundle"
  sha256_file="$tmp_dir/venus_backend_bundle.sha256"

  case "$VENUS_BUNDLE_URL" in
    http://*|https://*)
      if [[ "$DOWNLOAD_TOOL" == "wget" ]]; then wget -O "$archive" "$VENUS_BUNDLE_URL"; else curl -L --fail --output "$archive" "$VENUS_BUNDLE_URL"; fi
      ;;
    file://*) cp "${VENUS_BUNDLE_URL#file://}" "$archive" ;;
    *) cp "$VENUS_BUNDLE_URL" "$archive" ;;
  esac

  case "$VENUS_BUNDLE_SHA256_URL" in
    http://*|https://*)
      if [[ "$DOWNLOAD_TOOL" == "wget" ]]; then wget -O "$sha256_file" "$VENUS_BUNDLE_SHA256_URL"; else curl -L --fail --output "$sha256_file" "$VENUS_BUNDLE_SHA256_URL"; fi
      ;;
    file://*) cp "${VENUS_BUNDLE_SHA256_URL#file://}" "$sha256_file" ;;
    *) [[ -f "$VENUS_BUNDLE_SHA256_URL" ]] && cp "$VENUS_BUNDLE_SHA256_URL" "$sha256_file" ;;
  esac

  if [[ -f "$sha256_file" ]]; then
    expected_sha="$(awk '{print $1}' "$sha256_file" | head -n 1)"
    actual_sha="$(sha256sum "$archive" | awk '{print $1}')"
    [[ -n "$expected_sha" && "$expected_sha" == "$actual_sha" ]] || { echo "Backend bundle checksum mismatch" >&2; echo "expected: ${expected_sha:-<empty>}" >&2; echo "actual:   $actual_sha" >&2; exit 2; }
    echo "Verified backend bundle checksum: $actual_sha"
  else
    echo "No backend bundle checksum file found; skipping checksum verification."
  fi

  extract_dir="$tmp_dir/extracted"
  mkdir -p "$extract_dir"
  case "$VENUS_BUNDLE_URL" in
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$extract_dir" ;;
    *.tar.zst|*.tzst) tar --zstd -xf "$archive" -C "$extract_dir" ;;
    *.tar) tar -xf "$archive" -C "$extract_dir" ;;
    *) echo "Unsupported backend bundle format: $VENUS_BUNDLE_URL" >&2; exit 2 ;;
  esac

  shopt -s dotglob nullglob
  entries=("$extract_dir"/*)
  if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then extracted_root="${entries[0]}"; else extracted_root="$extract_dir"; fi

  rm -rf "$VENUS_DIR"
  mkdir -p "$VENUS_DIR"
  cp -a "$extracted_root"/. "$VENUS_DIR"/

  if ! is_backend_ready; then
    echo "Extracted backend at $VENUS_DIR is incomplete." >&2
    exit 2
  fi
fi

if ! is_zisk_ready; then
  tmp_dir_zisk="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir_zisk"' EXIT
  archive_zisk="$tmp_dir_zisk/zisk_bundle"
  sha256_file_zisk="$tmp_dir_zisk/zisk_bundle.sha256"
  extract_dir_zisk="$tmp_dir_zisk/extracted"
  mkdir -p "$extract_dir_zisk"

  case "$ZISK_BUNDLE_URL" in
    http://*|https://*)
      if [[ "$DOWNLOAD_TOOL" == "wget" ]]; then wget -O "$archive_zisk" "$ZISK_BUNDLE_URL"; else curl -L --fail --output "$archive_zisk" "$ZISK_BUNDLE_URL"; fi
      ;;
    file://*) cp "${ZISK_BUNDLE_URL#file://}" "$archive_zisk" ;;
    *) cp "$ZISK_BUNDLE_URL" "$archive_zisk" ;;
  esac

  case "$ZISK_BUNDLE_SHA256_URL" in
    http://*|https://*)
      if [[ "$DOWNLOAD_TOOL" == "wget" ]]; then wget -O "$sha256_file_zisk" "$ZISK_BUNDLE_SHA256_URL"; else curl -L --fail --output "$sha256_file_zisk" "$ZISK_BUNDLE_SHA256_URL"; fi
      ;;
    file://*) cp "${ZISK_BUNDLE_SHA256_URL#file://}" "$sha256_file_zisk" ;;
    *) [[ -f "$ZISK_BUNDLE_SHA256_URL" ]] && cp "$ZISK_BUNDLE_SHA256_URL" "$sha256_file_zisk" ;;
  esac

  if [[ -f "$sha256_file_zisk" ]]; then
    expected_sha="$(awk '{print $1}' "$sha256_file_zisk" | head -n 1)"
    actual_sha="$(sha256sum "$archive_zisk" | awk '{print $1}')"
    [[ -n "$expected_sha" && "$expected_sha" == "$actual_sha" ]] || { echo "Zisk bundle checksum mismatch" >&2; echo "expected: ${expected_sha:-<empty>}" >&2; echo "actual:   $actual_sha" >&2; exit 2; }
    echo "Verified zisk bundle checksum: $actual_sha"
  else
    echo "No zisk bundle checksum file found; skipping checksum verification."
  fi

  tar --zstd -xf "$archive_zisk" -C "$extract_dir_zisk"
  shopt -s dotglob nullglob
  entries=("$extract_dir_zisk"/*)
  if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then extracted_root_zisk="${entries[0]}"; else extracted_root_zisk="$extract_dir_zisk"; fi

  mkdir -p "$HOME/.zisk"
  rm -rf "$HOME/.zisk/toolchains"
  cp -a "$extracted_root_zisk"/. "$HOME/.zisk"/
fi

link_zisk_runtime
mkdir -p "$VENUS_DIR/tmp"
cmd=(env VENUS_PROVER_GRPC_PORT="$PORT" VENUS_DIR="$VENUS_DIR" VENUS_OUT_DIR="$VENUS_DIR/tmp" RUST_LOG="${RUST_LOG:-info}")
if [[ -n "$GPU" ]]; then cmd+=(CUDA_VISIBLE_DEVICES="$GPU"); fi
cmd+=("$PROVER_SERVER_BIN")
exec "${cmd[@]}"
