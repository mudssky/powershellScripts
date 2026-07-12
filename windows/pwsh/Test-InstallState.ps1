<#
.SYNOPSIS
    为 Windows 99 提供只读平台、catalog、Profile、AutoHotkey 和 WSL 检查。

.PARAMETER Step
    要检查的逻辑步骤数组。

.PARAMETER Preset
    Core 或 Full。

.PARAMETER IncludeWsl
    将 WSL 缺失计入 Blocked/Fail。

.PARAMETER OutputFormat
    Object 或 Json。

.PARAMETER WslConfigTargetPath
    用户级 .wslconfig 路径。

.OUTPUTS
    PSCustomObject[] 或 JSON 检查数组。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$Step,

    [ValidateSet('Core', 'Full')]
    [string]$Preset = 'Core',

    [switch]$IncludeWsl,

    [ValidateSet('Object', 'Json')]
    [string]$OutputFormat = 'Object',

    [string]$WslConfigTargetPath = $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.wslconfig' } else { '' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Import-Module (Join-Path $repoRoot 'windows/pwsh/WindowsInstall.psm1') -Force
Import-Module (Join-Path $repoRoot 'psutils') -Force
$platform = Get-WindowsInstallEnvironment
$packageCatalog = Import-WindowsPackageCatalog -Path (Join-Path $repoRoot 'config/install/windows-packages.psd1')
$results = [System.Collections.Generic.List[object]]::new()

function Add-WindowsInstallCheck {
    <#
    .SYNOPSIS
        添加统一 Windows 只读检查结果。

    .PARAMETER StepName
        逻辑步骤 ID。

    .PARAMETER Name
        检查项名称。

    .PARAMETER Status
        Pass、Warn、Fail、Blocked 或 Skipped。

    .PARAMETER Message
        检查摘要。

    .OUTPUTS
        None。结果添加到当前检查集合。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StepName,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Pass', 'Warn', 'Fail', 'Blocked', 'Skipped')]
        [string]$Status,

        [string]$Message = ''
    )

    $results.Add([pscustomobject]@{ Step = $StepName; Name = $Name; Status = $Status; Message = $Message })
}

function Add-WindowsCatalogChecks {
    <#
    .SYNOPSIS
        从统一应用清单添加 Scoop 应用检查。

    .PARAMETER StepName
        逻辑步骤 ID。

    .PARAMETER RequiredTag
        必须全部命中的标签。

    .OUTPUTS
        None。结果添加到当前检查集合。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StepName,

        [Parameter(Mandatory)]
        [string[]]$RequiredTag
    )

    $appsConfig = (Resolve-ConfigSources -Sources @(
            @{ Type = 'JsonFile'; Name = 'AppsConfig'; Path = (Join-Path $repoRoot 'profile/installer/apps-config.json') }
        ) -BasePath $repoRoot -ErrorOnMissing).Values
    $packageManagers = ConvertTo-ConfigHashtable -InputObject $appsConfig.packageManagers
    $selected = @(Select-PackageManagerApps -Apps @($packageManagers.scoop) -TargetOS Windows -RequiredTag $RequiredTag -IncludeSkipped)
    if ($selected.Count -eq 0) {
        Add-WindowsInstallCheck -StepName $StepName -Name catalog -Status Fail -Message '应用清单没有匹配项'
        return
    }
    foreach ($item in $selected) {
        $app = ConvertTo-ConfigHashtable -InputObject $item
        if ($app.ContainsKey('skipInstall') -and [bool]$app.skipInstall) {
            Add-WindowsInstallCheck -StepName $StepName -Name ([string]$app.name) -Status Warn -Message '配置标记 skipInstall'
            continue
        }
        $commandName = if ($app.ContainsKey('cliName') -and $app.cliName) { [string]$app.cliName } else { [string]$app.name }
        $filterCli = $app.ContainsKey('filterCli') -and [bool]$app.filterCli
        $installed = Test-ApplicationInstalled -AppName $commandName -FilterCli:$filterCli
        Add-WindowsInstallCheck -StepName $StepName -Name ([string]$app.name) -Status $(if ($installed) { 'Pass' } else { 'Fail' }) -Message $(if ($installed) { '已安装' } else { '未检测到安装结果' })
    }
}

