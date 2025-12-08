# 设置环境变量
$env:CHAIN_ID="534352"

# 定义要执行的verifier路径
$verifierPath = ".\verifier.exe"

# 启动verifier进程
Write-Host "Starting verifier.exe process."
& $verifierPath