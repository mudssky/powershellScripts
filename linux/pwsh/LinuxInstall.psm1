Set-StrictMode -Version Latest

function ConvertTo-LinuxArchitecture {
    <#
    .SYNOPSIS
        将系统架构名称规范化为 Linux 安装合同使用的名称。

    .PARAMETER Architecture
        RuntimeInformation、uname 或测试夹具提供的架构名称。

    .OUTPUTS
        System.String。返回 amd64、arm64 或 unknown。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Architecture
    )

    switch ($Architecture.Trim().ToLowerInvariant()) {
        { $_ -in @('x64', 'x86_64', 'amd64') } { return 'amd64' }
        { $_ -in @('arm64', 'aarch64') } { return 'arm64' }
        default { return 'unknown' }
    }
}

function Read-LinuxOsRelease {
    <#
    .SYNOPSIS
        读取受约束的 os-release 键值文件。

    .PARAMETER Path
        os-release 文件路径，默认由平台探测调用方传入 `/etc/os-release`。

    .OUTPUTS
        System.Collections.Hashtable。键统一为大写，缺失文件返回空表。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $values
    }

    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        $trimmed = ([string]$line).Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#') -or $trimmed -notmatch '=') {
            continue
        }

        $parts = $trimmed -split '=', 2
        $key = $parts[0].Trim().ToUpperInvariant()
        $value = $parts[1].Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$key] = $value
    }

    return $values
}