foreach ($stepName in $Step) {
    switch ($stepName) {
        'platform' {
            Add-WindowsInstallCheck -StepName platform -Name "$($platform.Edition)-$($platform.Architecture)" -Status $(if ($platform.SupportLevel -eq 'Full') { 'Pass' } elseif ($platform.SupportLevel -eq 'Partial') { 'Blocked' } else { 'Blocked' }) -Message "build=$($platform.BuildNumber) support=$($platform.SupportLevel)"
        }
        'repo' {
            Add-WindowsInstallCheck -StepName repo -Name install.ps1 -Status $(if (Test-Path -LiteralPath (Join-Path $repoRoot 'install.ps1') -PathType Leaf) { 'Pass' } else { 'Fail' }) -Message $repoRoot
        }
        'package-manager' {
            Add-WindowsInstallCheck -StepName package-manager -Name scoop -Status $(if ($platform.HasScoop) { 'Pass' } else { 'Fail' }) -Message 'Scoop current-user package manager'
        }
        'pwsh' {
            Add-WindowsInstallCheck -StepName pwsh -Name pwsh -Status $(if ($platform.HasPowerShell7) { 'Pass' } else { 'Fail' }) -Message 'PowerShell 7'
        }
        'sources' {
            $sourceCatalog = (Resolve-ConfigSources -Sources @(
                    @{ Type = 'JsonFile'; Name = 'Sources'; Path = (Join-Path $repoRoot 'config/network/package-sources.json') }
                ) -BasePath $repoRoot -ErrorOnMissing).Values
            $sourceTargets = ConvertTo-ConfigHashtable -InputObject $sourceCatalog.targets
            $targetsReady = @(@('npm', 'pnpm', 'pip', 'go', 'winget') | Where-Object { $sourceTargets.ContainsKey($_) }).Count -eq 5
            Add-WindowsInstallCheck -StepName sources -Name catalog -Status $(if ($targetsReady) { 'Pass' } else { 'Fail' }) -Message 'npm,pnpm,pip,go,winget'
        }
        'core-cli' { Add-WindowsCatalogChecks -StepName core-cli -RequiredTag @('core', 'cli') }
        'fonts' {
            $installedScoopItems = if ($platform.HasScoop) { @(& scoop list 2>$null) } else { @() }
            foreach ($font in @($packageCatalog.Scoop.Fonts)) {
                $installed = $platform.HasScoop -and (Test-WindowsScoopListContains -InputObject $installedScoopItems -Name ([string]$font))
                Add-WindowsInstallCheck -StepName fonts -Name ([string]$font) -Status $(if ($installed) { 'Pass' } else { 'Fail' }) -Message 'Scoop font state'
            }
        }
        'profile-tools' {
            foreach ($command in @('fnm', 'pnpm', 'uv')) {
                $available = $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
                Add-WindowsInstallCheck -StepName profile-tools -Name $command -Status $(if ($available) { 'Pass' } else { 'Fail' }) -Message 'command availability'
            }
            Add-WindowsInstallCheck -StepName profile-tools -Name profile -Status $(if (Test-Path -LiteralPath $PROFILE -PathType Leaf) { 'Pass' } else { 'Fail' }) -Message ([string]$PROFILE)
        }
        'full-apps' {
            if ($Preset -eq 'Full') { Add-WindowsCatalogChecks -StepName full-apps -RequiredTag @('cli', 'terminal-extras') }
            else { Add-WindowsInstallCheck -StepName full-apps -Name preset -Status Skipped -Message 'Core 不包含 terminal extras' }
        }
        'platform-automation' {
            if ($Preset -ne 'Full') {
                Add-WindowsInstallCheck -StepName platform-automation -Name preset -Status Skipped -Message 'Core 不包含 AutoHotkey'
            }
            else {
                Add-WindowsInstallCheck -StepName platform-automation -Name AutoHotkey -Status $(if ($platform.HasAutoHotkey) { 'Pass' } else { 'Fail' }) -Message 'AutoHotkey v2'
                $startupPath = if ($env:APPDATA) { Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\myAllScripts.lnk' } else { '' }
                Add-WindowsInstallCheck -StepName platform-automation -Name startup -Status $(if ($startupPath -and (Test-Path -LiteralPath $startupPath -PathType Leaf)) { 'Pass' } else { 'Fail' }) -Message $startupPath
            }
        }
        'wsl-host' {
            if (-not $IncludeWsl) {
                Add-WindowsInstallCheck -StepName wsl-host -Name wsl -Status Skipped -Message '未选择 IncludeWsl'
                break
            }
            Add-WindowsInstallCheck -StepName wsl-host -Name wsl -Status $(if ($platform.HasWsl) { 'Pass' } else { 'Blocked' }) -Message 'WSL host capability'
            $expected = ConvertTo-WindowsWslConfigContent -Catalog $packageCatalog -BuildNumber ([int]$platform.BuildNumber)
            $matches = $WslConfigTargetPath -and (Test-Path -LiteralPath $WslConfigTargetPath -PathType Leaf) -and ((Get-Content -LiteralPath $WslConfigTargetPath -Raw) -ceq $expected)
            Add-WindowsInstallCheck -StepName wsl-host -Name .wslconfig -Status $(if ($matches) { 'Pass' } else { 'Fail' }) -Message $WslConfigTargetPath
        }
    }
}

if ($OutputFormat -eq 'Json') {
    $results.ToArray() | ConvertTo-Json -Depth 10 -Compress
}
else {
    $results.ToArray()
}
