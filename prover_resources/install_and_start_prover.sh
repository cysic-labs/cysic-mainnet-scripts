#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENUS_DIR="${VENUS_DIR:-$HOME/venus_v0_1_6}"
ZISK_BUNDLE_URL="${ZISK_BUNDLE_URL:-https://public.prover.xyz/vadcop_final/venus_v0_1_6_backend_with_runtime.tar.zst}"
ZISK_BUNDLE_SHA256_URL="${ZISK_BUNDLE_SHA256_URL:-https://public.prover.xyz/vadcop_final/venus_v0_1_6_backend_with_runtime.tar.zst.sha256}"
BACKEND_BUNDLE_SM75_URL="${BACKEND_BUNDLE_SM75_URL:-https://public.prover.xyz/vadcop_final/venus_backend_sm_75.tar.zst}"
BACKEND_BUNDLE_SM86_URL="${BACKEND_BUNDLE_SM86_URL:-https://public.prover.xyz/vadcop_final/venus_backend_sm_86.tar.zst}"
BACKEND_BUNDLE_SM89_URL="${BACKEND_BUNDLE_SM89_URL:-https://public.prover.xyz/vadcop_final/venus_backend_sm_89.tar.zst}"
BACKEND_BUNDLE_SM120_URL="${BACKEND_BUNDLE_SM120_URL:-https://public.prover.xyz/vadcop_final/venus_backend_sm_120.tar.zst}"
DOWNLOAD_TOOL="${DOWNLOAD_TOOL:-curl}"
PORT="${PORT:-7000}"
GPU="${GPU:-}"
INSTALL_NVIDIA_DRIVERS="${INSTALL_NVIDIA_DRIVERS:-auto}"
PROVER_RELEASE_BASE_URL="${PROVER_RELEASE_BASE_URL:-https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/venus-prover-community-v0.1.16}"
CARGO_ZISK_RELEASE_BASE_URL="${CARGO_ZISK_RELEASE_BASE_URL:-https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v2.0.1}"
PROVER_SERVER_BIN="${PROVER_SERVER_BIN:-$SCRIPT_DIR/venus_prover_server}"
PROVER_DEMO_BIN="${PROVER_DEMO_BIN:-$SCRIPT_DIR/venus_prover_demo}"

if ! command -v apt-get >/dev/null 2>&1; then
  echo "apt-get not found. This script expects Ubuntu/Debian." >&2
  exit 1
fi

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=()
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo not found. Run this script as root or install sudo." >&2
    exit 1
  fi
  SUDO=(sudo)
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

download_or_copy_file() {
  local src="$1"
  local dst="$2"

  case "$src" in
    http://*|https://*) download_file "$src" "$dst" ;;
    file://*) cp "${src#file://}" "$dst" ;;
    *) cp "$src" "$dst" ;;
  esac
}

checksum_value() {
  local sha_file="$1"
  awk '{print $1}' "$sha_file" | head -n 1
}

verify_cached_bundle() {
  local bundle_file="$1"
  local sha_file="$2"
  local label="$3"
  local expected_sha
  local actual_sha

  expected_sha="$(checksum_value "$sha_file")"
  actual_sha="$(sha256sum "$bundle_file" | awk '{print $1}')"
  if [[ -z "$expected_sha" || "$expected_sha" != "$actual_sha" ]]; then
    echo "${label} checksum mismatch" >&2
    echo "expected: ${expected_sha:-<empty>}" >&2
    echo "actual:   $actual_sha" >&2
    return 1
  fi

  echo "Verified ${label,,} checksum: $actual_sha"
}

prepare_cached_bundle() {
  local bundle_url="$1"
  local sha_url="$2"
  local bundle_file="$3"
  local sha_file="$4"
  local label="$5"
  local tmp_bundle

  echo "Refreshing ${label,,} checksum file..."
  download_or_copy_file "$sha_url" "$sha_file"

  if [[ -f "$bundle_file" ]]; then
    if verify_cached_bundle "$bundle_file" "$sha_file" "$label"; then
      echo "Using cached ${label,,}: $bundle_file"
      return
    fi
    echo "Cached ${label,,} is outdated or invalid. Re-downloading..."
  else
    echo "${label} not found locally. Downloading..."
  fi

  tmp_bundle="${bundle_file}.download"
  rm -f "$tmp_bundle"
  download_or_copy_file "$bundle_url" "$tmp_bundle"
  mv "$tmp_bundle" "$bundle_file"
  verify_cached_bundle "$bundle_file" "$sha_file" "$label"
}

has_nvidia_driver() {
  command -v nvidia-smi >/dev/null 2>&1 || ldconfig -p | rg -q 'libcuda\.so'
}

detect_gpu_model() {
  local query_args=(--query-gpu=name --format=csv,noheader)

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "nvidia-smi not found. Unable to detect GPU model." >&2
    exit 2
  fi

  if [[ -n "$GPU" ]]; then
    query_args=(-i "$GPU" "${query_args[@]}")
  fi

  nvidia-smi "${query_args[@]}" | head -n 1
}

