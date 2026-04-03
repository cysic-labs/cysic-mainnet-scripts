#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVER_HOME="${PROVER_HOME:-$HOME/cysic-prover}"
PROVER_SOURCE="${PROVER_SOURCE:-$SCRIPT_DIR/prover_linux}"
CONFIG_PATH="${CONFIG_PATH:-$PROVER_HOME/config.yaml}"
INSTALL_AND_START_URL="${INSTALL_AND_START_URL:-https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/venus-prover-community-v0.1.16/install_and_start_prover.sh}"
INSTALL_AND_START_PATH="${INSTALL_AND_START_PATH:-$PROVER_HOME/install_and_start_prover.sh}"

require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "$path" ]]; then
    echo "$label not found: $path" >&2
    exit 1
  fi
}

add_venus_task_type() {
  local config_path="$1"
  local tmp_file

  if rg -q '^[[:space:]]*-[[:space:]]*venus[[:space:]]*$' "$config_path"; then
    echo "venus task type already present in $config_path"
    return 0
  fi

  tmp_file="$(mktemp)"
  awk '
    BEGIN {
      in_available_task_type = 0
      inserted = 0
    }

    /^available_task_type:[[:space:]]*$/ {
      print
      in_available_task_type = 1
      next
    }

    in_available_task_type && /^[[:space:]]*-[[:space:]]/ {
      print
      next
    }

    in_available_task_type && !inserted {
      print "  - venus"
      inserted = 1
      in_available_task_type = 0
    }

    {
      print
    }

    END {
      if (in_available_task_type && !inserted) {
        print "  - venus"
      }
    }
  ' "$config_path" >"$tmp_file"

  mv "$tmp_file" "$config_path"
  echo "Added venus task type to $config_path"
}

require_file "$PROVER_SOURCE" "prover_linux source"
require_file "$CONFIG_PATH" "config.yaml"

mkdir -p "$PROVER_HOME"

cp "$PROVER_SOURCE" "$PROVER_HOME/prover"
chmod +x "$PROVER_HOME/prover"
echo "Updated $PROVER_HOME/prover"

add_venus_task_type "$CONFIG_PATH"

curl -L --fail "$INSTALL_AND_START_URL" -o "$INSTALL_AND_START_PATH"
chmod +x "$INSTALL_AND_START_PATH"
echo "Downloaded $INSTALL_AND_START_PATH"

echo "Starting Venus prover setup..."
bash "$INSTALL_AND_START_PATH"
