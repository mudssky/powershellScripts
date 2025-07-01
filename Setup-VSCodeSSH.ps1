<#
.SYNOPSIS
    配置VS Code SSH连接的自动化脚本

.DESCRIPTION
    该脚本自动化配置VS Code远程SSH连接的整个过程，包括：
    1. 生成SSH密钥对（如果不存在）
    2. 将公钥复制到远程服务器
    3. 配置SSH config文件以便VS Code使用
    完成后可以在VS Code中直接使用配置的主机名进行连接。

.PARAMETER Username
    远程服务器的用户名

.PARAMETER RemoteHost
    远程服务器的主机名或IP地址

.EXAMPLE
    .\Setup-VSCodeSSH.ps1 -Username "user" -RemoteHost "192.168.1.100"
    为指定的远程主机配置SSH连接

.EXAMPLE
    .\Setup-VSCodeSSH.ps1 -Username "admin" -RemoteHost "server.example.com"
    为域名主机配置SSH连接

.NOTES
    需要安装OpenSSH客户端
    首次连接时可能需要输入远程服务器密码
    生成的SSH密钥位于 ~/.ssh/id_rsa
    配置完成后在VS Code中使用 'vscode-{RemoteHost}' 作为连接名
#>
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