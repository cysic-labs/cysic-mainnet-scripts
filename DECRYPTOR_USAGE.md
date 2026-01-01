# (Optional) Convert Reward Address to Private Key

> **Warning:** Below command can convert the verifier reward address key file to private key.
> 
> This step is only needed if you want to use the private key for other operations. Don't share the private key with anyone.

Run Below command according to your operating system:

1. Linux: 
   ```bash
   cd ~/cysic-verifier
   curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/reward_address_decryptor_linux.sh > reward_address_decryptor_linux.sh
   bash reward_address_decryptor_linux.sh
   ```

2. MacOS: 

   ```bash
   cd ~/cysic-verifier
   curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/reward_address_decryptor_mac.sh > reward_address_decryptor_mac.sh
   bash reward_address_decryptor_mac.sh
   ```

3. Windows: 
   ```ps1
   cd $env:USERPROFILE\cysic-verifier
   Invoke-WebRequest -Uri "https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/reward_address_decryptor_win.ps1" -OutFile "reward_address_decryptor_win.ps1"
   .\reward_address_decryptor_win.ps1
   ```

Above command will do the following task:

- Download the decryptor script to the `~/cysic-verifier` folder.
- Execute the decryptor script, the script will do the following steps:
   - Download the decryptor program to the `~/cysic-verifier/data/assets/` folder.
   - Make the decryptor program executable.
   - Run the decryptor program(the program will try to decrypt the reward address key file in current folder and print the private key to the console. If you have other key files need to decrypt, please copy them to this folder and the program will decrypt them as well).

The output of the decryptor program will be similar to below:

```
read privatekey from current dir
found 1 privatekey file
==========================================
reward address: 0x6e1fC643be3fDBeA1d80BA7e6E373491246E60D6
	 privatekey: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
==========================================
```


# (Optional) Convert Reward Address to Private Key

> **Warning:** Below command can convert the prover reward address key file to private key.
> 
> This step is only needed if you want to use the private key for other operations. Don't share the private key with anyone.

```bash
cd ~/cysic-prover
curl -L https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/reward_address_decryptor_prover.sh > reward_address_decryptor_prover.sh
bash reward_address_decryptor_prover.sh
```
Above command will do the following task:

- Download the decryptor script to the `~/cysic-prover` folder.
- Execute the decryptor script, the script will do the following steps:
   - Download the decryptor program to the `~/cysic-prover/data/assets/` folder.
   - Make the decryptor program executable.
   - Run the decryptor program(the program will try to decrypt the reward address key file in current folder and print the private key to the console. If you have other key files need to decrypt, please copy them to this folder and the program will decrypt them as well).

The output of the decryptor program will be similar to below:

```
read privatekey from current dir
found 1 privatekey file
==========================================
reward address: 0x6e1fC643be3fDBeA1d80BA7e6E373491246E60D6
	 privatekey: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
==========================================
```