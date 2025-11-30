[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RemoteHost,
    [Parameter(Mandatory = $true)][string]$Username,
    [int]$Port = 22,
    [ValidateSet('ed25519', 'rsa')][string]$KeyType = 'ed25519',
    [string]$KeyPath,
    [string]$HostAlias,
    [bool]$ManageServer = $true,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# 解析主目录与 ~/.ssh 目录
$userHome = [Environment]::GetFolderPath('UserProfile')
if ([string]::IsNullOrWhiteSpace($userHome)) {
    if ($env:USERPROFILE -and $env:USERPROFILE.Trim().Length -gt 0) { $userHome = $env:USERPROFILE }
    elseif ($env:HOME -and $env:HOME.Trim().Length -gt 0) { $userHome = $env:HOME }
    else { try { $userHome = (Resolve-Path ~).Path } catch { $userHome = $pwd.Path } }
}
$sshDir = $null
if ($userHome -and $userHome.Trim().Length -gt 0) {
    $sshDir = [System.IO.Path]::Combine($userHome, '.ssh')
}
else {
    $sshDir = [System.IO.Path]::Combine($pwd.Path, '.ssh')
}
if (-not $DryRun) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
if ($DryRun) { 
    Write-Output ("HOME=" + $userHome); 
    Write-Output ("SSHDir=" + $sshDir);
    Write-Output ("CombineTest=" + [System.IO.Path]::Combine('C:\\test', 'id_ed25519'));
    Write-Output ("KeyType=" + $KeyType)
    Write-Output ("CombineHomeSsh=" + [System.IO.Path]::Combine($userHome, '.ssh'))
    Write-Output ("CombineDefaultKey=" + [System.IO.Path]::Combine($userHome, '.ssh', ('id_' + $KeyType)))
    Write-Output ("RemoteHost=" + $RemoteHost)
}

# 依赖检测（ssh / ssh-keygen）
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { throw 'ssh not found. Please install OpenSSH client.' }
if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) { throw 'ssh-keygen not found. Please install OpenSSH client.' }

# 计算密钥路径与公钥路径
$defaultKeyPath = [System.IO.Path]::Combine($userHome, '.ssh', ('id_' + $KeyType))
if ([string]::IsNullOrWhiteSpace($KeyPath)) { $KeyPath = [System.IO.Path]::Combine($userHome, '.ssh', ('id_' + $KeyType)) }
$pubPath = "${KeyPath}.pub"
if ($DryRun) { Write-Output ("DefaultKeyPath=" + $defaultKeyPath); Write-Output ("KeyPath=" + $KeyPath); Write-Output ("PubPath=" + $pubPath) }

# 生成密钥（若不存在）
if (-not (Test-Path $KeyPath)) {
    $userLocal = if ($env:USER) { $env:USER } else { $env:USERNAME }
    $machineLocal = [Environment]::MachineName
    $comment = "$userLocal@$machineLocal"
    if ($DryRun) {
        Write-Output ("Generate key: " + $KeyPath + " type: " + $KeyType)
    }
    else {
        & ssh-keygen -t $KeyType -f $KeyPath -N "" -C $comment | Out-Null
    }
}

# 公钥准备（DryRun 时容忍不存在）
$pubKeyOutput = $null
if (Test-Path $pubPath) {
    $pubKeyOutput = (Get-Content -Path $pubPath -Raw).Trim()
}
else {
    if ($DryRun) {
        Write-Output ("Missing public key: " + $pubPath + " (will be created)")
        $pubKeyOutput = 'PUBKEY_PLACEHOLDER'
    }
    else {
        throw ("Public key not found: " + $pubPath)
    }
}

# Host 别名（用于 VSCode 配置）
$aliasToWrite = $HostAlias
if ([string]::IsNullOrWhiteSpace($aliasToWrite)) { $aliasToWrite = "ssh-" + $RemoteHost }
if ($DryRun) { Write-Output ("HostAlias=" + $aliasToWrite) }

# 优先使用 ssh-copy-id（Linux/macOS 常见），回退到 ssh 远程命令
$hasCopyId = [bool](Get-Command ssh-copy-id -ErrorAction SilentlyContinue)
$login = $Username + '@' + $RemoteHost
if ($hasCopyId) {
    if ($DryRun) {
        Write-Output ("ssh-copy-id -i '" + $pubPath + "' -p " + $Port + " " + $login)
    }
    else {
        & ssh-copy-id -i $pubPath -p $Port $login
    }
}
else {
    $hasScp = [bool](Get-Command scp -ErrorAction SilentlyContinue)
    if ($hasScp) {
        $tmpRemote = "~/.__tmp_id_key.pub"
        if ($DryRun) {
            Write-Output ("scp -P " + $Port + " '" + $pubPath + "' " + $login + ":" + $tmpRemote)
            Write-Output ("ssh -p " + $Port + " " + $login + " mkdir -p ~/.ssh; chmod 700 ~/.ssh; cat " + $tmpRemote + " >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; rm -f " + $tmpRemote)
        }
        else {
            & scp -P $Port $pubPath ($login + ":" + $tmpRemote)
            & ssh -p $Port $login ("mkdir -p ~/.ssh; chmod 700 ~/.ssh; cat " + $tmpRemote + " >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; rm -f " + $tmpRemote)
        }
    }
    else {
        $remoteCmd = "mkdir -p ~/.ssh; chmod 700 ~/.ssh; echo '" + $pubKeyOutput + "' >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys"
        if ($DryRun) {
            Write-Output ("ssh -p " + $Port + " " + $login + " " + $remoteCmd)
        }
        else {
            & ssh -p $Port $login $remoteCmd
        }
    }
}

