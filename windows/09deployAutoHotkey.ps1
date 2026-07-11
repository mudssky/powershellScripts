<#
.SYNOPSIS
    安装或验证 AutoHotkey v2，并部署当前用户脚本与 Startup 快捷方式。

.PARAMETER Preset
    仅接受 Full。

.PARAMETER NetworkMode
    Direct、China 或 Auto。

.PARAMETER InstallerPath
    可选本地签名 AutoHotkey 安装包。

.PARAMETER StartupPath
    当前用户 Startup 目录；测试可传临时目录。

.PARAMETER InstallOnly
    只安装或验证 AutoHotkey，不构建用户脚本。

.PARAMETER Unattended
    允许独立调用出现一次 UAC。

.PARAMETER NonInteractive
    严格零提示；需要提升时返回 Blocked/10。

.OUTPUTS
    文本组件结果；失败退出 1，Blocked 退出 10。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Full')]
    [string]$Preset = 'Full',

    [ValidateSet('Direct', 'China', 'Auto')]
    [string]$NetworkMode = 'Direct',

    [string]$InstallerPath = '',

    [string]$StartupPath = '',

    [switch]$InstallOnly,

    [switch]$Unattended,

    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Unattended -and $NonInteractive) {
    [Console]::Error.WriteLine('Unattended 与 NonInteractive 不能同时使用')
    exit 2
}
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $repoRoot 'windows/pwsh/WindowsInstall.psm1') -Force
Import-Module (Join-Path $repoRoot 'windows/bootstrap/WindowsBootstrap.psm1') -Force
$platform = Get-WindowsInstallEnvironment
if (-not $WhatIfPreference -and ($platform.SupportLevel -ne 'Full' -or $platform.IsServer)) {
    [Console]::Error.WriteLine("当前平台不支持 AutoHotkey 自动部署: $($platform.Edition)/$($platform.Architecture)")
    exit 10
}
# 管理员进程不应执行真实用户态副作用；但 WhatIf 仅生成计划，需放行（见规范 Error Matrix）。
if (-not $WhatIfPreference -and $platform.IsAdministrator) {
    [Console]::Error.WriteLine('AutoHotkey Startup 配置必须由普通用户进程执行')
    exit 10
}

$results = [System.Collections.Generic.List[object]]::new()
if ($platform.HasAutoHotkey) {
    $results.Add((New-WindowsInstallResult -Name AutoHotkey -Status AlreadyPresent))
}
elseif ($env:POWERSHELL_SCRIPTS_BOOTSTRAP_SESSION -eq '1' -and -not $WhatIfPreference) {
    $results.Add((New-WindowsInstallResult -Name AutoHotkey -Status Blocked -Message '00 bootstrap 已消费提升边界，但 AutoHotkey 仍缺失；请独立重跑 09' -ExitCode 10))
}
else {
    $catalog = Import-WindowsBootstrapCatalog -Path (Join-Path $repoRoot 'config/install/windows-packages.psd1')
    $temporaryRoot = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
    $resolution = Resolve-WindowsBootstrapInstallOperation `
        -Name AutoHotkey `
        -PackageConfig $catalog.Packages.AutoHotkey `
        -LocalInstallerPath $InstallerPath `
        -NetworkMode $NetworkMode `
        -DownloadDirectory (Join-Path $temporaryRoot 'powershellScripts-bootstrap-downloads') `
        -Preview:$WhatIfPreference
    $results.Add($resolution.Result)
    if ($null -ne $resolution.Operation -and -not $WhatIfPreference) {
        if ($NonInteractive) {
            $results.Add((New-WindowsInstallResult -Name elevation -Status Blocked -Message '严格非交互模式无法请求 AutoHotkey 安装提升' -ExitCode 10))
        }
        else {
            $elevated = Invoke-WindowsBootstrapElevation `
                -Operation @($resolution.Operation) `
                -NetworkMode $NetworkMode `
                -ExecutorPath (Join-Path $repoRoot 'windows/bootstrap/Invoke-WindowsElevatedPlan.ps1') `
                -SourceHelperPath (Join-Path $repoRoot 'scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1') `
                -SourceConfigPath (Join-Path $repoRoot 'config/network/package-sources.bootstrap.env')
            foreach ($result in @($elevated.Results)) {
                $results.Add($result)
            }
            if ([int]$elevated.ExitCode -ne 0 -and
                @($elevated.Results | Where-Object { $_.Status -in @('Failed', 'Blocked', 'RestartRequired') }).Count -eq 0) {
                $topStatus = if ([string]$elevated.Status -eq 'Failed') { 'Failed' } else { 'Blocked' }
                $topMessage = if ($elevated.PSObject.Properties['Message']) { [string]$elevated.Message } else { 'AutoHotkey 提升安装未完成' }
                $results.Add((New-WindowsInstallResult -Name elevation -Status $topStatus -Message $topMessage -ExitCode ([int]$elevated.ExitCode)))
            }
            elseif ([int]$elevated.ExitCode -eq 0) {
                $null = Update-WindowsBootstrapPath
                if (-not (Test-WindowsBootstrapComponentAvailable -Name AutoHotkey)) {
                    $results.Add((New-WindowsInstallResult -Name AutoHotkey -Status Blocked -Message '提升安装完成后仍未检测到 AutoHotkey v2' -ExitCode 10))
                }
            }
        }
    }
}

if (@($results | Where-Object { $_.Status -in @('Failed', 'Blocked', 'RestartRequired') }).Count -eq 0 -and -not $InstallOnly) {
    $buildArguments = @{
        OutputPath = Join-Path $repoRoot 'scripts/ahk/myAllScripts.ahk'
        WhatIf     = [bool]$WhatIfPreference
    }
    if ($StartupPath) {
        $buildArguments.StartupPath = $StartupPath
    }
    try {
        foreach ($result in @(& (Join-Path $repoRoot 'scripts/ahk/makeScripts.ps1') @buildArguments)) {
            $results.Add((New-WindowsInstallResult -Name "ahk-$($result.Name)" -Status ([string]$result.Status) -Message ([string]$result.Message)))
        }
    }
    catch {
        $results.Add((New-WindowsInstallResult -Name ahk-build -Status Failed -Message $_.Exception.Message -ExitCode 1))
    }
}

foreach ($result in $results) {
    Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Name, $result.Message)
}
exit (Get-WindowsInstallExitCode -Result $results.ToArray())
