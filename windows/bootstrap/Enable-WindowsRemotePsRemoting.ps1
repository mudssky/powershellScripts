<#
.SYNOPSIS
    配置或回滚仅绑定 Tailscale IPv4 的 Windows HTTPS PSRP listener。

.PARAMETER TailscaleIPv4
    可选显式 Tailscale IPv4；空值时从 Tailscale adapter 或 tailscale.exe 发现。

.PARAMETER Port
    HTTPS listener 端口，默认 5986。

.PARAMETER CertificateValidityYears
    新建自签名证书有效年数。

.PARAMETER Rollback
    删除本脚本管理的 listener、防火墙 rule 和证书，不修改 OpenSSH。

.PARAMETER OutputFormat
    Text 或 Json；Json stdout 只输出一个 document。

.OUTPUTS
    文本摘要或单个 JSON document。进程退出码为 0、1、2 或 10。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TailscaleIPv4 = '',

    [ValidateRange(1, 65535)]
    [int]$Port = 5986,

    [ValidateRange(1, 10)]
    [int]$CertificateValidityYears = 3,

    [switch]$Rollback,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'WindowsRemotePsRemoting.psm1') -Force

$document = Invoke-WindowsRemotePsRemoting `
    -TailscaleIPv4 $TailscaleIPv4 `
    -Port $Port `
    -CertificateValidityYears $CertificateValidityYears `
    -Rollback:$Rollback `
    -Preview:$WhatIfPreference

if ($OutputFormat -eq 'Json') {
    $document | ConvertTo-Json -Depth 10
}
else {
    Write-Output "[$($document.Status)] operation=$($document.Operation) exit=$($document.ExitCode) tailscale=$($document.TailscaleIPv4):$($document.Port)"
    foreach ($result in @($document.Results)) {
        Write-Output ("- {0}: {1} - {2}" -f $result.Name, $result.Status, $result.Message)
    }
    if ($document.RerunCommand) {
        Write-Output "Rerun: $($document.RerunCommand)"
    }
}

exit [int]$document.ExitCode