function Get-LinuxInstallEnvironment {
    <#
    .SYNOPSIS
        返回 Linux 安装流水线共享的平台能力模型。

    .PARAMETER OsReleasePath
        os-release 文件路径，测试可传入 fixture。

    .PARAMETER ProcVersionPath
        `/proc/version` 路径，测试可传入 fixture。

    .PARAMETER Architecture
        可选架构覆盖；为空时使用当前 PowerShell RuntimeInformation。

    .PARAMETER WslInterop
        WSL_INTEROP 值，默认读取当前进程环境。

    .PARAMETER WslDistroName
        WSL_DISTRO_NAME 值，默认读取当前进程环境。

    .PARAMETER Display
        DISPLAY 值，用于桌面能力探测。

    .PARAMETER WaylandDisplay
        WAYLAND_DISPLAY 值，用于桌面能力探测。

    .PARAMETER XdgCurrentDesktop
        XDG_CURRENT_DESKTOP 值，用于桌面能力探测。

    .PARAMETER SystemdDirectory
        systemd 运行态目录路径，测试可传入 fixture。

    .OUTPUTS
        PSCustomObject。包含发行版、架构、WSL、桌面、systemd 和支持级别。
    #>
    [CmdletBinding()]
    param(
        [string]$OsReleasePath = $(if ($env:POWERSHELL_SCRIPTS_OS_RELEASE_PATH) { $env:POWERSHELL_SCRIPTS_OS_RELEASE_PATH } else { '/etc/os-release' }),

        [string]$ProcVersionPath = $(if ($env:POWERSHELL_SCRIPTS_PROC_VERSION_PATH) { $env:POWERSHELL_SCRIPTS_PROC_VERSION_PATH } else { '/proc/version' }),

        [string]$Architecture = $env:POWERSHELL_SCRIPTS_ARCHITECTURE,

        [AllowEmptyString()]
        [string]$WslInterop = $env:WSL_INTEROP,

        [AllowEmptyString()]
        [string]$WslDistroName = $env:WSL_DISTRO_NAME,

        [AllowEmptyString()]
        [string]$Display = $env:DISPLAY,

        [AllowEmptyString()]
        [string]$WaylandDisplay = $env:WAYLAND_DISPLAY,

        [AllowEmptyString()]
        [string]$XdgCurrentDesktop = $env:XDG_CURRENT_DESKTOP,

        [string]$SystemdDirectory = $(if ($env:POWERSHELL_SCRIPTS_SYSTEMD_DIRECTORY) { $env:POWERSHELL_SCRIPTS_SYSTEMD_DIRECTORY } else { '/run/systemd/system' })
    )

    $osRelease = Read-LinuxOsRelease -Path $OsReleasePath
    $distributionId = if ($osRelease.ContainsKey('ID')) {
        ([string]$osRelease.ID).Trim().ToLowerInvariant()
    }
    else {
        'unknown'
    }
    $idLike = if ($osRelease.ContainsKey('ID_LIKE')) {
        @(([string]$osRelease.ID_LIKE).ToLowerInvariant() -split '\s+' | Where-Object { $_ })
    }
    else {
        @()
    }

    $distributionFamily = if ($distributionId -in @('ubuntu', 'debian') -or 'debian' -in $idLike) {
        'debian'
    }
    elseif ($distributionId -eq 'arch' -or 'arch' -in $idLike) {
        'arch'
    }
    else {
        'unknown'
    }

    $rawArchitecture = if ([string]::IsNullOrWhiteSpace($Architecture)) {
        [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    }
    else {
        $Architecture
    }
    $normalizedArchitecture = ConvertTo-LinuxArchitecture -Architecture $rawArchitecture

    $procVersion = if (Test-Path -LiteralPath $ProcVersionPath -PathType Leaf) {
        Get-Content -LiteralPath $ProcVersionPath -Raw -ErrorAction SilentlyContinue
    }
    else {
        ''
    }
    $isWsl = -not [string]::IsNullOrWhiteSpace($WslInterop) -or
        -not [string]::IsNullOrWhiteSpace($WslDistroName) -or
        $procVersion -match '(?i)microsoft|wsl'
    $hasDesktop = -not [string]::IsNullOrWhiteSpace($Display) -or
        -not [string]::IsNullOrWhiteSpace($WaylandDisplay) -or
        -not [string]::IsNullOrWhiteSpace($XdgCurrentDesktop)
    $hasSystemd = Test-Path -LiteralPath $SystemdDirectory -PathType Container

    $supportLevel = if ($distributionFamily -eq 'debian' -and $normalizedArchitecture -eq 'amd64') {
        'Full'
    }
    elseif ($distributionFamily -eq 'arch' -and $normalizedArchitecture -eq 'amd64') {
        'Partial'
    }
    else {
        'Blocked'
    }
    $sourceTarget = if ($distributionId -in @('ubuntu', 'debian', 'arch')) {
        $distributionId
    }
    elseif ($distributionFamily -eq 'debian') {
        'debian'
    }
    else {
        ''
    }

    return [pscustomobject]@{
        DistributionId     = $distributionId
        DistributionFamily = $distributionFamily
        SourceTarget       = $sourceTarget
        Architecture       = $normalizedArchitecture
        IsWsl              = [bool]$isWsl
        HasDesktop         = [bool]$hasDesktop
        HasSystemd         = [bool]$hasSystemd
        SupportLevel       = $supportLevel
    }
}

function Import-LinuxPackageCatalog {
    <#
    .SYNOPSIS
        通过共享配置解析器加载 Linux 系统包清单。

    .PARAMETER Path
        `linux-packages.psd1` 路径。

    .OUTPUTS
        System.Collections.Hashtable。校验 schema 后的系统包清单。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Get-Command Resolve-ConfigSources -ErrorAction SilentlyContinue)) {
        $configModulePath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'psutils/modules/config.psm1'
        Import-Module $configModulePath -Force
    }

    $catalog = (Resolve-ConfigSources -Sources @(
            @{ Type = 'PowerShellDataFile'; Name = 'LinuxPackages'; Path = $Path }
        ) -BasePath (Split-Path -Parent $Path) -ErrorOnMissing).Values
    if ([int]$catalog.SchemaVersion -ne 1 -or -not $catalog.ContainsKey('Families')) {
        throw 'Linux 系统包清单 schema 无效'
    }
    return $catalog
}

function Get-LinuxPackageFamily {
    <#
    .SYNOPSIS
        返回指定发行版族的系统包声明。

    .PARAMETER Catalog
        Import-LinuxPackageCatalog 返回的清单。

    .PARAMETER DistributionFamily
        规范化发行版族名称。

    .OUTPUTS
        System.Collections.Hashtable。发行版族配置；不支持时抛出异常。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Catalog,

        [Parameter(Mandatory)]
        [string]$DistributionFamily
    )

    if (-not $Catalog.Families.ContainsKey($DistributionFamily)) {
        throw "Linux 系统包清单不支持发行版族: $DistributionFamily"
    }
    return $Catalog.Families[$DistributionFamily]
}

