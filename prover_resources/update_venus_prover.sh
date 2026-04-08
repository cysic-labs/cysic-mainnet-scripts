#!/bin/bash
set -euo pipefail

PROVER_HOME="${PROVER_HOME:-$HOME/cysic-prover}"
PROVER_URL="${PROVER_URL:-https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v2.0.1/prover_linux}"
CONFIG_PATH="${CONFIG_PATH:-$PROVER_HOME/config.yaml}"
INSTALL_AND_START_URL="${INSTALL_AND_START_URL:-https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v2.0.1/install_and_start_prover.sh}"
INSTALL_AND_START_PATH="${INSTALL_AND_START_PATH:-$PROVER_HOME/install_and_start_prover.sh}"

require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "$path" ]]; then
    if [[ "$label" == "config.yaml" ]]; then
      echo "config.yaml not found: $path" >&2
      echo "update_venus_prover.sh is an upgrade script for an existing prover installation." >&2
      echo "Please run setup_prover.sh first to create $path, then rerun update_venus_prover.sh." >&2
    else
      echo "$label not found: $path" >&2
    fi
    exit 1
  fi
}

get_claim_reward_address() {
  local config_path="$1"
  local claim_reward_address

  claim_reward_address="$(sed -n 's/^[[:space:]]*claim_reward_address:[[:space:]]*"\{0,1\}\(.*[^"]\)\{0,1\}"\{0,1\}[[:space:]]*$/\1/p' "$config_path" | head -n1)"
  if [[ -z "$claim_reward_address" ]]; then
    echo "claim_reward_address not found in $config_path" >&2
    exit 1
  fi

  printf '%s\n' "$claim_reward_address"
}

rewrite_config() {
  local config_path="$1"
  local claim_reward_address="$2"

  cat <<EOF >"$config_path"
chain:
  endpoint: "grpc01.prover.xyz:9090"
  chain_id: "cysicmint_4399-1"
  gas_coin: "CYS"
  gas_price: 250000000000
  gas_limit: 300000

######################
#   local  setting   #
######################
# asset file storage path
asset_path: ./data/assets
# reward claim address
claim_reward_address: "$claim_reward_address"

# prover index (optional)
# index: 0
# bid price: adjust your bid price according to your machine price and reward policy to maximize your earnings
bid: "0.1"

######################
#   server  setting   #
######################
server:
  # cysic server endpoint
  cysic_endpoint: "https://api.prover.xyz"

######################
#   task  setting   #
######################
# available task types: ethProof, scroll
available_task_type:
  - venus
EOF

  echo "Rewrote $config_path for Venus prover"
}

require_file "$CONFIG_PATH" "config.yaml"
claim_reward_address="$(get_claim_reward_address "$CONFIG_PATH")"
downloaded_prover="$(mktemp)"

curl -L --fail "$PROVER_URL" -o "$downloaded_prover"
echo "Downloaded prover_linux from $PROVER_URL"

mkdir -p "$PROVER_HOME"

cp "$downloaded_prover" "$PROVER_HOME/prover"
rm -f "$downloaded_prover"
chmod +x "$PROVER_HOME/prover"
echo "Updated $PROVER_HOME/prover"

rewrite_config "$CONFIG_PATH" "$claim_reward_address"

curl -L --fail "$INSTALL_AND_START_URL" -o "$INSTALL_AND_START_PATH"
chmod +x "$INSTALL_AND_START_PATH"
echo "Downloaded $INSTALL_AND_START_PATH"

echo "Starting Venus prover setup..."
bash "$INSTALL_AND_START_PATH"
