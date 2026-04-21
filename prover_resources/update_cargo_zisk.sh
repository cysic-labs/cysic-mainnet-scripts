#!/usr/bin/env bash
set -euo pipefail

RELEASE_BASE_URL="${RELEASE_BASE_URL:-https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v2.0.1}"
VENUS_DIR="${VENUS_DIR:-$HOME/venus_v0_1_6}"
TARGET_PATH="${TARGET_PATH:-$VENUS_DIR/target/release/cargo-zisk}"
PORT="${PORT:-7000}"
GPU="${GPU:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVER_SERVER_BIN="${PROVER_SERVER_BIN:-$SCRIPT_DIR/venus_prover_server}"

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd not found" >&2
    exit 1
  fi
}

detect_gpu_name() {
  local query_args=(--query-gpu=name --format=csv,noheader)

  if [[ -n "$GPU" ]]; then
    query_args=(-i "$GPU" "${query_args[@]}")
  fi

  nvidia-smi "${query_args[@]}" | head -n 1 | sed 's/[[:space:]]*$//'
}

detect_compute_capability() {
  local query_args=(--query-gpu=compute_cap --format=csv,noheader)

  if [[ -n "$GPU" ]]; then
    query_args=(-i "$GPU" "${query_args[@]}")
  fi

  nvidia-smi "${query_args[@]}" 2>/dev/null | head -n 1 | tr -d '[:space:]'
}

asset_from_compute_capability() {
  local capability="$1"

  case "$capability" in
    7.5|7.5*) printf '%s\n' "cargo-zisk-sm75" ;;
    8.6|8.6*) printf '%s\n' "cargo-zisk-sm86" ;;
    8.9|8.9*) printf '%s\n' "cargo-zisk-sm89" ;;
    12.0|12.0*) printf '%s\n' "cargo-zisk-sm120" ;;
    *) return 1 ;;
  esac
}

asset_from_gpu_name() {
  local gpu_name="$1"

  case "$gpu_name" in
    *"RTX 20"*|*"T4"*)
      printf '%s\n' "cargo-zisk-sm75"
      ;;
    *"RTX 30"*|*"A10"*|*"A40"*|*"A30"*)
      printf '%s\n' "cargo-zisk-sm86"
      ;;
    *"RTX 40"*|*"L4"*|*"L40"*)
      printf '%s\n' "cargo-zisk-sm89"
      ;;
    *"RTX 50"*)
      printf '%s\n' "cargo-zisk-sm120"
      ;;
    *)
      return 1
      ;;
  esac
}

select_asset() {
  local capability="$1"
  local gpu_name="$2"

  if [[ -n "$capability" ]]; then
    if asset_from_compute_capability "$capability"; then
      return 0
    fi
  fi

  if asset_from_gpu_name "$gpu_name"; then
    return 0
  fi

  echo "Unsupported GPU. name=$gpu_name compute_capability=${capability:-unknown}" >&2
  echo "Supported targets: sm75, sm86, sm89, sm120" >&2
  exit 2
}

download_asset() {
  local asset_name="$1"
  local output_path="$2"
  local url="$RELEASE_BASE_URL/$asset_name"

  curl -L --fail --output "$output_path" "$url"
}

install_asset() {
  local asset_name="$1"
  local tmp_file

  mkdir -p "$(dirname "$TARGET_PATH")"
  tmp_file="$(mktemp)"
  trap 'rm -f "$tmp_file"' EXIT

  echo "Downloading $asset_name from $RELEASE_BASE_URL"
  download_asset "$asset_name" "$tmp_file"
  chmod +x "$tmp_file"
  mv "$tmp_file" "$TARGET_PATH"
  trap - EXIT

  echo "Installed $asset_name to $TARGET_PATH"
}

start_prover_server() {
  if [[ ! -x "$PROVER_SERVER_BIN" ]]; then
    echo "venus_prover_server not found or not executable: $PROVER_SERVER_BIN" >&2
    exit 1
  fi

  mkdir -p "$VENUS_DIR/tmp"

  echo "Starting venus_prover_server on port $PORT"
  local cmd=(env VENUS_PROVER_GRPC_PORT="$PORT" VENUS_DIR="$VENUS_DIR" VENUS_OUT_DIR="$VENUS_DIR/tmp" ASM_UNLOCK="${ASM_UNLOCK:-true}" RUST_LOG="${RUST_LOG:-info}")
  if [[ -n "$GPU" ]]; then
    cmd+=(CUDA_VISIBLE_DEVICES="$GPU")
  fi
  cmd+=("$PROVER_SERVER_BIN")
  exec "${cmd[@]}"
}

main() {
  local gpu_name
  local capability
  local asset_name

  require_command nvidia-smi
  require_command curl

  gpu_name="$(detect_gpu_name)"
  capability="$(detect_compute_capability || true)"
  asset_name="$(select_asset "$capability" "$gpu_name")"

  echo "Detected GPU: $gpu_name"
  if [[ -n "$capability" ]]; then
    echo "Detected compute capability: $capability"
  else
    echo "Compute capability query unavailable; using GPU name fallback"
  fi
  echo "Selected asset: $asset_name"

  install_asset "$asset_name"
  start_prover_server
}

main "$@"