function Resolve-LinuxFontEnvironment {
    <#
    .SYNOPSIS
        根据显式模式和平台能力决定字体步骤的有效环境。

    .PARAMETER Environment
        Auto、Desktop 或 Server。

    .PARAMETER Platform
        Get-LinuxInstallEnvironment 返回的平台对象。

    .OUTPUTS
        System.String。返回 Desktop 或 Server。
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Auto', 'Desktop', 'Server')]
        [string]$Environment = 'Auto',

        [Parameter(Mandatory)]
        [object]$Platform
    )

    if ($Environment -ne 'Auto') {
        return $Environment
    }
    if ([bool]$Platform.IsWsl) {
        return 'Server'
    }
    if ([bool]$Platform.HasDesktop) {
        return 'Desktop'
    }
    return 'Server'
}

function New-LinuxInstallResult {
    <#
    .SYNOPSIS
        创建 Linux 安装叶子的结构化组件结果。

    .PARAMETER Name
        组件名称。

    .PARAMETER Status
        组件状态。

    .PARAMETER Message
        可操作的结果摘要。

    .PARAMETER ExitCode
        组件原始退出码。

    .OUTPUTS
        PSCustomObject。包含 Name、Status、Message 和 ExitCode。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Succeeded', 'AlreadyPresent', 'Preview', 'Skipped', 'Failed', 'Blocked', 'RestartRequired')]
        [string]$Status,

        [string]$Message = '',

        [int]$ExitCode = 0
    )

    return [pscustomobject]@{
        Name     = $Name
        Status   = $Status
        Message  = $Message
        ExitCode = $ExitCode
    }
}

function Get-LinuxInstallExitCode {
    <#
    .SYNOPSIS
        按 Failed 优先于 Blocked 的规则汇总组件退出码。

    .PARAMETER Result
        New-LinuxInstallResult 返回的组件结果数组。

    .OUTPUTS
        System.Int32。返回 1、10 或 0。
    #>
    [CmdletBinding()]
    param(
        [object[]]$Result
    )

    if (@($Result | Where-Object Status -eq 'Failed').Count -gt 0) {
        return 1
    }
    if (@($Result | Where-Object { $_.Status -in @('Blocked', 'RestartRequired') }).Count -gt 0) {
        return 10
    }
    return 0
}

function Get-LinuxBrewPath {
    <#
    .SYNOPSIS
        定位当前 Linux 用户可用的 Homebrew 可执行文件。

    .OUTPUTS
        System.String。找到时返回绝对路径，未找到返回空字符串。
    #>
    [CmdletBinding()]
    param()

    $command = Get-Command brew -ErrorAction SilentlyContinue
    if ($command) {
        return [string]$command.Source
    }

    foreach ($candidate in @(
            '/home/linuxbrew/.linuxbrew/bin/brew',
            (Join-Path $HOME '.linuxbrew/bin/brew')
        )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    return ''
}

function Initialize-LinuxBrewEnvironment {
    <#
    .SYNOPSIS
        根据已知 Linuxbrew 可执行文件恢复当前 PowerShell 进程环境。

    .PARAMETER BrewPath
        brew 可执行文件路径；为空时自动探测。

    .OUTPUTS
        System.String。成功返回 brew 路径，未安装返回空字符串。
    #>
    [CmdletBinding()]
    param(
        [string]$BrewPath = ''
    )

    $resolvedBrewPath = if ([string]::IsNullOrWhiteSpace($BrewPath)) { Get-LinuxBrewPath } else { $BrewPath }
    if ([string]::IsNullOrWhiteSpace($resolvedBrewPath)) {
        return ''
    }

    $prefix = Split-Path -Parent (Split-Path -Parent $resolvedBrewPath)
    $paths = [object[]]@((Join-Path $prefix 'bin'), (Join-Path $prefix 'sbin'))
    [array]::Reverse($paths)
    $currentPaths = @($env:PATH -split [System.IO.Path]::PathSeparator)
    foreach ($path in $paths) {
        if ($path -notin $currentPaths) {
            $env:PATH = $path + [System.IO.Path]::PathSeparator + $env:PATH
        }
    }
    $env:HOMEBREW_PREFIX = $prefix
    $env:HOMEBREW_CELLAR = Join-Path $prefix 'Cellar'
    $env:HOMEBREW_REPOSITORY = Join-Path $prefix 'Homebrew'
    return $resolvedBrewPath
}

function Invoke-LinuxNativeCommand {
    <#
    .SYNOPSIS
        以参数数组执行 Linux 原生命令并返回结构化结果。

    .PARAMETER Name
        组件结果名称。

    .PARAMETER FilePath
        可执行文件路径或命令名。

    .PARAMETER ArgumentList
        原生命令参数数组。

    .PARAMETER Preview
        只返回 Preview，不执行命令。

    .OUTPUTS
        PSCustomObject。Linux 安装组件结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList,

        [switch]$Preview
    )

    $displayCommand = ("{0} {1}" -f $FilePath, ($ArgumentList -join ' ')).Trim()
    if ($Preview) {
        return New-LinuxInstallResult -Name $Name -Status Preview -Message $displayCommand
    }

    try {
        $output = @(& $FilePath @ArgumentList 2>&1)
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        $message = ($output | Select-Object -Last 20 | Out-String).Trim()
        if ($exitCode -ne 0) {
            return New-LinuxInstallResult -Name $Name -Status Failed -Message $(if ($message) { $message } else { "命令退出码为 $exitCode" }) -ExitCode $exitCode
        }
        return New-LinuxInstallResult -Name $Name -Status Succeeded -Message $message
    }
    catch {
        return New-LinuxInstallResult -Name $Name -Status Failed -Message $_.Exception.Message -ExitCode 1
    }
}

