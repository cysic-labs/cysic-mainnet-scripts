#!/bin/bash

# 检查是否传入了参数
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <claim_reward_address> <eth_proof_endpoint>"
  exit 1
fi

CLAIM_REWARD_ADDRESS=$1
ETH_PROOF_ENDPOINT=$2

# 第一段命令：删除旧的cysic-prover目录，创建新的目录，并下载必要的文件
rm -rf ~/cysic-prover
cd ~
mkdir cysic-prover

curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/prover_linux >~/cysic-prover/prover
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/libdarwin_prover.so >~/cysic-prover/libzkp.so
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/libcysnet_monitor.so >~/cysic-prover/libcysnet_monitor.so
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/librsp_prover.so >~/cysic-prover/librsp.so
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/eth_dependency.sh >~/cysic-prover/eth_dependency.sh
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/host_cuda_prover >~/cysic-prover/host_cuda_prover
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/imetadata.bin >~/cysic-prover/imetadata.bin

# 第二段命令：创建配置文件
cat <<EOF >~/cysic-prover/config.yaml
chain:
  # node grpc url
  endpoint: "grpc01.prover.xyz:9090"
  # chain id, don't modify this
  chain_id: "cysicmint_4399-1"
  # chain gas coin, don't modify this
  gas_coin: "CYS"
  # gas price, don't modify this
  gas_price: 250000000000
  # gas limit, default: 100000000
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
# bid price (required)
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
  - ethProof
  - scroll

# task type specific configuration
task_config:
  # scroll task configuration
  scroll:
    # scroll l2 endpoint
    l2_endpoint: "https://sepolia-rpc.scroll.io"
  # eth proof task configuration
  eth_proof:
    # eth proof endpoint
    endpoint: "$ETH_PROOF_ENDPOINT"
EOF

# 第三段命令：设置执行权限并启动verifier
cd ~/cysic-prover/
chmod +x ~/cysic-prover/prover
chmod +x ~/cysic-prover/host_cuda_prover
echo "SP1_PROVER=cuda LD_LIBRARY_PATH=. CHAIN_ID=534352 ./prover" >~/cysic-prover/start.sh
chmod +x ~/cysic-prover/start.sh

# 询问用户是否运行 eth_dependency.sh
read -p "do you want to setup the software env for eth proof, this will install sp1, cuda driver and docker for you. (y/n): " choice
case "$choice" in
y | Y)
  bash eth_dependency.sh
  ;;
n | N)
  echo "skip to run the eth_dependency.sh"
  ;;
*)
  echo "invalid choice input eth_dependency.sh"
  ;;
esac

echo "Cysic prover setup is complete. Run ./start.sh to start the prover."

