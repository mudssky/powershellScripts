Set-StrictMode -Version Latest

function ConvertTo-WindowsArchitecture {
    <#
    .SYNOPSIS
        将 Windows 架构名称规范化为安装合同使用的名称。

    .PARAMETER Architecture
        RuntimeInformation、环境变量或测试夹具提供的架构名称。

    .OUTPUTS
        System.String。返回 amd64、arm64 或 unknown。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Architecture
    )

    switch ($Architecture.Trim().ToLowerInvariant()) {
        { $_ -in @('x64', 'amd64', 'x86_64') } { return 'amd64' }
        { $_ -in @('arm64', 'aarch64') } { return 'arm64' }
        default { return 'unknown' }
    }
}

function Test-WindowsCommandAvailable {
    <#
    .SYNOPSIS
        使用测试覆盖或当前命令发现结果判断 Windows 组件是否可用。

    .PARAMETER Name
        要探测的命令名称。

    .PARAMETER CommandAvailability
        测试夹具提供的命令名到布尔值映射。

    .OUTPUTS
        System.Boolean。命令可用时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [hashtable]$CommandAvailability = @{}
    )

    if ($CommandAvailability.ContainsKey($Name)) {
        return [bool]$CommandAvailability[$Name]
    }
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-WindowsAdministrator {
    <#
    .SYNOPSIS
        判断当前 Windows 进程是否具有管理员权限。

    .PARAMETER WindowsHost
        是否为 Windows 宿主，测试可显式覆盖。

    .OUTPUTS
        System.Boolean。管理员进程返回 true。
    #>
    [CmdletBinding()]
    param(
        [bool]$WindowsHost = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
    )

    if (-not $WindowsHost) {
        return $false
    }
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-WindowsAutoHotkeyAvailable {
    <#
    .SYNOPSIS
        检查 AutoHotkey v2 是否可由命令或已知安装路径发现。

    .PARAMETER CommandAvailability
        测试夹具提供的命令覆盖。

    .PARAMETER WindowsHost
        是否为 Windows 宿主，测试可显式覆盖。

    .OUTPUTS
        System.Boolean。检测到 AutoHotkey v2 时返回 true。
    #>
    [CmdletBinding()]
    param(
        [hashtable]$CommandAvailability = @{},

        [bool]$WindowsHost = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
    )

    if ($CommandAvailability.ContainsKey('AutoHotkey')) {
        return [bool]$CommandAvailability.AutoHotkey
    }
    if (Get-Command AutoHotkey.exe -ErrorAction SilentlyContinue) {
        return $true
    }
    if (-not $WindowsHost) {
        return $false
    }
    foreach ($candidate in @(
            'C:\Program Files\AutoHotkey\v2\AutoHotkey.exe',
            'C:\Program Files\AutoHotkey\AutoHotkey.exe',
            'C:\Program Files\AutoHotkey\UX\AutoHotkeyUX.exe'
        )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $true
        }
    }
    return $false
}

