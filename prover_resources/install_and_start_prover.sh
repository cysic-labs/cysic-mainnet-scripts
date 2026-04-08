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

if ! is_backend_ready; then
  parent_dir="$(dirname "$VENUS_DIR")"
  mkdir -p "$parent_dir"

  gpu_model="$(detect_gpu_model)"
  backend_bundle_url="$(select_backend_bundle "$gpu_model")"
  backend_bundle_sha256_url="${VENUS_BUNDLE_SHA256_URL:-${backend_bundle_url}.sha256}"
  echo "Detected GPU model: $gpu_model"
  echo "Using backend bundle: $backend_bundle_url"

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  archive="$tmp_dir/venus_backend_bundle"
  sha256_file="$tmp_dir/venus_backend_bundle.sha256"

  case "$backend_bundle_url" in
    http://*|https://*)
      if [[ "$DOWNLOAD_TOOL" == "wget" ]]; then wget -O "$archive" "$backend_bundle_url"; else curl -L --fail --output "$archive" "$backend_bundle_url"; fi
      ;;
    file://*) cp "${backend_bundle_url#file://}" "$archive" ;;
    *) cp "$backend_bundle_url" "$archive" ;;
  esac

  case "$backend_bundle_sha256_url" in
    http://*|https://*)
      if [[ "$DOWNLOAD_TOOL" == "wget" ]]; then wget -O "$sha256_file" "$backend_bundle_sha256_url"; else curl -L --fail --output "$sha256_file" "$backend_bundle_sha256_url"; fi
      ;;
    file://*) cp "${backend_bundle_sha256_url#file://}" "$sha256_file" ;;
    *) [[ -f "$backend_bundle_sha256_url" ]] && cp "$backend_bundle_sha256_url" "$sha256_file" ;;
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
  tmp_dir_pk="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir_pk"' EXIT
  archive_pk="$tmp_dir_pk/zisk_bundle"
  sha256_file_pk="$tmp_dir_pk/zisk_bundle.sha256"
  extract_dir_pk="$tmp_dir_pk/extracted"
  mkdir -p "$extract_dir_pk"

  case "$ZISK_BUNDLE_URL" in
    http://*|https://*)
      if [[ "$DOWNLOAD_TOOL" == "wget" ]]; then wget -O "$archive_pk" "$ZISK_BUNDLE_URL"; else curl -L --fail --output "$archive_pk" "$ZISK_BUNDLE_URL"; fi
      ;;
    file://*) cp "${ZISK_BUNDLE_URL#file://}" "$archive_pk" ;;
    *) cp "$ZISK_BUNDLE_URL" "$archive_pk" ;;
  esac

  case "$ZISK_BUNDLE_SHA256_URL" in
    http://*|https://*)
      if [[ "$DOWNLOAD_TOOL" == "wget" ]]; then wget -O "$sha256_file_pk" "$ZISK_BUNDLE_SHA256_URL"; else curl -L --fail --output "$sha256_file_pk" "$ZISK_BUNDLE_SHA256_URL"; fi
      ;;
    file://*) cp "${ZISK_BUNDLE_SHA256_URL#file://}" "$sha256_file_pk" ;;
    *) [[ -f "$ZISK_BUNDLE_SHA256_URL" ]] && cp "$ZISK_BUNDLE_SHA256_URL" "$sha256_file_pk" ;;
  esac

  if [[ -f "$sha256_file_pk" ]]; then
    expected_sha="$(awk '{print $1}' "$sha256_file_pk" | head -n 1)"
    actual_sha="$(sha256sum "$archive_pk" | awk '{print $1}')"
    [[ -n "$expected_sha" && "$expected_sha" == "$actual_sha" ]] || { echo "Zisk bundle checksum mismatch" >&2; echo "expected: ${expected_sha:-<empty>}" >&2; echo "actual:   $actual_sha" >&2; exit 2; }
    echo "Verified zisk bundle checksum: $actual_sha"
  else
    echo "No zisk bundle checksum file found; skipping checksum verification."
  fi

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
mkdir -p "$VENUS_DIR/tmp"
cmd=(env VENUS_PROVER_GRPC_PORT="$PORT" VENUS_DIR="$VENUS_DIR" VENUS_OUT_DIR="$VENUS_DIR/tmp" RUST_LOG="${RUST_LOG:-info}")
if [[ -n "$GPU" ]]; then cmd+=(CUDA_VISIBLE_DEVICES="$GPU"); fi
cmd+=("$PROVER_SERVER_BIN")
exec "${cmd[@]}"
