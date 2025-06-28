param(
    [string]$Username,
    [string]$RemoteHost
)

$SshKeyPath = "$env:USERPROFILE\.ssh\id_rsa"

# 1. 生成SSH密钥
if (-not (Test-Path $SshKeyPath)) {
    ssh-keygen -t rsa -b 4096 -f $SshKeyPath -N '""'
}

# 2. 复制公钥到服务器
$pubKey = Get-Content "$SshKeyPath.pub"
ssh $Username@$RemoteHost "mkdir -p ~/.ssh && echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"

# 3. 配置SSH config
$configFile = "$env:USERPROFILE\.ssh\config"
if (-not (Test-Path $configFile)) {
    New-Item -Path $configFile -ItemType File
}

$configEntry = @"
Host vscode-$RemoteHost
    HostName $RemoteHost
    User $Username
    IdentityFile $SshKeyPath
"@

if (-not (Select-String -Path $configFile -Pattern "vscode-$RemoteHost" -Quiet)) {
    Add-Content -Path $configFile -Value $configEntry
}

Write-Host "配置完成! 在VS Code中使用 'vscode-$RemoteHost' 连接"