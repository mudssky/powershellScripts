<#
.SYNOPSIS
    在 Windows PowerShell 5.1 中完成 Windows Stage 0 并移交根 Stage 1。

.PARAMETER RepoUrl
    Git 仓库地址。

.PARAMETER RepoDir
    仓库 clone 或复用目录。

.PARAMETER BootstrapBaseUri
    远程最小 bootstrap 资产根 URI。

.PARAMETER Preset
    Core 或 Full。

.PARAMETER NetworkMode
    Direct、China 或 Auto。

.PARAMETER GitInstallerPath
    可选本地 Git 签名安装包。

.PARAMETER PowerShellMsiPath
    可选本地 PowerShell MSI。

.PARAMETER AutoHotkeyInstallerPath
    可选本地 AutoHotkey 签名安装包。

.PARAMETER ScoopInstallerPath
    可选本地 Scoop installer 脚本。

.PARAMETER IncludeWsl
    显式启用 WSL 宿主安装与配置。

.PARAMETER WslDistribution
    要确保存在的 WSL 发行版。

.PARAMETER Unattended
    允许本次调用出现一次 UAC。

.PARAMETER NonInteractive
    严格零提示；需要 UAC 时返回 Blocked/10。

.OUTPUTS
    文本阶段结果；失败退出 1，参数错误退出 2，Blocked/重启要求退出 10。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoUrl = 'https://github.com/mudssky/powershellScripts.git',

    [string]$RepoDir = $(Join-Path $HOME 'powershellScripts'),

    [ValidatePattern('^https://')]
    [string]$BootstrapBaseUri = 'https://raw.githubusercontent.com/mudssky/powershellScripts/master',

    [ValidateSet('Core', 'Full')]
    [string]$Preset = 'Core',

    [ValidateSet('Direct', 'China', 'Auto')]
    [string]$NetworkMode = 'Direct',

    [string]$GitInstallerPath = '',

    [string]$PowerShellMsiPath = '',

    [string]$AutoHotkeyInstallerPath = '',

    [string]$ScoopInstallerPath = '',

    [switch]$IncludeWsl,

    [string]$WslDistribution = 'Ubuntu-24.04',

    [switch]$Unattended,

    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-WindowsStage0Result {
    <#
    .SYNOPSIS
        输出统一 Stage 0 文本结果。

    .PARAMETER Result
        包含 Name、Status 和 Message 的结果对象。

    .OUTPUTS
        None。结果写入 stdout。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Result
    )

    Write-Output ('[{0}] {1}: {2}' -f $Result.Status, $Result.Name, $Result.Message)
}

