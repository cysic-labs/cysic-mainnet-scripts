cd $env:USERPROFILE

Invoke-WebRequest -Uri "https://github.com/cysic-labs/cysic-mainnet-scripts/releases/download/v1.0.0/decryptor_win" -OutFile "cysic-verifier\data\assets\decryptor.exe"

$decryptorPath = ".\data\assets\decryptor.exe"
$decryptorPath