function Get-WindowsInstallEnvironment {
    <#
    .SYNOPSIS
        返回 Windows 安装流水线共享的平台能力模型。

    .PARAMETER WindowsHost
        可选 Windows 宿主覆盖；为空时读取当前运行时。

    .PARAMETER ProductName
        可选 Windows 产品名覆盖；为空时从注册表读取。

    .PARAMETER InstallationType
        可选安装类型覆盖，用于识别 Server。

    .PARAMETER BuildNumber
        可选 build 覆盖；0 时从注册表读取。

    .PARAMETER Architecture
        可选架构覆盖。

    .PARAMETER Administrator
        可选管理员状态覆盖。

    .PARAMETER CommandAvailability
        测试夹具提供的命令名到布尔值映射。

    .OUTPUTS
        PSCustomObject。包含 edition、build、架构、权限、命令能力和支持级别。
    #>
    [CmdletBinding()]
    param(
        [Nullable[bool]]$WindowsHost,

        [string]$ProductName = '',

        [string]$InstallationType = '',

        [int]$BuildNumber = 0,

        [string]$Architecture = '',

        [Nullable[bool]]$Administrator,

        [hashtable]$CommandAvailability = @{}
    )

    $isWindowsHost = if ($null -ne $WindowsHost) {
        [bool]$WindowsHost
    }
    else {
        [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    }

    if ($isWindowsHost -and ([string]::IsNullOrWhiteSpace($ProductName) -or $BuildNumber -le 0 -or [string]::IsNullOrWhiteSpace($InstallationType))) {
        try {
            $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($ProductName)) {
                $ProductName = [string]$currentVersion.ProductName
            }
            if ($BuildNumber -le 0) {
                $BuildNumber = [int]$currentVersion.CurrentBuildNumber
            }
            if ([string]::IsNullOrWhiteSpace($InstallationType)) {
                $InstallationType = [string]$currentVersion.InstallationType
            }
        }
        catch {
        }
    }

    $rawArchitecture = if ([string]::IsNullOrWhiteSpace($Architecture)) {
        if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 }
        elseif ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE }
        else { [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }
    }
    else {
        $Architecture
    }
    $normalizedArchitecture = ConvertTo-WindowsArchitecture -Architecture $rawArchitecture
    $isServer = $ProductName -match '(?i)server' -or $InstallationType -match '(?i)server'
    $edition = if ($isServer) {
        'Server'
    }
    elseif ($BuildNumber -ge 22000) {
        'Windows11'
    }
    elseif ($BuildNumber -ge 10240) {
        'Windows10'
    }
    else {
        'Unknown'
    }

    $supportLevel = if (-not $isWindowsHost -or $normalizedArchitecture -ne 'amd64') {
        'Blocked'
    }
    elseif ($isServer) {
        'Partial'
    }
    elseif (($edition -eq 'Windows11' -and $BuildNumber -ge 22621) -or
        ($edition -eq 'Windows10' -and $BuildNumber -ge 19045)) {
        'Full'
    }
    else {
        'Blocked'
    }

    $isAdministrator = if ($null -ne $Administrator) {
        [bool]$Administrator
    }
    else {
        Test-WindowsAdministrator -WindowsHost $isWindowsHost
    }
    $hasWingetSourceCmdlets = @(@('Get-WinGetSource', 'Add-WinGetSource', 'Remove-WinGetSource') | Where-Object {
            Test-WindowsCommandAvailable -Name $_ -CommandAvailability $CommandAvailability
        }).Count -eq 3

    return [pscustomobject]@{
        Edition                      = $edition
        ProductName                  = $ProductName
        BuildNumber                  = $BuildNumber
        Architecture                 = $normalizedArchitecture
        IsWindows                    = [bool]$isWindowsHost
        IsServer                     = [bool]$isServer
        IsAdministrator              = [bool]$isAdministrator
        HasWinget                    = Test-WindowsCommandAvailable -Name winget -CommandAvailability $CommandAvailability
        HasWingetSourceCmdlets       = [bool]$hasWingetSourceCmdlets
        HasPowerShell7               = Test-WindowsCommandAvailable -Name pwsh -CommandAvailability $CommandAvailability
        HasScoop                     = Test-WindowsCommandAvailable -Name scoop -CommandAvailability $CommandAvailability
        HasWsl                       = Test-WindowsCommandAvailable -Name wsl -CommandAvailability $CommandAvailability
        HasAutoHotkey                = Test-WindowsAutoHotkeyAvailable -CommandAvailability $CommandAvailability -WindowsHost $isWindowsHost
        SupportsModernWslConfig      = -not $isServer -and $BuildNumber -ge 22621
        SupportsNestedVirtualization = -not $isServer -and $BuildNumber -ge 22000
        SupportLevel                 = $supportLevel
    }
}

function New-WindowsInstallResult {
    <#
    .SYNOPSIS
        创建 Windows 安装叶子的结构化组件结果。

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

function Get-WindowsInstallExitCode {
    <#
    .SYNOPSIS
        按 Failed 优先于 Blocked 的规则汇总 Windows 组件退出码。

    .PARAMETER Result
        New-WindowsInstallResult 返回的组件结果数组。

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

function Import-WindowsPackageCatalog {
    <#
    .SYNOPSIS
        通过共享配置解析器加载 Windows 安装声明。

    .PARAMETER Path
        windows-packages.psd1 路径。

    .OUTPUTS
        System.Collections.Hashtable。校验 schema 后的 Windows 安装清单。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Get-Command Resolve-ConfigSources -ErrorAction SilentlyContinue)) {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        Import-Module (Join-Path $repoRoot 'psutils/modules/config.psm1') -Force
    }
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $catalog = (Resolve-ConfigSources -Sources @(
            @{ Type = 'PowerShellDataFile'; Name = 'WindowsPackages'; Path = $resolvedPath }
        ) -BasePath (Split-Path -Parent $resolvedPath) -ErrorOnMissing).Values
    if ([int]$catalog.SchemaVersion -ne 1 -or -not $catalog.ContainsKey('Packages') -or
        -not $catalog.ContainsKey('Scoop') -or -not $catalog.ContainsKey('Wsl')) {
        throw 'Windows 安装清单 schema 无效'
    }
    return $catalog
}

