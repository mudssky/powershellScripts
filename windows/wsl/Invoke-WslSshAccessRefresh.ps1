<#
.SYNOPSIS
    启动指定 WSL 发行版并刷新稳定 SSH portproxy。
.PARAMETER ConfigPath
    由 Initialize-WslSshAccess 安装的无敏感信息 JSON 配置。
.PARAMETER OutputFormat
    Text 或 Json。
.OUTPUTS
    单个状态文档；成功 0，失败 1，参数错误 2。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$configValidated = $false
$document = [ordered]@{
    schemaVersion = 1
    operation     = 'Refresh'
    status        = 'Invalid'
    exitCode      = 2
    changed       = $false
    wslIPv4       = ''
    message       = ''
}

try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "runtime config does not exist: $ConfigPath"
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ([int]$config.schemaVersion -ne 1 -or [string]$config.distribution -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$' -or
        [string]$config.listenAddress -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$' -or
        [string]$config.connectAddress -ne '127.0.0.1' -or
        [int]$config.listenPort -lt 1 -or [int]$config.listenPort -gt 65535 -or
        [int]$config.guestPort -lt 1 -or [int]$config.guestPort -gt 65535) {
        throw 'runtime config contract is invalid'
    }
    $configValidated = $true
    # WSL NAT localhost relay 只在 guest listener 重新 bind 时可靠刷新。
    & wsl.exe -d ([string]$config.distribution) -u root -- systemctl restart ssh 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'cannot start WSL ssh.service'
    }
    $rawAddresses = [string]((& wsl.exe -d ([string]$config.distribution) -- hostname -I 2>$null) -join ' ')
    $addresses = (($rawAddresses -replace [char]0, '').Trim() -split '\s+')
    $wslIPv4 = @($addresses | Where-Object { $_ -match '^\d{1,3}(?:\.\d{1,3}){3}$' -and $_ -notmatch '^127\.' })[0]
    if ([string]::IsNullOrWhiteSpace($wslIPv4)) {
        throw 'cannot resolve WSL IPv4'
    }
    $relayReady = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        $client = New-Object Net.Sockets.TcpClient
        try {
            $client.Connect([string]$config.connectAddress, [int]$config.guestPort)
            $relayReady = $true
        }
        catch {
            Start-Sleep -Seconds 1
        }
        finally {
            $client.Dispose()
        }
    } while (-not $relayReady -and [DateTime]::UtcNow -lt $deadline)
    if (-not $relayReady) {
        throw 'WSL localhost relay is not ready'
    }
    $show = [string]((& netsh.exe interface portproxy show v4tov4) -join "`n")
    $pattern = "(?m)^\s*$([regex]::Escape([string]$config.listenAddress))\s+$([int]$config.listenPort)\s+$([regex]::Escape([string]$config.connectAddress))\s+$([int]$config.guestPort)\s*$"
    if ($show -notmatch $pattern) {
        & netsh.exe interface portproxy delete v4tov4 "listenaddress=$([string]$config.listenAddress)" "listenport=$([int]$config.listenPort)" 2>$null | Out-Null
        & netsh.exe interface portproxy add v4tov4 "listenaddress=$([string]$config.listenAddress)" "listenport=$([int]$config.listenPort)" "connectaddress=$([string]$config.connectAddress)" "connectport=$([int]$config.guestPort)" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'cannot update WSL SSH portproxy'
        }
        $document.changed = $true
    }
    $document.status = 'Succeeded'
    $document.exitCode = 0
    $document.wslIPv4 = $wslIPv4
    $document.message = 'WSL SSH portproxy is ready'
}
catch {
    $document.status = if ($configValidated) { 'Failed' } else { 'Invalid' }
    $document.exitCode = if ($configValidated) { 1 } else { 2 }
    $document.message = $_.Exception.Message
}

if ($OutputFormat -eq 'Json') {
    [Console]::Out.WriteLine(($document | ConvertTo-Json -Depth 6 -Compress))
}
else {
    [Console]::Out.WriteLine("[$($document.status)] $($document.message)")
}
exit [int]$document.exitCode
