#!/usr/bin/env bash
set -euo pipefail

# Configurable inputs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_URL="${BUNDLE_URL:-https://public.prover.xyz/vadcop_final/vadcop_bundle_portable_v2.tar.zst}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/venus_bundle}"
PORT="${PORT:-7000}"
PROVER_RELEASE_BASE_URL="${PROVER_RELEASE_BASE_URL:-https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/venus-prover-community-v0.1.16}"
PROVER_BIN="${PROVER_BIN:-$SCRIPT_DIR/venus_prover_server}"
CUDA_INSTALLED=0

if [[ -z "${ETH_PROOF_ENDPOINT:-}" ]]; then
  echo "ETH_PROOF_ENDPOINT is required (set by caller, e.g. setup.sh)."
  exit 1
fi

# === Install Linux dependencies ===
if ! command -v apt-get >/dev/null 2>&1; then
  echo "apt-get not found. This script expects Ubuntu/Debian."
  exit 1
fi

sudo apt-get update
sudo apt-get install -y \
  ca-certificates \
  curl \
  tar \
  zstd \
  libssl3 \
  libstdc++6 \
  libgmp10 \
  libsodium23 \
  libomp5 \
  openmpi-bin \
  libopenmpi3 \
  libopenmpi-dev \
  libhwloc15 \
  libz1 \
  libevent-2.1-7 \
  libevent-pthreads-2.1-7 \
  libudev1 \
  libcap2

# === Install CUDA 13 toolkit if missing ===
if ! ldconfig -p | rg -q "libcudart.so.13"; then
  wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin
  sudo mv cuda-ubuntu2404.pin /etc/apt/preferences.d/cuda-repository-pin-600
  wget https://developer.download.nvidia.com/compute/cuda/13.0.0/local_installers/cuda-repo-ubuntu2404-13-0-local_13.0.0-580.65.06-1_amd64.deb
  sudo dpkg -i cuda-repo-ubuntu2404-13-0-local_13.0.0-580.65.06-1_amd64.deb
  sudo cp /var/cuda-repo-ubuntu2404-13-0-local/cuda-*-keyring.gpg /usr/share/keyrings/
  sudo apt-get update
  sudo apt-get -y install cuda-toolkit-13-0
  sudo apt-get install -y cuda-drivers
  CUDA_INSTALLED=1
  echo "CUDA installed. A reboot may be required."
fi

if [[ "$CUDA_INSTALLED" -eq 1 ]]; then
  echo "Please reboot the machine and rerun install_and_run_prover0.sh to start prover0."
  exit 0
fi

# === Bundle paths ===
BUNDLE_FILE="$(basename "$BUNDLE_URL")"
SHA_URL="${BUNDLE_URL}.sha256"
SHA_FILE="${BUNDLE_FILE}.sha256"
BUNDLE_ROOT="$INSTALL_DIR/vadcop_bundle_portable_v2"

download_or_copy() {
  local src_url="$1"
  local dst_file="$2"

  if [[ "$src_url" == file://* ]]; then
    local src_path="${src_url#file://}"
    if [[ ! -f "$src_path" ]]; then
      echo "Local file not found: $src_path"
      exit 1
    fi
    local src_abs dst_abs
    src_abs="$(readlink -f "$src_path")"
    dst_abs="$(readlink -f "$dst_file" 2>/dev/null || true)"
    if [[ "$src_abs" == "$dst_abs" ]]; then
      return 0
    fi
    cp -f "$src_path" "$dst_file"
  else
    curl -fL "$src_url" -o "$dst_file"
  fi
}

# === Extract bundle (skip if already installed) ===
if [[ -f "$BUNDLE_ROOT/.installed" ]]; then
  echo "Bundle already installed at: $BUNDLE_ROOT"
else
  # === Download bundle + checksum ===
  download_or_copy "$BUNDLE_URL" "$BUNDLE_FILE"
  download_or_copy "$SHA_URL" "$SHA_FILE"

  # === Verify checksum ===
  EXPECTED_SHA="$(awk '{print $1}' "$SHA_FILE" | head -n 1)"
  ACTUAL_SHA="$(sha256sum "$BUNDLE_FILE" | awk '{print $1}')"
  if [[ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
    echo "sha256 mismatch: expected $EXPECTED_SHA, got $ACTUAL_SHA"
    exit 1
  fi

  mkdir -p "$INSTALL_DIR"
  tar -I 'zstd -d' -xf "$BUNDLE_FILE" -C "$INSTALL_DIR"
  touch "$BUNDLE_ROOT/.installed"
fi

# === Copy ZisK cache ===
if [[ -d "$BUNDLE_ROOT/zisk_cache" ]]; then
  mkdir -p "$HOME/.zisk/cache"
  cp -a "$BUNDLE_ROOT/zisk_cache/." "$HOME/.zisk/cache/" || true
fi

# === Export env vars ===
export VENUS_DIR="$BUNDLE_ROOT/venus"
export VENUS_PROVER_BIN="$VENUS_DIR/target/release/venus-prover"
export VENUS_INPUT_GEN_BIN="$VENUS_DIR/guest/zisk-eth-client/target/release/input-gen"
export VENUS_OUT_DIR="$VENUS_DIR/tmp"
export VENUS_VERKEY_PATH="$VENUS_DIR/build/provingKey/zisk/vadcop_final/vadcop_final.verkey.bin"
export LD_LIBRARY_PATH="$BUNDLE_ROOT/lib:${LD_LIBRARY_PATH:-}"

# === Validate expected files ===
missing=0
for p in "$VENUS_PROVER_BIN" "$VENUS_INPUT_GEN_BIN" "$VENUS_VERKEY_PATH"; do
  if [[ ! -f "$p" ]]; then
    echo "Missing: $p"
    missing=1
  fi
done
if ! ls "$BUNDLE_ROOT/lib"/libstd-*.so >/dev/null 2>&1; then
  echo "Missing: $BUNDLE_ROOT/lib/libstd-*.so (bundle Rust stdlib)"
  missing=1
fi
if [[ "$missing" -ne 0 ]]; then
  echo "Bundle not installed correctly at: $INSTALL_DIR"
  exit 2
fi

# === Download prover server binary if missing ===
if [[ ! -x "$PROVER_BIN" ]]; then
  curl -fL "$PROVER_RELEASE_BASE_URL/venus_prover_server" -o "$PROVER_BIN"
  chmod +x "$PROVER_BIN"
fi

# === Start prover0 ===
VENUS_PROVER_GRPC_PORT="$PORT" \
  HTTP_RPC_URL="$ETH_PROOF_ENDPOINT" \
  VENUS_OUT_DIR="$VENUS_OUT_DIR/prover_$PORT" \
  ASM_UNLOCK=true \
  RUST_LOG=info \
  "$PROVER_BIN" &

sleep 2
if ss -ltnp | rg -q ":${PORT}\\b"; then
  echo "Prover is running on port $PORT"
else
  echo "WARNING: Prover is not listening on port $PORT"
fi
