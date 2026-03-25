#!/bin/bash

cd ~
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/latest/download/decryptor_linux >~/cysic-verifier/data/assets/decryptor

cd ~/cysic-verifier/data/assets
chmod +x ~/cysic-verifier/data/assets/decryptor
./data/assets/decryptor
