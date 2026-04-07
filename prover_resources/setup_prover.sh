#!/bin/bash

# 检查是否传入了参数
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <claim_reward_address>"
  exit 1
fi

CLAIM_REWARD_ADDRESS=$1

# 第一段命令：删除旧的cysic-prover目录，创建新的目录，并下载必要的文件
rm -rf ~/cysic-prover
cd ~
mkdir cysic-prover

curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/latest/download/prover_linux >~/cysic-prover/prover
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/latest/download/libdarwin_prover.so >~/cysic-prover/libzkp.so
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/latest/download/libcysnet_monitor.so >~/cysic-prover/libcysnet_monitor.so
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/latest/download/librsp_prover.so >~/cysic-prover/librsp.so
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v2.0.1/install_and_start_prover.sh >~/cysic-prover/install_and_start_prover.sh
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/latest/download/imetadata.bin >~/cysic-prover/imetadata.bin

# 第二段命令：创建配置文件
cat <<EOF >~/cysic-prover/config.yaml
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
claim_reward_address: "$CLAIM_REWARD_ADDRESS"

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

# 第三段命令：设置执行权限并启动verifier
cd ~/cysic-prover/
chmod +x ~/cysic-prover/prover
chmod +x ~/cysic-prover/install_and_start_prover.sh
echo "LD_LIBRARY_PATH=. CHAIN_ID=534352 ./prover" >~/cysic-prover/start.sh
chmod +x ~/cysic-prover/start.sh

echo "Starting Venus prover setup..."
echo "install_and_start_prover.sh manages its own dependencies and then execs venus_prover_server."
echo "If startup succeeds, this wrapper will not print any further completion message."
bash ~/cysic-prover/install_and_start_prover.sh