function Test-WindowsStage0Administrator {
    <#
    .SYNOPSIS
        在 bootstrap 模块加载前判断当前 Windows 进程是否已提升。

    .OUTPUTS
        System.Boolean。管理员进程返回 true。
    #>
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsBootstrapAssetSet {
    <#
    .SYNOPSIS
        解析本地仓库资产或下载并校验远程最小 bootstrap bundle。

    .PARAMETER CandidateRepoRoot
        当前脚本可能所在的仓库根目录。

    .PARAMETER ExistingRepoRoot
        RepoDir 指向的可能现有仓库。

    .PARAMETER BaseUri
        远程资产根 URI。

    .PARAMETER Preview
        预览时不下载资产。

    .OUTPUTS
        Hashtable。包含 RepoRoot、AssetRoot 与固定资产路径；远程预览返回空表。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CandidateRepoRoot,

        [Parameter(Mandatory)]
        [string]$ExistingRepoRoot,

        [Parameter(Mandatory)]
        [string]$BaseUri,

        [switch]$Preview
    )

    $repoRoot = ''
    foreach ($candidate in @($CandidateRepoRoot, $ExistingRepoRoot)) {
        if ((Test-Path -LiteralPath (Join-Path $candidate 'install.ps1') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'windows/bootstrap/WindowsBootstrap.psm1') -PathType Leaf)) {
            $repoRoot = [System.IO.Path]::GetFullPath($candidate)
            break
        }
    }
    if ($repoRoot) {
        return @{
            RepoRoot        = $repoRoot
            AssetRoot       = $repoRoot
            ModulePath      = Join-Path $repoRoot 'windows/bootstrap/WindowsBootstrap.psm1'
            ExecutorPath    = Join-Path $repoRoot 'windows/bootstrap/Invoke-WindowsElevatedPlan.ps1'
            SourceHelper    = Join-Path $repoRoot 'scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1'
            SourceConfig    = Join-Path $repoRoot 'config/network/package-sources.bootstrap.env'
            PackageConfig   = Join-Path $repoRoot 'config/install/windows-packages.psd1'
        }
    }

    if ($Preview) {
        Write-Output "[Preview] bootstrap-assets: $BaseUri/windows/bootstrap/bootstrap-manifest.psd1"
        return @{}
    }

    $assetRoot = Join-Path $env:TEMP ("powershellScripts-bootstrap-{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $assetRoot -Force | Out-Null
    $manifestRelativePath = 'windows/bootstrap/bootstrap-manifest.psd1'
    $manifestPath = Join-Path $assetRoot $manifestRelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $manifestPath) -Force | Out-Null
    Invoke-WebRequest -Uri ($BaseUri.TrimEnd('/') + '/' + $manifestRelativePath) -UseBasicParsing -OutFile $manifestPath
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
    if ([int]$manifest.SchemaVersion -ne 1 -or @($manifest.Assets).Count -eq 0) {
        throw '远程 bootstrap manifest schema 无效'
    }
    foreach ($asset in @($manifest.Assets)) {
        $relativePath = ([string]$asset.Path).Replace('\', '/')
        if (-not $relativePath -or $relativePath.StartsWith('/') -or $relativePath -match '(^|/)\.\.(/|$)') {
            throw "远程 bootstrap manifest 包含非法路径: $relativePath"
        }
        $destination = Join-Path $assetRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Invoke-WebRequest -Uri ($BaseUri.TrimEnd('/') + '/' + $relativePath) -UseBasicParsing -OutFile $destination
        $actualHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne ([string]$asset.Sha256).ToLowerInvariant()) {
            throw "远程 bootstrap 资产 hash 不匹配: $relativePath"
        }
    }
    return @{
        RepoRoot      = ''
        AssetRoot     = $assetRoot
        ModulePath    = Join-Path $assetRoot 'windows/bootstrap/WindowsBootstrap.psm1'
        ExecutorPath  = Join-Path $assetRoot 'windows/bootstrap/Invoke-WindowsElevatedPlan.ps1'
        SourceHelper  = Join-Path $assetRoot 'scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1'
        SourceConfig  = Join-Path $assetRoot 'config/network/package-sources.bootstrap.env'
        PackageConfig = Join-Path $assetRoot 'config/install/windows-packages.psd1'
    }
}

function Test-WindowsWslDistributionInstalled {
    <#
    .SYNOPSIS
        只读检查指定 WSL 发行版是否已注册。

    .PARAMETER Distribution
        发行版名称。

    .OUTPUTS
        System.Boolean。发行版已注册时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Distribution
    )

    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        return $false
    }
    $distributions = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { ([string]$_).Replace([char]0, '').Trim() })
    return @($distributions | Where-Object { $_ -eq $Distribution }).Count -gt 0
}

if ($Unattended -and $NonInteractive) {
    [Console]::Error.WriteLine('Unattended 与 NonInteractive 不能同时使用')
    exit 2
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    [Console]::Error.WriteLine('Windows bootstrap 只能在 Windows 执行')
    exit 10
}
if (Test-WindowsStage0Administrator) {
    [Console]::Error.WriteLine('请从普通用户 Windows PowerShell 启动 bootstrap；用户配置不得由提升进程拥有')
    exit 10
}

$candidateRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$resolvedRepoDir = [System.IO.Path]::GetFullPath($RepoDir)
if ((Test-Path -LiteralPath $resolvedRepoDir) -and -not (Test-Path -LiteralPath $resolvedRepoDir -PathType Container)) {
    [Console]::Error.WriteLine("RepoDir 不是目录: $resolvedRepoDir")
    exit 2
}
if ((Test-Path -LiteralPath $resolvedRepoDir -PathType Container) -and
    -not (Test-Path -LiteralPath (Join-Path $resolvedRepoDir '.git') -PathType Container) -and
    @((Get-ChildItem -LiteralPath $resolvedRepoDir -Force -ErrorAction SilentlyContinue)).Count -gt 0) {
    [Console]::Error.WriteLine("RepoDir 已存在但不是 Git clone: $resolvedRepoDir")
    exit 2
}

try {
    $assets = Get-WindowsBootstrapAssetSet `
        -CandidateRepoRoot $candidateRepoRoot `
        -ExistingRepoRoot $resolvedRepoDir `
        -BaseUri $BootstrapBaseUri `
        -Preview:$WhatIfPreference
    if ($WhatIfPreference -and $assets.Count -eq 0) {
        Write-Output "[Preview] repo: git clone --depth=1 $RepoUrl $resolvedRepoDir"
        Write-Output "[Preview] stage1: pwsh ./install.ps1 -Preset $Preset -NetworkMode $NetworkMode -WhatIf"
        if ($IncludeWsl) {
            Write-Output "[Preview] wsl: ensure $WslDistribution and deploy .wslconfig"
        }
        exit 0
    }

    Import-Module $assets.ModulePath -Force
    $catalog = Import-WindowsBootstrapCatalog -Path $assets.PackageConfig
    if (-not $PSBoundParameters.ContainsKey('WslDistribution')) {
        $WslDistribution = [string]$catalog.Wsl.DefaultDistribution
    }
    $downloadDirectory = Join-Path $assets.AssetRoot 'downloads'
    $operations = New-Object System.Collections.Generic.List[object]
    $preflightResults = New-Object System.Collections.Generic.List[object]
    $componentRequests = @(
        @{ Name = 'Git'; Config = $catalog.Packages.Git; LocalPath = $GitInstallerPath },
        @{ Name = 'PowerShell'; Config = $catalog.Packages.PowerShell; LocalPath = $PowerShellMsiPath }
    )
    if ($Preset -eq 'Full') {
        $componentRequests += @{ Name = 'AutoHotkey'; Config = $catalog.Packages.AutoHotkey; LocalPath = $AutoHotkeyInstallerPath }
    }
    foreach ($request in $componentRequests) {
        $resolution = Resolve-WindowsBootstrapInstallOperation `
            -Name $request.Name `
            -PackageConfig $request.Config `
            -LocalInstallerPath $request.LocalPath `
            -NetworkMode $NetworkMode `
            -DownloadDirectory $downloadDirectory `
            -Preview:$WhatIfPreference
        $preflightResults.Add($resolution.Result)
        if ($null -ne $resolution.Operation) {
            $operations.Add($resolution.Operation)
        }
    }
    if ($IncludeWsl) {
        if (Test-WindowsWslDistributionInstalled -Distribution $WslDistribution) {
            $preflightResults.Add((New-WindowsBootstrapResult -Name Wsl -Status AlreadyPresent -Message $WslDistribution))
        }
        else {
            $operations.Add((New-WindowsBootstrapOperation -Type WslInstall -Name Wsl -Distribution $WslDistribution))
            $preflightResults.Add((New-WindowsBootstrapResult -Name Wsl -Status $(if ($WhatIfPreference) { 'Preview' } else { 'Succeeded' }) -Message "wsl --install --no-launch -d $WslDistribution"))
        }
    }
    foreach ($result in $preflightResults) {
        Write-WindowsStage0Result -Result $result
    }
    $preflightExitCode = Get-WindowsBootstrapExitCode -Result $preflightResults
    if ($preflightExitCode -ne 0) {
        exit $preflightExitCode
    }
    if ($WhatIfPreference) {
        Write-Output "[Preview] repo: git clone --depth=1 $RepoUrl $resolvedRepoDir"
        exit 0
    }
    if ($operations.Count -gt 0 -and $NonInteractive) {
        [Console]::Error.WriteLine('严格非交互模式无法请求机器级提升')
        exit 10
    }
    if ($operations.Count -gt 0) {
        $elevated = Invoke-WindowsBootstrapElevation `
            -Operation $operations.ToArray() `
            -NetworkMode $NetworkMode `
            -ExecutorPath $assets.ExecutorPath `
            -SourceHelperPath $assets.SourceHelper `
            -SourceConfigPath $assets.SourceConfig
        foreach ($result in @($elevated.Results)) {
            Write-WindowsStage0Result -Result $result
        }
        if ([int]$elevated.ExitCode -ne 0) {
            if ([string]$elevated.Status -eq 'RestartRequired') {
                [Console]::Error.WriteLine('机器操作要求重启 Windows；重启后使用相同参数重新运行 00quickstart.ps1')
            }
            elseif ($elevated.PSObject.Properties['Message'] -and $elevated.Message) {
                [Console]::Error.WriteLine([string]$elevated.Message)
            }
            exit ([int]$elevated.ExitCode)
        }
    }
    $null = Update-WindowsBootstrapPath
    foreach ($component in @('Git', 'PowerShell')) {
        if (-not (Test-WindowsBootstrapComponentAvailable -Name $component)) {
            [Console]::Error.WriteLine("Stage 0 完成后仍未检测到组件: $component")
            exit 10
        }
    }
    if ($Preset -eq 'Full' -and -not (Test-WindowsBootstrapComponentAvailable -Name AutoHotkey)) {
        [Console]::Error.WriteLine('Stage 0 完成后仍未检测到 AutoHotkey v2')
        exit 10
    }
    if ($IncludeWsl -and -not (Test-WindowsWslDistributionInstalled -Distribution $WslDistribution)) {
        [Console]::Error.WriteLine('WSL 发行版尚未就绪；若系统刚启用 WSL，请重启 Windows 后使用相同参数重跑 00')
        exit 10
    }

    $repoRoot = if ($assets.RepoRoot) { [string]$assets.RepoRoot } else { $resolvedRepoDir }
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git') -PathType Container)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $repoRoot) -Force | Out-Null
        & git clone --Depth=1 $RepoUrl $repoRoot
        if ($LASTEXITCODE -ne 0) {
            throw "git clone 失败，退出码: $LASTEXITCODE"
        }
    }

    $scoopArguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repoRoot 'windows/01installScoop.ps1'), '-NetworkMode', $NetworkMode)
    if ($ScoopInstallerPath) { $scoopArguments += @('-InstallerPath', $ScoopInstallerPath) }
    if ($Unattended) { $scoopArguments += '-Unattended' }
    if ($NonInteractive) { $scoopArguments += '-NonInteractive' }
    & powershell.exe @scoopArguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $env:POWERSHELL_SCRIPTS_BOOTSTRAP_SESSION = '1'
    $rootArguments = @('-NoLogo', '-NoProfile', '-File', (Join-Path $repoRoot 'install.ps1'), '-Preset', $Preset, '-NetworkMode', $NetworkMode)
    if ($Unattended) { $rootArguments += '-Unattended' }
    if ($NonInteractive) { $rootArguments += '-NonInteractive' }
    & pwsh @rootArguments
    $rootExitCode = $LASTEXITCODE
    if ($rootExitCode -ne 0) {
        exit $rootExitCode
    }
    if ($IncludeWsl) {
        & pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'windows/wsl/Initialize-WslHost.ps1') -Distribution $WslDistribution
        exit $LASTEXITCODE
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