# 可选：远端服务/权限检查（不强制变更）
if ($ManageServer) {
    $svcCheck = "if command -v systemctl >/dev/null 2>&1; then systemctl is-active ssh; systemctl is-active sshd; fi"
    if ($DryRun) {
        Write-Output ("ssh -p " + $Port + " " + $login + " " + $svcCheck)
    }
    else {
        try { & ssh -p $Port $login $svcCheck } catch { }
    }
    $macEnable = "if command -v systemsetup >/dev/null 2>&1; then sudo -n systemsetup -setremotelogin on; fi"
    if ($DryRun) {
        Write-Output ("ssh -p " + $Port + " " + $login + " " + $macEnable)
    }
    else {
        try { & ssh -p $Port $login $macEnable } catch { }
    }
}

# 验证已追加公钥
$verifyCmd = "grep -F '" + $pubKeyOutput + "' ~/.ssh/authorized_keys >/dev/null 2>&1 && echo OK || echo MISSING"
if ($DryRun) {
    Write-Output ("ssh -p " + $Port + " " + $login + " " + $verifyCmd)
}
else {
    try {
        $verify = & ssh -p $Port $login $verifyCmd
        if (-not ($verify -match 'OK')) { throw "Failed to append public key to remote authorized_keys" }
    }
    catch { throw $_ }
}

# 写入 ~/.ssh/config（避免重复追加）
$configFile = [System.IO.Path]::Combine($sshDir, 'config')
if ($DryRun) {
    Write-Output ("Write ~/.ssh/config alias: " + $aliasToWrite)
    Write-Output ("ConfigFile=" + $configFile)
}
else {
    if (-not (Test-Path $configFile)) { New-Item -ItemType File -Path $configFile | Out-Null }
    $exists = $false
    if (Test-Path $configFile) {
        $exists = Select-String -Path $configFile -Pattern ("^Host\s+" + [regex]::Escape($Alias)) -Quiet
    }
    if (-not $exists) {
        $entry = "Host " + $aliasToWrite + "`n    HostName " + $RemoteHost + "`n    User " + $Username + "`n    IdentityFile " + $KeyPath + "`n    Port " + $Port + "`n    PreferredAuthentications publickey"
        Add-Content -Path $configFile -Value $entry
    }
}

# 完成提示
Write-Output ("Done: use alias '" + $aliasToWrite + "'")
<#
.SYNOPSIS
    跨平台 SSH 免密登录配置脚本

.DESCRIPTION
    自动化完成免密 SSH 的关键步骤：
    1. 生成本机 SSH 密钥（若不存在，默认 ed25519）
    2. 将公钥追加到远端用户的 ~/.ssh/authorized_keys 并修正权限
    3. 写入本机 ~/.ssh/config（VSCode 兼容的 Host 别名）
    支持 DryRun 预览，将不会修改系统状态。

.PARAMETER RemoteHost
    目标主机的 IP 或域名，例如 192.168.1.10 或 server.local。

.PARAMETER Username
    目标主机登录用户名，例如 ubuntu、mac_user。

.PARAMETER Port
    SSH 端口，默认 22。

.PARAMETER KeyType
    密钥类型：ed25519 或 rsa，默认 ed25519。

.PARAMETER KeyPath
    密钥路径，默认 ~/.ssh/id_{KeyType}。

.PARAMETER HostAlias
    写入 ~/.ssh/config 的 Host 别名，默认 ssh-{RemoteHost}。

.PARAMETER ManageServer
    是否执行远端服务/权限检查，默认 true（非强制变更）。

.PARAMETER DryRun
    仅输出将执行的操作，不进行实际更改。

.EXAMPLE
    .\Setup-SshNoPasswd.ps1 -RemoteHost 192.168.1.10 -Username user
    使用默认端口 22 与 ed25519，在本机生成密钥、将公钥追加到远端并写入 ~/.ssh/config。

.EXAMPLE
    .\Setup-SshNoPasswd.ps1 -RemoteHost server.example.com -Username ubuntu -Port 2222 -Alias ssh-server -KeyType rsa
    使用自定义端口与 rsa 密钥类型，并指定连接别名。

.NOTES
    - 本机需安装 OpenSSH（ssh、ssh-keygen）。
    - 远端需开启 SSH 登录且防火墙放行对应端口。
#>