function Invoke-WindowsNativeCommand {
    <#
    .SYNOPSIS
        以参数数组执行 Windows 原生命令并返回结构化结果。

    .PARAMETER Name
        组件结果名称。

    .PARAMETER FilePath
        可执行文件路径或命令名。

    .PARAMETER ArgumentList
        原生命令参数数组。

    .PARAMETER Preview
        只返回 Preview，不执行命令。

    .OUTPUTS
        PSCustomObject。Windows 安装组件结果。
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
        return New-WindowsInstallResult -Name $Name -Status Preview -Message $displayCommand
    }
    try {
        $output = @(& $FilePath @ArgumentList 2>&1)
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        $message = ($output | Select-Object -Last 20 | Out-String).Trim()
        if ($exitCode -ne 0) {
            return New-WindowsInstallResult -Name $Name -Status Failed -Message $(if ($message) { $message } else { "命令退出码为 $exitCode" }) -ExitCode $exitCode
        }
        return New-WindowsInstallResult -Name $Name -Status Succeeded -Message $message
    }
    catch {
        return New-WindowsInstallResult -Name $Name -Status Failed -Message $_.Exception.Message -ExitCode 1
    }
}

function Invoke-WindowsScoopCatalogInstall {
    <#
    .SYNOPSIS
        从统一应用清单安装 Windows Scoop 应用子集。

    .PARAMETER RepoRoot
        仓库根目录。

    .PARAMETER RequiredTag
        必须全部命中的应用标签。

    .PARAMETER Preview
        只返回安装计划。

    .OUTPUTS
        PSCustomObject[]。逐应用安装结果。
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
    Import-Module (Join-Path $resolvedRepoRoot 'psutils') -Force
    $configPath = Join-Path $resolvedRepoRoot 'profile/installer/apps-config.json'
    $config = (Resolve-ConfigSources -Sources @(
            @{ Type = 'JsonFile'; Name = 'AppsConfig'; Path = $configPath }
        ) -BasePath $resolvedRepoRoot -ErrorOnMissing).Values
    $null = Test-PackageManagerAppCatalog -ConfigObject $config
    $packageManagers = ConvertTo-ConfigHashtable -InputObject $config.packageManagers
    $selected = @(Select-PackageManagerApps `
            -Apps @($packageManagers.scoop) `
            -TargetOS Windows `
            -RequiredTag $RequiredTag)
    if ($selected.Count -eq 0) {
        return @(New-WindowsInstallResult -Name scoop -Status Failed -Message ("没有匹配标签: {0}" -f ($RequiredTag -join ', ')) -ExitCode 1)
    }
    if (-not $Preview -and -not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        return @(New-WindowsInstallResult -Name scoop -Status Blocked -Message '缺少 Scoop，请先完成 01 package-manager' -ExitCode 10)
    }
    return @(Install-PackageManagerApps `
            -PackageManager scoop `
            -ConfigObject $config `
            -TargetOS Windows `
            -RequiredTag $RequiredTag `
            -Required `
            -WhatIf:$Preview)
}

function Test-WindowsScoopListContains {
    <#
    .SYNOPSIS
        判断 Scoop list/bucket list 输出是否包含指定名称。

    .PARAMETER InputObject
        Scoop 输出的对象或旧版本文本行。

    .PARAMETER Name
        要匹配的应用或 bucket 名称。

    .OUTPUTS
        System.Boolean。输出中存在目标名称时返回 true。
    #>
    [CmdletBinding()]
    param(
        [object[]]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    foreach ($item in @($InputObject)) {
        $nameProperty = $item.PSObject.Properties['Name']
        if ($null -ne $nameProperty -and [string]$nameProperty.Value -ieq $Name) {
            return $true
        }
        if ([string]$item -match ("(?i)^\s*{0}(?:\s|$)" -f [regex]::Escape($Name))) {
            return $true
        }
    }
    return $false
}

function Install-WindowsScoopFonts {
    <#
    .SYNOPSIS
        幂等安装 Windows 声明中的 Scoop Nerd Fonts。

    .PARAMETER Catalog
        Import-WindowsPackageCatalog 返回的清单。

    .PARAMETER Preview
        只返回 bucket 与字体安装计划。

    .OUTPUTS
        PSCustomObject[]。bucket 与逐字体结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Catalog,

        [switch]$Preview
    )

    $bucket = [string]$Catalog.Scoop.FontBucket
    $fonts = @($Catalog.Scoop.Fonts)
    if (-not $Preview -and -not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        return @(New-WindowsInstallResult -Name fonts -Status Blocked -Message '缺少 Scoop，请先完成 01 package-manager' -ExitCode 10)
    }

    $results = [System.Collections.Generic.List[object]]::new()
    if ($Preview) {
        $results.Add((New-WindowsInstallResult -Name "bucket:$bucket" -Status Preview -Message "scoop bucket add $bucket"))
        foreach ($font in $fonts) {
            $results.Add((New-WindowsInstallResult -Name $font -Status Preview -Message "scoop install $font"))
        }
        return $results.ToArray()
    }

    $bucketOutput = @(& scoop bucket list 2>&1)
    $bucketExitCode = $LASTEXITCODE
    if ($bucketExitCode -ne 0 -or -not (Test-WindowsScoopListContains -InputObject $bucketOutput -Name $bucket)) {
        $results.Add((Invoke-WindowsNativeCommand -Name "bucket:$bucket" -FilePath scoop -ArgumentList @('bucket', 'add', $bucket)))
    }
    else {
        $results.Add((New-WindowsInstallResult -Name "bucket:$bucket" -Status AlreadyPresent))
    }
    $installedOutput = @(& scoop list 2>&1)
    foreach ($font in $fonts) {
        if (Test-WindowsScoopListContains -InputObject $installedOutput -Name ([string]$font)) {
            $results.Add((New-WindowsInstallResult -Name ([string]$font) -Status AlreadyPresent))
        }
        else {
            $results.Add((Invoke-WindowsNativeCommand -Name ([string]$font) -FilePath scoop -ArgumentList @('install', [string]$font)))
        }
    }
    return $results.ToArray()
}

function Merge-WindowsPathValue {
    <#
    .SYNOPSIS
        合并多个 Windows PATH 字符串并按不区分大小写规则去重。

    .PARAMETER PathValue
        按优先级排列的 PATH 字符串数组。

    .OUTPUTS
        System.String。使用平台分隔符连接的 PATH。
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string[]]$PathValue
    )

    $values = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($source in @($PathValue)) {
        foreach ($entry in @([string]$source -split [System.IO.Path]::PathSeparator)) {
            $trimmed = ([string]$entry).Trim()
            if ($trimmed -and $seen.Add($trimmed)) {
                $values.Add($trimmed)
            }
        }
    }
    return $values -join [System.IO.Path]::PathSeparator
}

function Update-WindowsProcessPath {
    <#
    .SYNOPSIS
        从 User、Machine 与当前 Process PATH 重建当前进程环境。

    .PARAMETER UserPath
        可选 User PATH 覆盖。

    .PARAMETER MachinePath
        可选 Machine PATH 覆盖。

    .OUTPUTS
        System.String。更新后的当前进程 PATH。
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$UserPath = '',

        [AllowEmptyString()]
        [string]$MachinePath = ''
    )

    if ([string]::IsNullOrWhiteSpace($UserPath)) {
        $UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    }
    if ([string]::IsNullOrWhiteSpace($MachinePath)) {
        $MachinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    }
    $env:PATH = Merge-WindowsPathValue -PathValue @($UserPath, $MachinePath, $env:PATH)
    return $env:PATH
}

function Add-WindowsUserPathEntry {
    <#
    .SYNOPSIS
        幂等追加单个目录到 Windows 用户 PATH 并刷新当前进程。

    .PARAMETER Path
        要追加的目录。

    .PARAMETER Preview
        只返回 Preview，不写入用户环境变量。

    .OUTPUTS
        PSCustomObject。PATH 更新结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Preview
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @([string]$userPath -split [System.IO.Path]::PathSeparator | Where-Object { $_ })
    if (@($entries | Where-Object { $_.Trim() -ieq $resolvedPath }).Count -gt 0) {
        $null = Update-WindowsProcessPath -UserPath $userPath
        return New-WindowsInstallResult -Name user-path -Status AlreadyPresent -Message $resolvedPath
    }
    if ($Preview) {
        return New-WindowsInstallResult -Name user-path -Status Preview -Message $resolvedPath
    }
    $updated = Merge-WindowsPathValue -PathValue @($userPath, $resolvedPath)
    [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
    $null = Update-WindowsProcessPath -UserPath $updated
    return New-WindowsInstallResult -Name user-path -Status Succeeded -Message $resolvedPath
}

function ConvertTo-WindowsWslConfigContent {
    <#
    .SYNOPSIS
        根据 Windows build 和声明式配置生成有效 .wslconfig 内容。

    .PARAMETER Catalog
        Import-WindowsPackageCatalog 返回的清单。

    .PARAMETER BuildNumber
        当前 Windows build。

    .OUTPUTS
        System.String。按 section 和声明顺序生成的配置文本。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Catalog,

        [Parameter(Mandatory)]
        [int]$BuildNumber
    )

    $settings = @($Catalog.Wsl.Settings | Where-Object { [int]$_['MinimumBuild'] -le $BuildNumber })
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($section in @($settings | ForEach-Object { [string]$_['Section'] } | Select-Object -Unique)) {
        if ($lines.Count -gt 0) {
            $lines.Add('')
        }
        $lines.Add("[$section]")
        foreach ($setting in @($settings | Where-Object { [string]$_['Section'] -eq $section })) {
            $lines.Add(("{0}={1}" -f $setting['Name'], $setting['Value']))
        }
    }
    return ($lines -join "`n") + "`n"
}

function Set-WindowsManagedContent {
    <#
    .SYNOPSIS
        幂等写入用户配置，变化时先创建时间戳备份再同目录替换。

    .PARAMETER Path
        目标文件路径。

    .PARAMETER Content
        要写入的完整内容。

    .PARAMETER Preview
        只返回 Preview，不创建目录、备份或目标文件。

    .OUTPUTS
        PSCustomObject。AlreadyPresent、Preview 或 RestartRequired 结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Content,

        [switch]$Preview
    )

    $targetPath = [System.IO.Path]::GetFullPath($Path)
    $current = if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
        Get-Content -LiteralPath $targetPath -Raw
    }
    else {
        $null
    }
    if ($null -ne $current -and $current -ceq $Content) {
        return New-WindowsInstallResult -Name managed-config -Status AlreadyPresent -Message $targetPath
    }
    if ($Preview) {
        return New-WindowsInstallResult -Name managed-config -Status Preview -Message $targetPath
    }

    $directory = Split-Path -Parent $targetPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $backupPath = ''
    if ($null -ne $current) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        $backupPath = "$targetPath.$timestamp.bak"
        Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
    }
    $temporaryPath = Join-Path $directory (".{0}.{1}.tmp" -f ([System.IO.Path]::GetFileName($targetPath)), ([guid]::NewGuid().ToString('N')))
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $Content, [System.Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            [System.IO.File]::Move($temporaryPath, $targetPath, $true)
        }
        else {
            Move-Item -LiteralPath $temporaryPath -Destination $targetPath
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
    $message = if ($backupPath) { "已更新；备份: $backupPath" } else { '已创建配置' }
    return New-WindowsInstallResult -Name managed-config -Status RestartRequired -Message $message -ExitCode 10
}

Export-ModuleMember -Function @(
    'ConvertTo-WindowsArchitecture',
    'Test-WindowsCommandAvailable',
    'Test-WindowsAdministrator',
    'Test-WindowsAutoHotkeyAvailable',
    'Get-WindowsInstallEnvironment',
    'New-WindowsInstallResult',
    'Get-WindowsInstallExitCode',
    'Import-WindowsPackageCatalog',
    'Invoke-WindowsNativeCommand',
    'Invoke-WindowsScoopCatalogInstall',
    'Install-WindowsScoopFonts',
    'Merge-WindowsPathValue',
    'Update-WindowsProcessPath',
    'Add-WindowsUserPathEntry',
    'ConvertTo-WindowsWslConfigContent',
    'Set-WindowsManagedContent'
)