detect_compute_capability() {
  local query_args=(--query-gpu=compute_cap --format=csv,noheader)

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "nvidia-smi not found. Unable to detect compute capability." >&2
    exit 2
  fi

  if [[ -n "$GPU" ]]; then
    query_args=(-i "$GPU" "${query_args[@]}")
  fi

  nvidia-smi "${query_args[@]}" 2>/dev/null | head -n 1 | tr -d '[:space:]'
}

select_cargo_zisk_asset() {
  local capability="$1"
  local gpu_model="$2"

  case "$capability" in
    7.5|7.5*) printf '%s\n' "cargo-zisk-sm75"; return 0 ;;
    8.6|8.6*) printf '%s\n' "cargo-zisk-sm86"; return 0 ;;
    8.9|8.9*) printf '%s\n' "cargo-zisk-sm89"; return 0 ;;
    12.0|12.0*) printf '%s\n' "cargo-zisk-sm120"; return 0 ;;
  esac

  case "$gpu_model" in
    *"RTX 20"*|*"20"*"90"*|*"20"*"80"*|*"20"*"70"*|*"20"*"60"*|*"20"*"50"*|*"T4"*)
      printf '%s\n' "cargo-zisk-sm75"
      ;;
    *"RTX 30"*|*"30"*"90"*|*"30"*"80"*|*"30"*"70"*|*"30"*"60"*|*"30"*"50"*|*"A10"*|*"A40"*|*"A30"*)
      printf '%s\n' "cargo-zisk-sm86"
      ;;
    *"RTX 40"*|*"40"*"90"*|*"40"*"80"*|*"40"*"70"*|*"40"*"60"*|*"40"*"50"*|*"L4"*|*"L40"*)
      printf '%s\n' "cargo-zisk-sm89"
      ;;
    *"RTX 50"*|*"50"*"90"*|*"50"*"80"*|*"50"*"70"*|*"50"*"60"*|*"50"*"50"*)
      printf '%s\n' "cargo-zisk-sm120"
      ;;
    *)
      echo "Unsupported or unknown GPU model for cargo-zisk: $gpu_model" >&2
      exit 2
      ;;
  esac
}

update_cargo_zisk() {
  local gpu_model="$1"
  local capability="$2"
  local asset_name
  local target_path="$VENUS_DIR/target/release/cargo-zisk"
  local tmp_file

  asset_name="$(select_cargo_zisk_asset "$capability" "$gpu_model")"
  tmp_file="$(mktemp)"
  trap 'rm -f "$tmp_file"' EXIT

  echo "Updating cargo-zisk with asset: $asset_name"
  download_file "$CARGO_ZISK_RELEASE_BASE_URL/$asset_name" "$tmp_file"
  chmod +x "$tmp_file"
  mv "$tmp_file" "$target_path"
  trap - EXIT
}

select_backend_bundle() {
  local gpu_model="$1"

  case "$gpu_model" in
    *"RTX 20"*|*"20"*"90"*|*"20"*"80"*|*"20"*"70"*|*"20"*"60"*|*"20"*"50"*|*"T4"*)
      printf '%s\n' "$BACKEND_BUNDLE_SM75_URL"
      ;;
    *"RTX 30"*|*"30"*"90"*|*"30"*"80"*|*"30"*"70"*|*"30"*"60"*|*"30"*"50"*|*"A10"*|*"A40"*|*"A30"*)
      printf '%s\n' "$BACKEND_BUNDLE_SM86_URL"
      ;;
    *"RTX 40"*|*"40"*"90"*|*"40"*"80"*|*"40"*"70"*|*"40"*"60"*|*"40"*"50"*|*"L4"*|*"L40"*)
      printf '%s\n' "$BACKEND_BUNDLE_SM89_URL"
      ;;
    *"RTX 50"*|*"50"*"90"*|*"50"*"80"*|*"50"*"70"*|*"50"*"60"*|*"50"*"50"*)
      printf '%s\n' "$BACKEND_BUNDLE_SM120_URL"
      ;;
    *)
      echo "Unsupported or unknown GPU model: $gpu_model" >&2
      exit 2
      ;;
  esac
}

"${SUDO[@]}" apt-get update
"${SUDO[@]}" apt-get install -y \
  ca-certificates curl wget tar zstd \
  libssl3 libstdc++6 libgmp10 libgmp-dev libsodium23 libomp5 \
  openmpi-bin libopenmpi3 libopenmpi-dev libhwloc15 \
  libz1 libevent-2.1-7 libevent-pthreads-2.1-7 libudev1 libcap2 ripgrep build-essential binutils

if ! ldconfig -p | rg -q 'libcudart.so.13'; then
  wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin
  "${SUDO[@]}" mv cuda-ubuntu2404.pin /etc/apt/preferences.d/cuda-repository-pin-600
  wget -q https://developer.download.nvidia.com/compute/cuda/13.0.0/local_installers/cuda-repo-ubuntu2404-13-0-local_13.0.0-580.65.06-1_amd64.deb
  "${SUDO[@]}" dpkg -i cuda-repo-ubuntu2404-13-0-local_13.0.0-580.65.06-1_amd64.deb
  "${SUDO[@]}" cp /var/cuda-repo-ubuntu2404-13-0-local/cuda-*-keyring.gpg /usr/share/keyrings/
  "${SUDO[@]}" apt-get update
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
  "${SUDO[@]}" apt-get install -y "${cuda_packages[@]}"
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
  [[ -f "$VENUS_DIR/guest/zisk-eth-client/bin/guests/stateless-validator-reth/target/riscv64ima-zisk-zkvm-elf/release/zec-reth" ]]
}

