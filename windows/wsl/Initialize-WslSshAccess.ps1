<#
.SYNOPSIS
    配置或验证 Windows 到 WSL 的稳定 SSH 管理入口。
.PARAMETER Distribution
    已注册的 WSL 发行版名称。
.PARAMETER WindowsUser
    运行 AtStartup S4U task 的 Windows 用户。
.PARAMETER LinuxUser
    WSL SSH 用户。
.PARAMETER ListenAddress
    Windows portproxy 监听地址，默认 0.0.0.0。
.PARAMETER ListenPort
    Windows portproxy 监听端口，默认 2222。
.PARAMETER GuestPort
    WSL sshd 端口，默认 22。
.PARAMETER RemoteAddress
    Windows firewall remote allowlist。
.PARAMETER AuthorizedKeyPath
    单个 OpenSSH 公钥文件路径。
.PARAMETER Apply
    执行真实配置；默认只生成计划。
.PARAMETER Verify
    只读验证现有状态。
.PARAMETER Rollback
    精确删除本功能托管资源。
.PARAMETER OutputFormat
    Text 或 Json。
.OUTPUTS
    单个 schema v1 状态文档。
#>
[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu-22.04',
    [string]$WindowsUser = $env:USERNAME,
    [string]$LinuxUser = $env:USERNAME,
    [string]$ListenAddress = '0.0.0.0',
    [int]$ListenPort = 2222,
    [int]$GuestPort = 22,
    [string[]]$RemoteAddress = @('LocalSubnet', '100.64.0.0/10'),
    [string]$AuthorizedKeyPath,
    [switch]$Apply,
    [switch]$Verify,
    [switch]$Rollback,
    [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (@(@($Apply, $Verify, $Rollback) | Where-Object { $_.IsPresent }).Count -gt 1) {
    [Console]::Error.WriteLine('Apply, Verify and Rollback are mutually exclusive')
    exit 2
}
$operation = if ($Rollback) { 'Rollback' } elseif ($Verify) { 'Verify' } elseif ($Apply) { 'Apply' } else { 'Plan' }
$modulePath = Join-Path $PSScriptRoot 'WslSshAccess.psm1'
$runtimeHelperPath = Join-Path $PSScriptRoot 'Invoke-WslSshAccessRefresh.ps1'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$guestScriptPath = Join-Path $repoRoot 'linux/wsl/prepare-ssh-access.sh'
Import-Module $modulePath -Force

$publicKey = ''
if (-not $Rollback) {
    if ([string]::IsNullOrWhiteSpace($AuthorizedKeyPath) -or -not (Test-Path -LiteralPath $AuthorizedKeyPath -PathType Leaf)) {
        $document = [pscustomobject]@{
            SchemaVersion = 1; Platform = 'Windows/WSL'; Operation = $operation; Status = 'Invalid'; ExitCode = 2
            Changed = $false; Errors = @('AuthorizedKeyPath must reference an existing public key file')
        }
        if ($OutputFormat -eq 'Json') { [Console]::Out.WriteLine(($document | ConvertTo-Json -Depth 8 -Compress)) }
        else { [Console]::Out.WriteLine('[Invalid] AuthorizedKeyPath must reference an existing public key file') }
        exit 2
    }
    $publicKey = Get-Content -LiteralPath $AuthorizedKeyPath -Raw
}

$document = Invoke-WslSshAccess -Operation $operation -Distribution $Distribution `
    -WindowsUser $WindowsUser -LinuxUser $LinuxUser -ListenAddress $ListenAddress `
    -ListenPort $ListenPort -GuestPort $GuestPort -RemoteAddress $RemoteAddress `
    -PublicKey $publicKey -GuestScriptPath $guestScriptPath -RuntimeHelperSource $runtimeHelperPath

if ($OutputFormat -eq 'Json') {
    [Console]::Out.WriteLine(($document | ConvertTo-Json -Depth 12 -Compress))
}
else {
    [Console]::Out.WriteLine("[$($document.Status)] operation=$operation changed=$($document.Changed) distribution=$Distribution listen=${ListenAddress}:$ListenPort")
    foreach ($errorMessage in @($document.Errors)) {
        [Console]::Error.WriteLine($errorMessage)
    }
}
exit [int]$document.ExitCode
