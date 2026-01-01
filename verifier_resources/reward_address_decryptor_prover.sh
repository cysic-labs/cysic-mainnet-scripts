#!/bin/bash

cd ~
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/decryptor_linux >~/cysic-prover/data/assets/decryptor

cd ~/cysic-prover/data/assets
chmod +x ~/cysic-prover/data/assets/decryptor
./data/assets/decryptor