function Get-LinuxSudoPreflightResult {
    <#
    .SYNOPSIS
        按交互等级验证 Linux 特权命令前置。

    .PARAMETER Unattended
        允许通过 `sudo -v` 在步骤开始时完成一次认证。

    .PARAMETER NonInteractive
        只允许 `sudo -n true`，需要提示时返回 Blocked。

    .PARAMETER Preview
        预览模式不访问 sudo，返回空结果。

    .OUTPUTS
        PSCustomObject 或 null。返回 sudo 的 AlreadyPresent/Blocked 结果；无需预检时返回 null。
    #>
    [CmdletBinding()]
    param(
        [switch]$Unattended,

        [switch]$NonInteractive,

        [switch]$Preview
    )

    if ($Preview -or (-not $Unattended -and -not $NonInteractive)) {
        return $null
    }

    $arguments = if ($NonInteractive) { @('-n', 'true') } else { @('-v') }
    $nativeResult = Invoke-LinuxNativeCommand -Name sudo -FilePath sudo -ArgumentList $arguments
    if ($nativeResult.Status -eq 'Failed') {
        $message = if ($NonInteractive) {
            '严格非交互模式需要预置 sudo 凭据'
        }
        else {
            '无法获得 sudo 认证'
        }
        return New-LinuxInstallResult -Name sudo -Status Blocked -Message $message -ExitCode 10
    }

    return New-LinuxInstallResult -Name sudo -Status AlreadyPresent -Message 'sudo 前置已满足'
}

function Install-LinuxAptPackages {
    <#
    .SYNOPSIS
        使用 apt-get 安装声明式 Linux 系统包。

    .PARAMETER Name
        组件结果名称。

    .PARAMETER Package
        要安装的包名数组。

    .PARAMETER Update
        安装前执行 apt-get update。

    .PARAMETER Preview
        只返回命令计划。

    .OUTPUTS
        PSCustomObject[]。apt update 与 install 的组件结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string[]]$Package,

        [switch]$Update,

        [switch]$Preview
    )

    $packages = @($Package | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    if ($packages.Count -eq 0) {
        return @(New-LinuxInstallResult -Name $Name -Status Skipped -Message '没有声明系统包')
    }

    $results = [System.Collections.Generic.List[object]]::new()
    if ($Update) {
        $updateResult = Invoke-LinuxNativeCommand -Name "$Name-update" -FilePath sudo -ArgumentList @('apt-get', 'update') -Preview:$Preview
        $results.Add($updateResult)
        if ($updateResult.Status -eq 'Failed') {
            return $results.ToArray()
        }
    }
    $arguments = @('env', 'DEBIAN_FRONTEND=noninteractive', 'apt-get', 'install', '-y') + $packages
    $results.Add((Invoke-LinuxNativeCommand -Name $Name -FilePath sudo -ArgumentList $arguments -Preview:$Preview))
    return $results.ToArray()
}

