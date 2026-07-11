#!/usr/bin/env pwsh

<#
.SYNOPSIS
    读取 Linux/WSL 安装流水线的只读组件状态。

.PARAMETER Step
    要检查的逻辑步骤，可传多个。

.PARAMETER Preset
    Core 或 Full，用于应用清单选择。

.PARAMETER OutputFormat
    Object、Tsv 或 Json。

.PARAMETER WslConfigTargetPath
    WSL 客体配置路径，生产默认 `/etc/wsl.conf`，测试可传临时路径。

.OUTPUTS
    PSCustomObject[]、TSV 或 JSON，绝不修改安装状态。
#>
[CmdletBinding()]
param(
    [string[]]$Step,

    [ValidateSet('Core', 'Full')]
    [string]$Preset = 'Core',

    [ValidateSet('Object', 'Tsv', 'Json')]
    [string]$OutputFormat = 'Object',

    [string]$WslConfigTargetPath = '/etc/wsl.conf'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Import-Module (Join-Path $repoRoot 'linux/pwsh/LinuxInstall.psm1') -Force
Import-Module (Join-Path $repoRoot 'psutils') -Force

$validSteps = @(
    'platform',
    'repo',
    'package-manager',
    'pwsh',
    'sources',
    'shell',
    'core-cli',
    'fonts',
    'profile-tools',
    'full-apps',
    'docker',
    'wsl-config'
)
$selectedSteps = @($Step | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($selectedSteps.Count -eq 0) {
    $selectedSteps = $validSteps
}
$unknownSteps = @($selectedSteps | Where-Object { $_ -notin $validSteps })
if ($unknownSteps.Count -gt 0) {
    throw "未知 Linux 验证步骤: $($unknownSteps -join ', ')"
}

$platform = Get-LinuxInstallEnvironment
$packageCatalog = Import-LinuxPackageCatalog -Path (Join-Path $repoRoot 'config/install/linux-packages.psd1')
$results = [System.Collections.Generic.List[object]]::new()

function Add-LinuxInstallCheck {
    <#
    .SYNOPSIS
        向只读验证结果添加检查项。

    .PARAMETER Step
        逻辑步骤 ID。

    .PARAMETER Name
        检查项名称。

    .PARAMETER Status
        Pass、Warn、Fail、Blocked 或 Skipped。

    .PARAMETER Message
        检查摘要。

    .OUTPUTS
        None。结果写入脚本级列表。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Step,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Pass', 'Warn', 'Fail', 'Blocked', 'Skipped')]
        [string]$Status,

        [string]$Message = ''
    )

    $results.Add([pscustomobject]@{
            Step    = $Step
            Name    = $Name
            Status  = $Status
            Message = $Message
        })
}

function Test-LinuxCommandAvailable {
    <#
    .SYNOPSIS
        添加一个命令存在性检查。

    .PARAMETER Step
        逻辑步骤 ID。

    .PARAMETER Name
        展示名称。

    .PARAMETER Command
        要查找的命令名。

    .OUTPUTS
        None。结果写入脚本级列表。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Step,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Command
    )

    $commandInfo = Get-Command $Command -ErrorAction SilentlyContinue
    Add-LinuxInstallCheck `
        -Step $Step `
        -Name $Name `
        -Status $(if ($commandInfo) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($commandInfo) { [string]$commandInfo.Source } else { "缺少命令: $Command" })
}

function Test-LinuxSystemPackageInstalled {
    <#
    .SYNOPSIS
        只读检查当前发行版中的系统包是否已安装。

    .PARAMETER DistributionFamily
        debian 或 arch。

    .PARAMETER Package
        要检查的系统包名。

    .OUTPUTS
        System.Boolean。包已安装时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('debian', 'arch')]
        [string]$DistributionFamily,

        [Parameter(Mandatory)]
        [string]$Package
    )

    if ($DistributionFamily -eq 'arch') {
        $null = & pacman -Q $Package 2>$null
    }
    else {
        $null = & dpkg-query -W -f='${Status}' $Package 2>$null
    }
    return $LASTEXITCODE -eq 0
}

function Add-LinuxCatalogChecks {
    <#
    .SYNOPSIS
        从统一应用清单添加 Linuxbrew 软件检查。

    .PARAMETER Step
        core-cli 或 full-apps。

    .PARAMETER RequiredTag
        必须全部命中的标签。

    .OUTPUTS
        None。结果写入脚本级列表。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Step,

        [Parameter(Mandatory)]
        [string[]]$RequiredTag
    )

    $config = (Resolve-ConfigSources -Sources @(
            @{ Type = 'JsonFile'; Name = 'AppsConfig'; Path = (Join-Path $repoRoot 'profile/installer/apps-config.json') }
        ) -BasePath $repoRoot -ErrorOnMissing).Values
    $null = Test-PackageManagerAppCatalog -ConfigObject $config
    $homebrewApps = @($config.packageManagers.homebrew)
    $apps = @(Select-PackageManagerApps `
            -Apps $homebrewApps `
            -TargetOS Linux `
            -RequiredTag $RequiredTag `
            -IncludeSkipped)
    if ($apps.Count -eq 0) {
        Add-LinuxInstallCheck -Step $Step -Name catalog -Status Skipped -Message '清单没有匹配项'
        return
    }

    foreach ($app in $apps) {
        $name = [string]$app.name
        $propertyNames = @($app.PSObject.Properties.Name)
        $cliName = if ('cliName' -in $propertyNames -and $app.cliName) { [string]$app.cliName } else { $name }
        $skipInstall = 'skipInstall' -in $propertyNames -and [bool]$app.skipInstall
        $filterCli = 'filterCli' -in $propertyNames -and [bool]$app.filterCli
        if ($skipInstall) {
            Add-LinuxInstallCheck -Step $Step -Name $name -Status Warn -Message '配置标记 skipInstall'
            continue
        }
        $installed = Test-ApplicationInstalled -AppName $cliName -FilterCli:$filterCli
        Add-LinuxInstallCheck `
            -Step $Step `
            -Name $name `
            -Status $(if ($installed) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($installed) { "$cliName 已安装" } else { "缺少 $cliName" })
    }
}

