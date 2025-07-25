
<#
.SYNOPSIS
    为远程Linux主机设置SSH密钥认证。

.DESCRIPTION
    此函数会生成SSH密钥对，并将公钥复制到指定的远程Linux主机，实现免密码登录。

.PARAMETER RemoteUser
    远程Linux主机的用户名。

.PARAMETER RemoteHost
    远程Linux主机的地址或域名。

.EXAMPLE
    Set-SSHKeyAuth -RemoteUser "ubuntu" -RemoteHost "192.168.1.100"
    为用户ubuntu在IP为192.168.1.100的远程主机设置SSH密钥认证。

.NOTES
    需要确保本地已安装SSH客户端，且远程主机可以通过SSH访问。
#>
function Set-SSHKeyAuth {
    param (
        [Parameter(Mandatory = $true)]
        [string]$RemoteUser,
        
        [Parameter(Mandatory = $true)]
        [string]$RemoteHost,

        [Parameter(Mandatory = $false)]
        [string]$Passphrase = '""'
    )

    try {
        # 检查SSH客户端是否安装
        if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
            throw "未找到SSH客户端，请确保已安装SSH工具。"
        }

        # 检查远程主机连接性
        if (-not (Test-Connection -ComputerName $RemoteHost -Count 1 -Quiet)) {
            throw "无法连接到远程主机 $RemoteHost"
        }

        # 检查并创建.ssh目录
        $sshDir = "$env:USERPROFILE\.ssh"
        if (-not (Test-Path $sshDir)) {
            New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        }

        # 生成 SSH 密钥
        $keyPath = "$sshDir\id_rsa"
        if (Test-Path $keyPath) {
            $confirmation = Read-Host "SSH密钥已存在。是否要覆盖？(Y/N)"
            if ($confirmation -ne 'Y') {
                throw "操作已取消"
            }
        }
        
        $result = ssh-keygen -t rsa -b 4096 -f $keyPath -N $Passphrase -q
        if ($LASTEXITCODE -ne 0) {
            throw "生成SSH密钥失败: $result"
        }

        # 复制公钥到远程主机
        try {
            Get-Content "$keyPath.pub" | ssh $RemoteUser@$RemoteHost `
                "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
            if ($LASTEXITCODE -ne 0) {
                throw "复制公钥到远程主机失败"
            }
        }
        catch {
            throw "无法连接到远程主机或复制公钥失败: $_"
        }

        Write-Host "SSH 密钥认证已成功设置。" -ForegroundColor Green
    }
    catch {
        Write-Error "设置SSH密钥认证失败: $_"
        return $false
    }
    
    return $true
}

Export-ModuleMember -Function Set-SSHKeyAuth