
<#
.SYNOPSIS
    为远程Linux主机设置SSH密钥认证。

.DESCRIPTION
    此函数会生成SSH密钥对，并将公钥复制到指定的远程Linux主机，实现免密码登录。

.PARAMETER RemoteUser
    远程Linux主机的用户名。

.PARAMETER RemoteHost
    远程Linux主机的地址或域名。

.PARAMETER Passphrase
    已弃用的兼容参数。为避免口令出现在原生进程参数中，仅允许空字符串；非空值会被拒绝。

.PARAMETER PromptForPassphrase
    让 ssh-keygen 在终端中交互式读取口令。启用后不会向原生进程参数传递 `-N`。

.OUTPUTS
    System.Boolean
    SSH 密钥认证设置成功时返回 true，失败时返回 false。

.EXAMPLE
    Set-SSHKeyAuth -RemoteUser "ubuntu" -RemoteHost "192.168.1.100"
    为用户ubuntu在IP为192.168.1.100的远程主机设置SSH密钥认证。

.NOTES
    需要确保本地已安装SSH客户端，且远程主机可以通过SSH访问。
    非空口令必须使用 PromptForPassphrase 交互输入，不能通过 Passphrase 参数传递。
#>
function Set-SSHKeyAuth {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingUsernameAndPasswordParams',
        '',
        Justification = 'Passphrase 仅作为旧参数名兼容且拒绝非空值；远程用户不与认证密码组合使用。'
    )]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingPlainTextForPassword',
        '',
        Justification = 'Passphrase 仅允许空字符串，非空口令必须由 ssh-keygen 交互读取。'
    )]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [string]$RemoteUser,
        
        [Parameter(Mandatory = $true)]
        [string]$RemoteHost,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Passphrase = '',

        [Parameter(Mandatory = $false)]
        [switch]$PromptForPassphrase
    )

    try {
        if (-not [string]::IsNullOrEmpty($Passphrase)) {
            throw '为避免口令暴露在进程参数中，不再支持非空 Passphrase。请改用 PromptForPassphrase 交互输入。'
        }
        if ($PromptForPassphrase -and $PSBoundParameters.ContainsKey('Passphrase')) {
            throw 'PromptForPassphrase 与 Passphrase 不能同时使用。'
        }
        if ($RemoteUser.StartsWith('-') -or $RemoteUser -match '[@\s]') {
            throw 'RemoteUser 不能以连字符开头，也不能包含空白或 @。'
        }
        if ($RemoteHost.StartsWith('-') -or $RemoteHost -match '[@\s]') {
            throw 'RemoteHost 不能以连字符开头，也不能包含空白或 @。'
        }

        # 检查SSH客户端是否安装
        if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
            throw "未找到SSH客户端，请确保已安装SSH工具。"
        }
        if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
            throw "未找到ssh命令，请确保已安装SSH工具。"
        }
        if (-not $PSCmdlet.ShouldProcess(
                "$RemoteUser@$RemoteHost",
                '生成本地 SSH 密钥并追加远程 authorized_keys'
            )) {
            return $false
        }

        # 检查远程主机连接性
        if (-not (Test-Connection -ComputerName $RemoteHost -Count 1 -Quiet)) {
            throw "无法连接到远程主机 $RemoteHost"
        }

        if ([string]::IsNullOrWhiteSpace($HOME)) {
            throw '无法确定当前用户 HOME 目录。'
        }

        # PowerShell 的 HOME 在 Windows、Linux 和 macOS 上都指向当前用户主目录。
        $sshDir = Join-Path $HOME '.ssh'
        if (-not (Test-Path -LiteralPath $sshDir)) {
            New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        }

        # 生成 SSH 密钥
        $keyPath = Join-Path $sshDir 'id_rsa'
        if (Test-Path -LiteralPath $keyPath) {
            $confirmation = Read-Host "SSH密钥已存在。是否要覆盖？(Y/N)"
            if ($confirmation -ne 'Y') {
                throw "操作已取消"
            }
        }
        
        $keygenArgs = @('-t', 'rsa', '-b', '4096', '-f', $keyPath, '-q')
        if (-not $PromptForPassphrase) {
            $keygenArgs += @('-N', '')
        }

        $result = ssh-keygen @keygenArgs
        if ($LASTEXITCODE -ne 0) {
            throw "生成SSH密钥失败: $result"
        }

        # 复制公钥到远程主机
        try {
            Get-Content -LiteralPath "$keyPath.pub" | ssh $RemoteUser@$RemoteHost `
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