foreach ($stepId in $selectedSteps) {
    switch ($stepId) {
        'platform' {
            Add-LinuxInstallCheck `
                -Step platform `
                -Name "$($platform.DistributionId)-$($platform.Architecture)" `
                -Status $(if ($platform.SupportLevel -eq 'Full') { 'Pass' } else { 'Blocked' }) `
                -Message "support=$($platform.SupportLevel) wsl=$($platform.IsWsl) systemd=$($platform.HasSystemd)"
        }
        'repo' {
            $installPath = Join-Path $repoRoot 'install.ps1'
            Add-LinuxInstallCheck -Step repo -Name install.ps1 -Status $(if (Test-Path -LiteralPath $installPath -PathType Leaf) { 'Pass' } else { 'Fail' }) -Message $installPath
        }
        'package-manager' {
            $brewPath = Get-LinuxBrewPath
            Add-LinuxInstallCheck -Step package-manager -Name linuxbrew -Status $(if ($brewPath) { 'Pass' } else { 'Fail' }) -Message $(if ($brewPath) { $brewPath } else { '缺少 Linuxbrew' })
        }
        'pwsh' {
            $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
            $major = if ($pwshCommand) { pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.Major' 2>$null } else { 0 }
            Add-LinuxInstallCheck -Step pwsh -Name pwsh -Status $(if ([int]$major -ge 7) { 'Pass' } else { 'Fail' }) -Message $(if ($pwshCommand) { "major=$major" } else { '缺少 PowerShell 7' })
        }
        'sources' {
            $sourceCatalog = (Resolve-ConfigSources -Sources @(
                    @{ Type = 'JsonFile'; Name = 'PackageSources'; Path = (Join-Path $repoRoot 'config/network/package-sources.json') }
                ) -BasePath $repoRoot -ErrorOnMissing).Values
            $targetAvailable = $platform.SourceTarget -and $sourceCatalog.targets.ContainsKey($platform.SourceTarget)
            $brewSupportsLinux = $sourceCatalog.targets.brew.platforms -contains 'linux'
            Add-LinuxInstallCheck `
                -Step sources `
                -Name catalog `
                -Status $(if ($targetAvailable -and $brewSupportsLinux) { 'Pass' } else { 'Blocked' }) `
                -Message "distribution=$($platform.SourceTarget) brew-linux=$brewSupportsLinux"
        }
        'shell' {
            $snippetDirectory = Join-Path $HOME '.bashrc.d'
            $loaderFiles = @((Join-Path $HOME '.bashrc'), (Join-Path $HOME '.zshrc'))
            $hasLoader = @($loaderFiles | Where-Object {
                    (Test-Path -LiteralPath $_ -PathType Leaf) -and
                    (Select-String -LiteralPath $_ -Pattern 'Load modular configuration files from ~/.bashrc.d' -SimpleMatch -Quiet)
                }).Count -gt 0
            Add-LinuxInstallCheck -Step shell -Name snippets -Status $(if (Test-Path -LiteralPath $snippetDirectory -PathType Container) { 'Pass' } else { 'Fail' }) -Message $snippetDirectory
            Add-LinuxInstallCheck -Step shell -Name loader -Status $(if ($hasLoader) { 'Pass' } else { 'Fail' }) -Message 'bashrc/zshrc modular loader'
        }
        'core-cli' {
            Add-LinuxCatalogChecks -Step core-cli -RequiredTag @('core', 'cli')
        }
        'fonts' {
            $fontEnvironment = Resolve-LinuxFontEnvironment -Environment Auto -Platform $platform
            if ($fontEnvironment -eq 'Server') {
                Add-LinuxInstallCheck -Step fonts -Name fonts -Status Skipped -Message 'Server/WSL 默认不安装字体'
                break
            }
            $family = Get-LinuxPackageFamily -Catalog $packageCatalog -DistributionFamily $platform.DistributionFamily
            foreach ($package in @($family.DesktopFonts.Required)) {
                $installed = Test-LinuxSystemPackageInstalled -DistributionFamily $platform.DistributionFamily -Package $package
                Add-LinuxInstallCheck `
                    -Step fonts `
                    -Name $package `
                    -Status $(if ($installed) { 'Pass' } else { 'Fail' }) `
                    -Message "$($platform.DistributionFamily) package state"
            }
        }
        'profile-tools' {
            Test-LinuxCommandAvailable -Step profile-tools -Name fnm -Command fnm
            Test-LinuxCommandAvailable -Step profile-tools -Name pnpm -Command pnpm
            Test-LinuxCommandAvailable -Step profile-tools -Name uv -Command uv
            $profileExists = Test-Path -LiteralPath $PROFILE -PathType Leaf
            Add-LinuxInstallCheck -Step profile-tools -Name profile -Status $(if ($profileExists) { 'Pass' } else { 'Fail' }) -Message $PROFILE
        }
        'full-apps' {
            if ($Preset -ne 'Full') {
                Add-LinuxInstallCheck -Step full-apps -Name preset -Status Skipped -Message 'Core 不包含 terminal extras'
                break
            }
            Add-LinuxCatalogChecks -Step full-apps -RequiredTag @('cli', 'terminal-extras')
        }
        'docker' {
            Add-LinuxInstallCheck -Step docker -Name docker -Status $(if (Test-LinuxDockerAvailable) { 'Pass' } else { 'Fail' }) -Message 'docker info'
        }
        'wsl-config' {
            if (-not $platform.IsWsl) {
                Add-LinuxInstallCheck -Step wsl-config -Name wsl.conf -Status Skipped -Message '当前不是 WSL 客体'
                break
            }
            $sourcePath = Join-Path $repoRoot 'linux/wsl/wsl.conf'
            if (-not (Test-Path -LiteralPath $WslConfigTargetPath -PathType Leaf)) {
                Add-LinuxInstallCheck -Step wsl-config -Name wsl.conf -Status Fail -Message "缺少 $WslConfigTargetPath"
                break
            }
            $matches = (Get-Content -LiteralPath $sourcePath -Raw) -ceq (Get-Content -LiteralPath $WslConfigTargetPath -Raw)
            Add-LinuxInstallCheck -Step wsl-config -Name wsl.conf -Status $(if ($matches) { 'Pass' } else { 'Fail' }) -Message $WslConfigTargetPath
            if (-not $platform.HasSystemd) {
                Add-LinuxInstallCheck -Step wsl-config -Name systemd -Status Blocked -Message '配置可能尚未通过 wsl --shutdown 生效'
            }
        }
    }
}

switch ($OutputFormat) {
    'Json' {
        $results.ToArray() | ConvertTo-Json -Depth 8 -Compress
    }
    'Tsv' {
        foreach ($result in $results) {
            "{0}`t{1}`t{2}`t{3}" -f $result.Step, $result.Name, $result.Status, $result.Message
        }
    }
    default {
        $results.ToArray()
    }
}
