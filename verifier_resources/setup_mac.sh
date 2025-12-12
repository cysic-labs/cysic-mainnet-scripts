#!/bin/bash

# 检查是否传入了参数
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <claim_reward_address>"
  exit 1
fi

CLAIM_REWARD_ADDRESS=$1

# 第一段命令：删除旧的cysic-verifier目录，创建新的目录，并下载必要的文件
rm -rf ~/cysic-verifier
cd ~
mkdir cysic-verifier
if [[ $(uname -m) == "x86_64" ]]; then
  # Intel chip
  # M series chip
  curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/verifier_mac_intel >~/cysic-verifier/verifier_mac
  curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/libzkp_intel.dylib >~/cysic-verifier/libzkp.dylib
  curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/librsp_intel.dylib >~/cysic-verifier/librsp.dylib
else
  # M series chip
  curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/verifier_mac >~/cysic-verifier/verifier_mac
  curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/libzkp.dylib >~/cysic-verifier/libzkp.dylib
  curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/librsp.dylib >~/cysic-verifier/librsp.dylib
fi

# 第二段命令：创建配置文件
cat <<EOF >~/cysic-verifier/config.yaml
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

#######################
#  verifier  setting  #
#######################
asset_path: ./data/assets
claim_reward_address: "$CLAIM_REWARD_ADDRESS"

######################
#   normal  setting   #
######################
server:
  # don't modify this
  cysic_endpoint: "https://api.prover.xyz"
  verify_endpoint: "https://checkproof01.prover.xyz:50051"
  env_chain_id: 534352
EOF

# 第三段命令：设置执行权限并启动verifier
cd ~/cysic-verifier/
chmod +x ~/cysic-verifier/verifier_mac
echo "DYLD_LIBRARY_PATH=. CHAIN_ID=534352 ./verifier_mac" >~/cysic-verifier/start.sh
chmod +x ~/cysic-verifier/start.sh