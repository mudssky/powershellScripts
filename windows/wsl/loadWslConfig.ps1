<#
.SYNOPSIS
    兼容入口：部署 WSL 宿主配置但不自动关闭 WSL。

.PARAMETER Distribution
    要确保存在的 WSL 发行版。

.PARAMETER WslConfigTargetPath
    用户级 .wslconfig 目标路径。

.OUTPUTS
    Initialize-WslHost.ps1 的文本结果和退出码。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Distribution = 'Ubuntu-24.04',

    [string]$WslConfigTargetPath = $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.wslconfig' } else { '' })
)

& (Join-Path $PSScriptRoot 'Initialize-WslHost.ps1') `
    -Distribution $Distribution `
    -WslConfigTargetPath $WslConfigTargetPath `
    -WhatIf:$WhatIfPreference
exit $LASTEXITCODE