is_pk_ready() {
  [[ -f "$VENUS_DIR/build/provingKey/zisk/vadcop_final/vadcop_final.verkey.bin" ]]
}

link_zisk_runtime() {
  mkdir -p "$HOME/.zisk/zisk" "$HOME/.zisk/bin"
  rm -rf "$HOME/.zisk/zisk/emulator-asm"
  rm -f "$HOME/.zisk/bin/libziskclib.a"
  ln -sfn "$VENUS_DIR/emulator-asm" "$HOME/.zisk/zisk/emulator-asm"
  ln -sfn "$VENUS_DIR/target/release/libziskclib.a" "$HOME/.zisk/bin/libziskclib.a"
}

gpu_model="$(detect_gpu_model)"
compute_capability="$(detect_compute_capability || true)"

if ! is_backend_ready; then
  parent_dir="$(dirname "$VENUS_DIR")"
  mkdir -p "$parent_dir"

  backend_bundle_url="$(select_backend_bundle "$gpu_model")"
  backend_bundle_sha256_url="${VENUS_BUNDLE_SHA256_URL:-${backend_bundle_url}.sha256}"
  backend_bundle_name="$(basename "$backend_bundle_url")"
  backend_sha_name="$(basename "$backend_bundle_sha256_url")"
  archive="$HOME/$backend_bundle_name"
  sha256_file="$HOME/$backend_sha_name"
  echo "Detected GPU model: $gpu_model"
  echo "Using backend bundle: $backend_bundle_url"

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  prepare_cached_bundle "$backend_bundle_url" "$backend_bundle_sha256_url" "$archive" "$sha256_file" "Backend bundle"

  extract_dir="$tmp_dir/extracted"
  mkdir -p "$extract_dir"
  case "$backend_bundle_url" in
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$extract_dir" ;;
    *.tar.zst|*.tzst) tar --zstd -xf "$archive" -C "$extract_dir" ;;
    *.tar) tar -xf "$archive" -C "$extract_dir" ;;
    *) echo "Unsupported backend bundle format: $backend_bundle_url" >&2; exit 2 ;;
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

if ! is_pk_ready; then
  zisk_bundle_name="$(basename "$ZISK_BUNDLE_URL")"
  zisk_sha_name="$(basename "$ZISK_BUNDLE_SHA256_URL")"
  archive_pk="$HOME/$zisk_bundle_name"
  sha256_file_pk="$HOME/$zisk_sha_name"
  tmp_dir_pk="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir_pk"' EXIT
  extract_dir_pk="$tmp_dir_pk/extracted"
  mkdir -p "$extract_dir_pk"

  prepare_cached_bundle "$ZISK_BUNDLE_URL" "$ZISK_BUNDLE_SHA256_URL" "$archive_pk" "$sha256_file_pk" "Zisk bundle"

  tar --zstd -xf "$archive_pk" -C "$extract_dir_pk"
  shopt -s dotglob nullglob
  entries=("$extract_dir_pk"/*)
  if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then extracted_root_pk="${entries[0]}"; else extracted_root_pk="$extract_dir_pk"; fi

  pk_dir="$(find "$extracted_root_pk" -type d -path '*/build/provingKey' | head -n 1)"
  if [[ -z "$pk_dir" ]]; then
    echo "Unable to find build/provingKey in zisk bundle." >&2
    exit 2
  fi

  mkdir -p "$VENUS_DIR/build"
  rm -rf "$VENUS_DIR/build/provingKey"
  cp -a "$pk_dir" "$VENUS_DIR/build/provingKey"

  if ! is_pk_ready; then
    echo "Extracted pk at $VENUS_DIR/build/provingKey is incomplete." >&2
    exit 2
  fi
fi

link_zisk_runtime
if [[ -n "$compute_capability" ]]; then
  echo "Detected compute capability: $compute_capability"
else
  echo "Compute capability query unavailable; using GPU name fallback for cargo-zisk"
fi
update_cargo_zisk "$gpu_model" "$compute_capability"
mkdir -p "$VENUS_DIR/tmp"
cmd=(env VENUS_PROVER_GRPC_PORT="$PORT" VENUS_DIR="$VENUS_DIR" VENUS_OUT_DIR="$VENUS_DIR/tmp" ASM_UNLOCK="${ASM_UNLOCK:-true}" RUST_LOG="${RUST_LOG:-info}")
if [[ -n "$GPU" ]]; then cmd+=(CUDA_VISIBLE_DEVICES="$GPU"); fi
cmd+=("$PROVER_SERVER_BIN")
exec "${cmd[@]}"
