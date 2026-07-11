<#
.SYNOPSIS
    兼容入口：调用 Windows 09 叶子仅安装或验证 AutoHotkey v2。

.PARAMETER NetworkMode
    Direct、China 或 Auto。

.PARAMETER InstallerPath
    可选本地签名 AutoHotkey 安装包。

.PARAMETER Unattended
    允许本次调用出现一次 UAC。

.PARAMETER NonInteractive
    严格零提示；需要提升时返回 Blocked/10。

.OUTPUTS
    Windows 09 叶子的文本结果和退出码。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Direct', 'China', 'Auto')]
    [string]$NetworkMode = 'Direct',

    [string]$InstallerPath = '',

    [switch]$Unattended,

    [switch]$NonInteractive
)

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
& (Join-Path $repoRoot 'windows/09deployAutoHotkey.ps1') `
    -Preset Full `
    -NetworkMode $NetworkMode `
    -InstallerPath $InstallerPath `
    -InstallOnly `
    -Unattended:$Unattended `
    -NonInteractive:$NonInteractive `
    -WhatIf:$WhatIfPreference
exit $LASTEXITCODE