function Resolve-LinuxAptAlternative {
    <#
    .SYNOPSIS
        从候选包中选择 apt 仓库可见的第一个包。

    .PARAMETER Candidate
        按优先级排列的包名。

    .PARAMETER Preview
        预览时直接选择首个候选，不访问 apt-cache。

    .OUTPUTS
        System.String。可用包名，全部不可用时返回空字符串。
    #>
    [CmdletBinding()]
    param(
        [string[]]$Candidate,

        [switch]$Preview
    )

    $candidates = @($Candidate | Where-Object { $_ })
    if ($Preview) {
        return $(if ($candidates.Count -gt 0) { [string]$candidates[0] } else { '' })
    }
    foreach ($package in $candidates) {
        $null = & apt-cache show $package 2>$null
        if ($LASTEXITCODE -eq 0) {
            return [string]$package
        }
    }
    return ''
}

function Test-LinuxDockerAvailable {
    <#
    .SYNOPSIS
        通过 docker info 判断当前 Docker daemon 是否真实可用。

    .PARAMETER DockerCommand
        Docker CLI 命令名或路径。

    .OUTPUTS
        System.Boolean。CLI 和 daemon 均可用时返回 true。
    #>
    [CmdletBinding()]
    param(
        [string]$DockerCommand = 'docker'
    )

    if (-not (Get-Command $DockerCommand -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        $null = & $DockerCommand info 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Install-LinuxDocker {
    <#
    .SYNOPSIS
        复用可用 Docker，或在受支持 Debian 系平台安装客体 Docker Engine。

    .PARAMETER Platform
        Get-LinuxInstallEnvironment 返回的平台对象。

    .PARAMETER PackageFamily
        系统包清单中的 Debian 族配置。

    .PARAMETER Preview
        只返回安装计划，不探测或修改 Docker。

    .OUTPUTS
        PSCustomObject[]。Docker 探测、安装、服务与验证结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Platform,

        [Parameter(Mandatory)]
        [hashtable]$PackageFamily,

        [switch]$Preview
    )

    if ($Preview) {
        $previewPackages = @($PackageFamily.Docker.Required)
        foreach ($group in @($PackageFamily.Docker.ComposeGroups)) {
            $candidate = Resolve-LinuxAptAlternative -Candidate @($group) -Preview
            if ($candidate) {
                $previewPackages += $candidate
            }
        }
        return @(New-LinuxInstallResult -Name docker -Status Preview -Message ("apt-get install {0}" -f ($previewPackages -join ' ')))
    }
    if (Test-LinuxDockerAvailable) {
        return @(New-LinuxInstallResult -Name docker -Status AlreadyPresent -Message 'docker info 成功')
    }
    if ($Platform.SupportLevel -ne 'Full') {
        return @(New-LinuxInstallResult -Name docker -Status Blocked -Message '当前发行版或架构不在 Docker 完整支持矩阵' -ExitCode 10)
    }
    if (-not [bool]$Platform.HasSystemd) {
        return @(New-LinuxInstallResult -Name docker -Status Blocked -Message 'Docker Engine 需要可用 systemd；WSL 请先完成重启' -ExitCode 10)
    }

    $packages = @($PackageFamily.Docker.Required)
    foreach ($group in @($PackageFamily.Docker.ComposeGroups)) {
        $candidate = Resolve-LinuxAptAlternative -Candidate @($group)
        if ($candidate) {
            $packages += $candidate
        }
    }
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($result in @(Install-LinuxAptPackages -Name docker-packages -Package $packages -Update)) {
        $results.Add($result)
    }
    if (@($results | Where-Object Status -eq 'Failed').Count -gt 0) {
        return $results.ToArray()
    }

    $serviceResult = Invoke-LinuxNativeCommand -Name docker-service -FilePath sudo -ArgumentList @('systemctl', 'enable', '--now', 'docker')
    $results.Add($serviceResult)
    if ($serviceResult.Status -eq 'Failed') {
        return $results.ToArray()
    }
    if (Test-LinuxDockerAvailable) {
        $results.Add((New-LinuxInstallResult -Name docker -Status Succeeded -Message 'Docker Engine 与 daemon 已可用'))
    }
    else {
        $userName = if (-not [string]::IsNullOrWhiteSpace($env:USER)) {
            $env:USER
        }
        else {
            [Environment]::UserName
        }
        if ([string]::IsNullOrWhiteSpace($userName) -or $userName -eq 'root') {
            $results.Add((New-LinuxInstallResult -Name docker -Status Failed -Message '安装后 docker info 仍不可用' -ExitCode 1))
            return $results.ToArray()
        }

        $groupResult = Invoke-LinuxNativeCommand -Name docker-group -FilePath sudo -ArgumentList @('usermod', '-aG', 'docker', $userName)
        $results.Add($groupResult)
        if ($groupResult.Status -eq 'Failed') {
            return $results.ToArray()
        }

        $daemonResult = Invoke-LinuxNativeCommand -Name docker-daemon -FilePath sudo -ArgumentList @('docker', 'info')
        $results.Add($daemonResult)
        if ($daemonResult.Status -eq 'Failed') {
            return $results.ToArray()
        }

        $restartMessage = if ([bool]$Platform.IsWsl) {
            '已加入 docker 组；请在 Windows 执行 wsl --shutdown 后重跑以刷新组权限'
        }
        else {
            '已加入 docker 组；请重新登录后重跑以刷新组权限'
        }
        $results.Add((New-LinuxInstallResult -Name docker-access -Status RestartRequired -Message $restartMessage -ExitCode 10))
    }
    return $results.ToArray()
}

function Test-WslGuestConfigContent {
    <#
    .SYNOPSIS
        校验 WSL 客体配置包含本流水线要求的 systemd 合同。

    .PARAMETER Content
        wsl.conf 文本。

    .OUTPUTS
        System.Boolean。包含 `[boot]` 与 `systemd=true` 时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    return $Content -match '(?ms)^\s*\[boot\]\s*$.*?^\s*systemd\s*=\s*true\s*$'
}

function Install-WslGuestConfig {
    <#
    .SYNOPSIS
        在内容变化时备份并原子部署 WSL 客体配置。

    .PARAMETER SourcePath
        仓库内 wsl.conf 模板。

    .PARAMETER TargetPath
        客体目标路径，生产默认 `/etc/wsl.conf`，测试可传临时路径。

    .PARAMETER Preview
        只返回计划，不写目标。

    .OUTPUTS
        PSCustomObject。AlreadyPresent、Preview、RestartRequired 或 Failed。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [string]$TargetPath = '/etc/wsl.conf',

        [switch]$Preview
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        return New-LinuxInstallResult -Name wsl-config -Status Failed -Message "WSL 配置模板不存在: $SourcePath" -ExitCode 1
    }
    $sourceContent = Get-Content -LiteralPath $SourcePath -Raw -ErrorAction Stop
    if (-not (Test-WslGuestConfigContent -Content $sourceContent)) {
        return New-LinuxInstallResult -Name wsl-config -Status Failed -Message 'WSL 配置模板缺少 [boot] systemd=true' -ExitCode 1
    }
    $targetExists = Test-Path -LiteralPath $TargetPath -PathType Leaf
    $targetContent = if ($targetExists) { Get-Content -LiteralPath $TargetPath -Raw -ErrorAction Stop } else { '' }
    if ($targetExists -and $targetContent -ceq $sourceContent) {
        return New-LinuxInstallResult -Name wsl-config -Status AlreadyPresent -Message 'wsl.conf 内容未变化'
    }
    if ($Preview) {
        return New-LinuxInstallResult -Name wsl-config -Status Preview -Message "部署 $SourcePath -> $TargetPath；变化后需要在 Windows 执行 wsl --shutdown"
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $backupPath = "$TargetPath.$timestamp.bak"
    $targetDirectory = Split-Path -Parent $TargetPath
    $requiresElevation = [System.IO.Path]::GetFullPath($TargetPath).StartsWith('/etc/', [System.StringComparison]::Ordinal)
    try {
        if ($requiresElevation) {
            $temporaryTarget = Join-Path $targetDirectory (".wsl.conf.{0}.tmp" -f [guid]::NewGuid().ToString('N'))
            if ($targetExists) {
                $backupResult = Invoke-LinuxNativeCommand -Name wsl-config-backup -FilePath sudo -ArgumentList @('cp', '-p', $TargetPath, $backupPath)
                if ($backupResult.Status -eq 'Failed') {
                    return $backupResult
                }
            }
            $installResult = Invoke-LinuxNativeCommand -Name wsl-config-stage -FilePath sudo -ArgumentList @('install', '-m', '0644', $SourcePath, $temporaryTarget)
            if ($installResult.Status -eq 'Failed') {
                return $installResult
            }
            $moveResult = Invoke-LinuxNativeCommand -Name wsl-config-commit -FilePath sudo -ArgumentList @('mv', '-f', $temporaryTarget, $TargetPath)
            if ($moveResult.Status -eq 'Failed') {
                $null = Invoke-LinuxNativeCommand -Name wsl-config-cleanup -FilePath sudo -ArgumentList @('rm', '-f', $temporaryTarget)
                return $moveResult
            }
        }
        else {
            if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
                New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
            }
            if ($targetExists) {
                Copy-Item -LiteralPath $TargetPath -Destination $backupPath -Force
            }
            $temporaryTarget = Join-Path $targetDirectory (".{0}.{1}.tmp" -f (Split-Path -Leaf $TargetPath), [guid]::NewGuid().ToString('N'))
            Copy-Item -LiteralPath $SourcePath -Destination $temporaryTarget -Force
            Move-Item -LiteralPath $temporaryTarget -Destination $TargetPath -Force
        }
    }
    catch {
        return New-LinuxInstallResult -Name wsl-config -Status Failed -Message $_.Exception.Message -ExitCode 1
    }

    $message = "已部署 $TargetPath"
    if ($targetExists) {
        $message += "，备份为 $backupPath"
    }
    $message += '；请在 Windows 执行 wsl --shutdown 后重跑'
    return New-LinuxInstallResult -Name wsl-config -Status RestartRequired -Message $message -ExitCode 10
}

function Invoke-LinuxBrewCatalogInstall {
    <#
    .SYNOPSIS
        从统一应用清单选择并安装 Linuxbrew 软件。

    .PARAMETER RepoRoot
        仓库根目录。

    .PARAMETER RequiredTag
        必须全部命中的应用标签。

    .PARAMETER Preview
        预览安装，不要求本机已存在 brew。

    .OUTPUTS
        PSCustomObject[]。Install-PackageManagerApps 或 Blocked/Skipped 结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string[]]$RequiredTag,

        [switch]$Preview
    )

    $resolvedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
    if (-not (Get-Command Install-PackageManagerApps -ErrorAction SilentlyContinue) -or
        -not (Get-Command Resolve-ConfigSources -ErrorAction SilentlyContinue) -or
        -not (Get-Command Test-ApplicationInstalled -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $resolvedRepoRoot 'psutils') -Force -Global
    }

    $brewPath = Initialize-LinuxBrewEnvironment
    if (-not $Preview -and [string]::IsNullOrWhiteSpace($brewPath)) {
        return @(New-LinuxInstallResult -Name linuxbrew -Status Blocked -Message '缺少 Linuxbrew，请先完成 01 package-manager' -ExitCode 10)
    }

    $config = (Resolve-ConfigSources -Sources @(
            @{ Type = 'JsonFile'; Name = 'AppsConfig'; Path = (Join-Path $resolvedRepoRoot 'profile/installer/apps-config.json') }
        ) -BasePath $resolvedRepoRoot -ErrorOnMissing).Values
    $null = Test-PackageManagerAppCatalog -ConfigObject $config
    $results = @(Install-PackageManagerApps `
            -PackageManager homebrew `
            -ConfigObject $config `
            -TargetOS Linux `
            -RequiredTag $RequiredTag `
            -Required `
            -WhatIf:$Preview)
    if ($results.Count -eq 0) {
        return @(New-LinuxInstallResult -Name linuxbrew -Status Skipped -Message ("没有匹配标签: {0}" -f ($RequiredTag -join ', ')))
    }
    return $results
}

Export-ModuleMember -Function @(
    'ConvertTo-LinuxArchitecture',
    'Read-LinuxOsRelease',
    'Get-LinuxInstallEnvironment',
    'Import-LinuxPackageCatalog',
    'Get-LinuxPackageFamily',
    'Resolve-LinuxFontEnvironment',
    'New-LinuxInstallResult',
    'Get-LinuxInstallExitCode',
    'Get-LinuxBrewPath',
    'Initialize-LinuxBrewEnvironment',
    'Invoke-LinuxNativeCommand',
    'Get-LinuxSudoPreflightResult',
    'Install-LinuxAptPackages',
    'Resolve-LinuxAptAlternative',
    'Test-LinuxDockerAvailable',
    'Install-LinuxDocker',
    'Test-WslGuestConfigContent',
    'Install-WslGuestConfig',
    'Invoke-LinuxBrewCatalogInstall'
)
