cd $env:USERPROFILE

Invoke-WebRequest -Uri "https://github.com/cysic-labs/cysic-mainnet-scripts/releases/latest/download/decryptor_win" -OutFile "cysic-verifier\data\assets\decryptor.exe"

$decryptorPath = ".\data\assets\decryptor.exe"
$decryptorPath
