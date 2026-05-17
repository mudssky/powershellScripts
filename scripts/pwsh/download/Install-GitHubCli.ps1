#!/usr/bin/env pwsh

<#
.SYNOPSIS
    按 JSON 配置下载并安装 GitHub Release 中分发的 CLI。

.DESCRIPTION
    读取 GitHub CLI 下载清单，根据当前平台选择 release asset，调用 `gh release download`
    下载压缩包，解压后把 CLI 可执行文件安装到用户级或配置指定目录。

.PARAMETER ConfigPath
    JSON 配置文件路径，默认优先读取脚本目录下的 `github-cli.config.json`，
    文件不存在时回退到 `github-cli.config.example.json`。

.PARAMETER Name
    只安装指定工具名称；未提供时安装配置中的全部工具。

.PARAMETER DownloadDir
    覆盖配置中的下载缓存目录。

.PARAMETER NoOverwrite
    目标 CLI 文件已存在时跳过安装。

.PARAMETER KeepTemp
    安装结束后保留临时下载与解压目录，便于排查问题。

.PARAMETER DryRun
    只输出解析后的安装计划，不执行下载和安装。
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = '',

    [string[]]$Name = @(),

    [string]$DownloadDir = '',

    [switch]$NoOverwrite,

    [switch]$KeepTemp,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GitHubCliDownloadRoot = $PSScriptRoot
$script:GitHubCliConfigModuleLoaded = $false

function Resolve-GitHubCliDefaultConfigPath {
    <#
    .SYNOPSIS
        解析默认下载配置文件路径。

    .DESCRIPTION
        优先使用用户本地配置 `github-cli.config.json`；不存在时回退到仓库提供的示例配置，
        让脚本首次运行也能通过 dry-run 看到可用计划。

    .OUTPUTS
        string。默认配置文件路径。
    #>
    [CmdletBinding()]
    param()

    $localConfigPath = Join-Path $script:GitHubCliDownloadRoot 'github-cli.config.json'
    if (Test-Path -LiteralPath $localConfigPath -PathType Leaf) {
        return $localConfigPath
    }

    return (Join-Path $script:GitHubCliDownloadRoot 'github-cli.config.example.json')
}

function ConvertTo-GitHubCliHashtable {
    <#
    .SYNOPSIS
        将配置对象转换为 hashtable。

    .DESCRIPTION
        统一处理 JSON 解析后的 PSCustomObject、hashtable 与字典对象，便于后续用
        大小写不敏感的配置读取逻辑访问字段。

    .PARAMETER InputObject
        待转换的配置对象；传入空值时返回空表。

    .OUTPUTS
        hashtable。转换后的浅层键值表。
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return @{}
    }

    if ($InputObject -is [hashtable]) {
        return @{} + $InputObject
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = $InputObject[$key]
        }
        return $result
    }

    $objectResult = @{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $objectResult[$property.Name] = $property.Value
    }
    return $objectResult
}

function Get-GitHubCliConfigValue {
    <#
    .SYNOPSIS
        按大小写不敏感方式读取配置值。

    .PARAMETER Values
        配置键值表。

    .PARAMETER Name
        要读取的配置键名。

    .PARAMETER DefaultValue
        未命中配置键时返回的默认值。

    .OUTPUTS
        object。命中的配置值；未命中时返回默认值。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Values,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$DefaultValue = $null
    )

    foreach ($entry in $Values.GetEnumerator()) {
        if ([string]::Equals([string]$entry.Key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $entry.Value
        }
    }

    return $DefaultValue
}

function Import-GitHubCliConfigModule {
    <#
    .SYNOPSIS
        加载仓库共享配置模块。

    .DESCRIPTION
        通过 `psutils/modules/config.psm1` 复用 `psutils/src/config` 的 JSON 配置读取逻辑，
        避免下载脚本维护独立配置解析器。

    .OUTPUTS
        None。加载 `Resolve-ConfigSources` 到当前会话。
    #>
    [CmdletBinding()]
    param()

    if ($script:GitHubCliConfigModuleLoaded) {
        return
    }

    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $script:GitHubCliDownloadRoot '../../..'))
    $configModulePath = Join-Path $repoRoot 'psutils/modules/config.psm1'
    if (-not (Test-Path -LiteralPath $configModulePath -PathType Leaf)) {
        throw "未找到共享配置解析器模块: $configModulePath"
    }

    Import-Module $configModulePath -Force
    $script:GitHubCliConfigModuleLoaded = $true
}

function Resolve-GitHubCliEnvPlaceholder {
    <#
    .SYNOPSIS
        替换路径字符串中的环境变量占位符。

    .DESCRIPTION
        支持 `${VAR_NAME}` 与平台原生 `%VAR_NAME%` 形式。`${...}` 缺失时抛错，
        防止安装路径意外落到错误目录。

    .PARAMETER Value
        待解析的路径字符串。

    .PARAMETER Context
        当前配置位置，用于错误提示。

    .OUTPUTS
        string。替换环境变量后的路径文本。
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Context
    )

    $pattern = '\$\{([A-Za-z_][A-Za-z0-9_]*)\}'
    foreach ($match in [regex]::Matches($Value, $pattern)) {
        $envName = $match.Groups[1].Value
        if ($null -eq [Environment]::GetEnvironmentVariable($envName, 'Process')) {
            throw "环境变量未设置: $envName（$Context）"
        }
    }

    $resolved = [regex]::Replace($Value, $pattern, {
            param($Match)
            $envName = $Match.Groups[1].Value
            return [Environment]::GetEnvironmentVariable($envName, 'Process')
        })

    return [Environment]::ExpandEnvironmentVariables($resolved)
}

function Resolve-GitHubCliPath {
    <#
    .SYNOPSIS
        将配置路径解析为绝对路径。

    .DESCRIPTION
        处理 `~`、环境变量占位符和相对路径。相对路径按配置文件所在目录解析，
        让下载配置可以随仓库移动。

    .PARAMETER Path
        原始路径配置值。

    .PARAMETER BasePath
        解析相对路径使用的基准目录。

    .PARAMETER Context
        当前配置位置，用于错误提示。

    .OUTPUTS
        string。绝对路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "路径配置不能为空: $Context"
    }

    $expanded = Resolve-GitHubCliEnvPlaceholder -Value $Path.Trim() -Context $Context
    if ($expanded -eq '~' -or $expanded.StartsWith('~/') -or $expanded.StartsWith('~\')) {
        $userHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        if ([string]::IsNullOrWhiteSpace($userHome)) {
            throw "无法解析用户主目录: $Context"
        }

        if ($expanded -eq '~') {
            $expanded = $userHome
        }
        else {
            $expanded = Join-Path $userHome $expanded.Substring(2)
        }
    }

    $combined = if ([System.IO.Path]::IsPathRooted($expanded)) {
        $expanded
    }
    else {
        Join-Path $BasePath $expanded
    }

    return [System.IO.Path]::GetFullPath($combined)
}

function New-GitHubCliPlatform {
    <#
    .SYNOPSIS
        创建当前或指定平台描述。

    .DESCRIPTION
        将 PowerShell 平台变量与 .NET 进程架构规范化为配置可使用的
        `windows-x64`、`linux-arm64`、`macos-x64` 等键。

    .PARAMETER OperatingSystem
        可选操作系统覆盖值，支持 `windows`、`linux`、`macos`。

    .PARAMETER Architecture
        可选架构覆盖值，支持 `x64`、`arm64` 或 .NET 架构名称。

    .OUTPUTS
        PSCustomObject。包含 OperatingSystem、Architecture 与 Key。
    #>
    [CmdletBinding()]
    param(
        [string]$OperatingSystem = '',

        [string]$Architecture = ''
    )

    $os = if (-not [string]::IsNullOrWhiteSpace($OperatingSystem)) {
        $OperatingSystem.Trim().ToLowerInvariant()
    }
    elseif ($IsWindows) {
        'windows'
    }
    elseif ($IsMacOS) {
        'macos'
    }
    elseif ($IsLinux) {
        'linux'
    }
    else {
        throw '无法识别当前操作系统。'
    }

    if ($os -notin @('windows', 'linux', 'macos')) {
        throw "不支持的操作系统: $OperatingSystem"
    }

    $rawArchitecture = if (-not [string]::IsNullOrWhiteSpace($Architecture)) {
        $Architecture
    }
    else {
        [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    }

    $arch = switch ($rawArchitecture.Trim().ToLowerInvariant()) {
        { $_ -in @('x64', 'amd64') } { 'x64'; break }
        { $_ -in @('arm64', 'aarch64') } { 'arm64'; break }
        default { throw "不支持的 CPU 架构: $rawArchitecture" }
    }

    return [pscustomobject]@{
        OperatingSystem = $os
        Architecture    = $arch
        Key             = "$os-$arch"
    }
}

function Get-GitHubCliDefaultInstallDir {
    <#
    .SYNOPSIS
        返回指定平台的用户级默认安装目录。

    .PARAMETER Platform
        `New-GitHubCliPlatform` 返回的平台描述。

    .OUTPUTS
        string。平台对应的默认安装路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Platform
    )

    if ($Platform.OperatingSystem -eq 'windows') {
        return '%USERPROFILE%\.local\bin'
    }

    return '~/.local/bin'
}

function Resolve-GitHubCliPlatformValue {
    <#
    .SYNOPSIS
        从平台映射配置中读取当前平台值。

    .DESCRIPTION
        按 `平台-架构`、`平台`、`default` 的顺序读取配置，例如先匹配
        `windows-x64`，再匹配 `windows`，最后匹配 `default`。

    .PARAMETER Value
        平台映射对象，也可以在允许标量时传入字符串。

    .PARAMETER Platform
        当前平台描述。

    .PARAMETER Label
        配置字段名称，用于错误提示。

    .PARAMETER AllowScalar
        允许直接传入字符串值。

    .OUTPUTS
        object。命中的平台配置值。
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [pscustomobject]$Platform,

        [Parameter(Mandatory)]
        [string]$Label,

        [switch]$AllowScalar
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string]) {
        if ($AllowScalar) {
            return $Value
        }

        throw "$Label 需要按平台配置，不能是单个字符串。"
    }

    $table = ConvertTo-GitHubCliHashtable -InputObject $Value
    foreach ($key in @($Platform.Key, $Platform.OperatingSystem, 'default')) {
        $mappedValue = Get-GitHubCliConfigValue -Values $table -Name $key
        if ($null -ne $mappedValue -and -not [string]::IsNullOrWhiteSpace([string]$mappedValue)) {
            return $mappedValue
        }
    }

    return $null
}

function Read-GitHubCliDownloadConfig {
    <#
    .SYNOPSIS
        读取 GitHub CLI 下载 JSON 配置。

    .DESCRIPTION
        通过共享配置解析器合并默认值、JSON 文件和命令行覆盖参数。
        后出现的来源覆盖前者。

    .PARAMETER ConfigPath
        JSON 配置文件路径。

    .PARAMETER CliParameters
        命令行覆盖参数，当前主要用于覆盖 `download_dir`。

    .OUTPUTS
        PSCustomObject。包含 Values 与 BasePath。
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$ConfigPath,

        [hashtable]$CliParameters = @{}
    )

    if ($ConfigPath -notmatch '\.json$') {
        throw 'GitHub CLI 下载配置仅支持 JSON 文件。'
    }

    Import-GitHubCliConfigModule

    $resolvedConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
    $basePath = Split-Path -Parent $resolvedConfigPath
    $sources = New-Object 'System.Collections.Generic.List[hashtable]'
    $sources.Add(@{
            Type = 'Hashtable'
            Name = 'Defaults'
            Data = @{
                download_dir = '.github-cli-downloads'
            }
        }) | Out-Null
    $sources.Add(@{
            Type = 'JsonFile'
            Name = 'ConfigFile'
            Path = $resolvedConfigPath
        }) | Out-Null

    if ($CliParameters.Count -gt 0) {
        $sources.Add(@{
                Type        = 'CliParameters'
                Name        = 'Cli'
                Data        = $CliParameters
                ExcludeKeys = @('ConfigPath', 'Name', 'NoOverwrite', 'KeepTemp', 'DryRun')
            }) | Out-Null
    }

    $resolved = Resolve-ConfigSources -Sources $sources.ToArray() -BasePath $basePath -ErrorOnMissing
    return [pscustomobject]@{
        Values   = $resolved.Values
        BasePath = $basePath
    }
}

function Resolve-GitHubCliExecutableName {
    <#
    .SYNOPSIS
        解析工具在当前平台的可执行文件名。

    .PARAMETER Tool
        单个工具配置表。

    .PARAMETER Platform
        当前平台描述。

    .OUTPUTS
        string。可执行文件名。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Tool,

        [Parameter(Mandatory)]
        [pscustomobject]$Platform
    )

    $executables = Get-GitHubCliConfigValue -Values $Tool -Name 'executables'
    $platformExecutable = Resolve-GitHubCliPlatformValue -Value $executables -Platform $Platform -Label 'executables' -AllowScalar
    if (-not [string]::IsNullOrWhiteSpace([string]$platformExecutable)) {
        return [string]$platformExecutable
    }

    $executable = [string](Get-GitHubCliConfigValue -Values $Tool -Name 'executable' -DefaultValue (Get-GitHubCliConfigValue -Values $Tool -Name 'name'))
    if ([string]::IsNullOrWhiteSpace($executable)) {
        throw '工具配置缺少 executable 或 name。'
    }

    if ($Platform.OperatingSystem -eq 'windows' -and -not $executable.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        return "$executable.exe"
    }

    return $executable
}

function Resolve-GitHubCliInstallDir {
    <#
    .SYNOPSIS
        解析工具在当前平台的安装目录。

    .DESCRIPTION
        优先级为工具级 `install_dirs`、工具级 `install_dir`、全局 `install_dirs`、
        全局 `install_dir`、用户级默认目录。

    .PARAMETER ConfigValues
        顶层配置值。

    .PARAMETER Tool
        单个工具配置表。

    .PARAMETER Platform
        当前平台描述。

    .PARAMETER BasePath
        解析相对路径使用的基准目录。

    .OUTPUTS
        string。安装目录绝对路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ConfigValues,

        [Parameter(Mandatory)]
        [hashtable]$Tool,

        [Parameter(Mandatory)]
        [pscustomobject]$Platform,

        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $candidate = Resolve-GitHubCliPlatformValue -Value (Get-GitHubCliConfigValue -Values $Tool -Name 'install_dirs') -Platform $Platform -Label 'tool.install_dirs' -AllowScalar
    if ($null -eq $candidate) {
        $candidate = Get-GitHubCliConfigValue -Values $Tool -Name 'install_dir'
    }
    if ($null -eq $candidate) {
        $candidate = Resolve-GitHubCliPlatformValue -Value (Get-GitHubCliConfigValue -Values $ConfigValues -Name 'install_dirs') -Platform $Platform -Label 'install_dirs' -AllowScalar
    }
    if ($null -eq $candidate) {
        $candidate = Get-GitHubCliConfigValue -Values $ConfigValues -Name 'install_dir'
    }
    if ($null -eq $candidate) {
        $candidate = Get-GitHubCliDefaultInstallDir -Platform $Platform
    }

    return Resolve-GitHubCliPath -Path ([string]$candidate) -BasePath $BasePath -Context 'install_dir'
}

function Resolve-GitHubCliDownloadSpecs {
    <#
    .SYNOPSIS
        将配置转换为当前平台的安装计划。

    .PARAMETER Config
        `Read-GitHubCliDownloadConfig` 返回的配置对象。

    .PARAMETER Platform
        当前平台描述。

    .PARAMETER Name
        需要安装的工具名称筛选列表。

    .OUTPUTS
        PSCustomObject[]。每个对象描述一个工具的下载与安装计划。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config,

        [Parameter(Mandatory)]
        [pscustomobject]$Platform,

        [string[]]$Name = @()
    )

    $values = $Config.Values
    $toolsValue = Get-GitHubCliConfigValue -Values $values -Name 'tools'
    if ($null -eq $toolsValue) {
        throw '配置缺少 tools 数组。'
    }

    $selectedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Name) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $selectedNames.Add($item) | Out-Null
        }
    }

    $downloadDir = Resolve-GitHubCliPath -Path ([string](Get-GitHubCliConfigValue -Values $values -Name 'download_dir' -DefaultValue '.github-cli-downloads')) -BasePath $Config.BasePath -Context 'download_dir'
    $specs = New-Object 'System.Collections.Generic.List[object]'
    foreach ($toolItem in @($toolsValue)) {
        $tool = ConvertTo-GitHubCliHashtable -InputObject $toolItem
        $toolName = [string](Get-GitHubCliConfigValue -Values $tool -Name 'name')
        if ([string]::IsNullOrWhiteSpace($toolName)) {
            throw 'tools[] 项缺少 name。'
        }

        if ($selectedNames.Count -gt 0 -and -not $selectedNames.Contains($toolName)) {
            continue
        }

        $repo = [string](Get-GitHubCliConfigValue -Values $tool -Name 'repo')
        if ([string]::IsNullOrWhiteSpace($repo)) {
            throw "工具 '$toolName' 缺少 repo。"
        }

        $assetPattern = Resolve-GitHubCliPlatformValue -Value (Get-GitHubCliConfigValue -Values $tool -Name 'asset_patterns') -Platform $Platform -Label "$toolName.asset_patterns"
        if ([string]::IsNullOrWhiteSpace([string]$assetPattern)) {
            throw "工具 '$toolName' 未配置平台 $($Platform.Key) 的 asset pattern。"
        }

        $binaryPath = Resolve-GitHubCliPlatformValue -Value (Get-GitHubCliConfigValue -Values $tool -Name 'binary_paths') -Platform $Platform -Label "$toolName.binary_paths" -AllowScalar
        if ($null -eq $binaryPath) {
            $binaryPath = Get-GitHubCliConfigValue -Values $tool -Name 'binary_path'
        }

        $specs.Add([pscustomobject]@{
                Name              = $toolName
                Repo              = $repo
                Tag               = [string](Get-GitHubCliConfigValue -Values $tool -Name 'tag' -DefaultValue '')
                AssetPattern      = [string]$assetPattern
                ExecutableName    = Resolve-GitHubCliExecutableName -Tool $tool -Platform $Platform
                BinaryPath        = if ($null -eq $binaryPath) { '' } else { [string]$binaryPath }
                DownloadDirectory = $downloadDir
                InstallDirectory  = Resolve-GitHubCliInstallDir -ConfigValues $values -Tool $tool -Platform $Platform -BasePath $Config.BasePath
                Platform          = $Platform
            }) | Out-Null
    }

    if ($selectedNames.Count -gt 0 -and $specs.Count -eq 0) {
        throw "未找到指定工具: $($Name -join ', ')"
    }

    return [pscustomobject[]]$specs.ToArray()
}

function New-GitHubCliDownloadArguments {
    <#
    .SYNOPSIS
        生成 `gh release download` 参数。

    .PARAMETER Spec
        单个工具下载与安装计划。

    .PARAMETER Destination
        下载目标目录。

    .OUTPUTS
        string[]。传给 `gh` 的参数数组。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Spec,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    $arguments = New-Object 'System.Collections.Generic.List[string]'
    $arguments.Add('release') | Out-Null
    $arguments.Add('download') | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($Spec.Tag) -and $Spec.Tag -ne 'latest') {
        $arguments.Add($Spec.Tag) | Out-Null
    }
    $arguments.Add('--repo') | Out-Null
    $arguments.Add($Spec.Repo) | Out-Null
    $arguments.Add('--pattern') | Out-Null
    $arguments.Add($Spec.AssetPattern) | Out-Null
    $arguments.Add('--dir') | Out-Null
    $arguments.Add($Destination) | Out-Null
    $arguments.Add('--clobber') | Out-Null
    return [string[]]$arguments.ToArray()
}

function New-GitHubCliWorkspace {
    <#
    .SYNOPSIS
        创建单次工具安装使用的临时工作目录。

    .PARAMETER Spec
        单个工具下载与安装计划。

    .OUTPUTS
        string。新建的临时工作目录路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Spec
    )

    $safeName = $Spec.Name -replace '[^A-Za-z0-9._-]', '-'
    $workspace = Join-Path $Spec.DownloadDirectory ("{0}-{1}" -f $safeName, [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workspace -Force | Out-Null
    return $workspace
}

function Invoke-GitHubCliReleaseDownload {
    <#
    .SYNOPSIS
        调用 GitHub CLI 下载 release asset。

    .PARAMETER Spec
        单个工具下载与安装计划。

    .PARAMETER Destination
        下载目标目录。

    .PARAMETER GhCommand
        GitHub CLI 命令名或路径。

    .OUTPUTS
        None。下载失败时抛出异常。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Spec,

        [Parameter(Mandatory)]
        [string]$Destination,

        [string]$GhCommand = 'gh'
    )

    if (-not (Get-Command $GhCommand -ErrorAction SilentlyContinue)) {
        throw "未找到 GitHub CLI 命令 '$GhCommand'。请先安装 gh 并确保它在 PATH 中。"
    }

    $arguments = New-GitHubCliDownloadArguments -Spec $Spec -Destination $Destination
    & $GhCommand @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "下载 GitHub release asset 失败: $($Spec.Name)"
    }
}

function Get-GitHubCliArchiveKind {
    <#
    .SYNOPSIS
        判断下载文件的压缩格式。

    .PARAMETER Path
        下载到本地的 release asset 路径。

    .OUTPUTS
        string。返回 `Zip` 或 `TarGz`。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($Path.EndsWith('.zip', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Zip'
    }

    if ($Path.EndsWith('.tar.gz', [System.StringComparison]::OrdinalIgnoreCase) -or $Path.EndsWith('.tgz', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'TarGz'
    }

    throw "不支持的压缩格式: $Path"
}

function Get-GitHubCliDownloadedAsset {
    <#
    .SYNOPSIS
        从下载目录定位 release asset 文件。

    .PARAMETER Directory
        `gh release download` 输出目录。

    .OUTPUTS
        string。唯一下载文件路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory
    )

    $files = @(Get-ChildItem -LiteralPath $Directory -File)
    if ($files.Count -eq 0) {
        throw "未在下载目录中找到 release asset: $Directory"
    }

    if ($files.Count -gt 1) {
        throw "asset pattern 匹配到多个文件，请收窄配置: $($files.Name -join ', ')"
    }

    return $files[0].FullName
}

function Expand-GitHubCliArchive {
    <#
    .SYNOPSIS
        解压 GitHub Release 下载包。

    .PARAMETER ArchivePath
        `.zip`、`.tar.gz` 或 `.tgz` 文件路径。

    .PARAMETER Destination
        解压目标目录。

    .OUTPUTS
        None。解压失败时抛出异常。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArchivePath,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $kind = Get-GitHubCliArchiveKind -Path $ArchivePath
    if ($kind -eq 'Zip') {
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Destination -Force
        return
    }

    $tarCommand = Get-Command tar -ErrorAction SilentlyContinue
    if (-not $tarCommand) {
        throw '未找到 tar 命令，无法解压 .tar.gz 文件。'
    }

    & $tarCommand.Source -xzf $ArchivePath -C $Destination
    if ($LASTEXITCODE -ne 0) {
        throw "解压 tar.gz 文件失败: $ArchivePath"
    }
}

function Find-GitHubCliExecutableCandidate {
    <#
    .SYNOPSIS
        在解压目录中定位需要安装的 CLI 可执行文件。

    .PARAMETER ExtractDirectory
        解压后的目录。

    .PARAMETER ExecutableName
        目标可执行文件名。

    .PARAMETER BinaryPath
        可选的压缩包内部相对路径。

    .OUTPUTS
        string。匹配到的可执行文件路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExtractDirectory,

        [Parameter(Mandatory)]
        [string]$ExecutableName,

        [string]$BinaryPath = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($BinaryPath)) {
        $candidate = Join-Path $ExtractDirectory $BinaryPath
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "压缩包内未找到配置的 binary_path: $BinaryPath"
        }
        return $candidate
    }

    $matches = @(Get-ChildItem -LiteralPath $ExtractDirectory -Recurse -File | Where-Object {
            [string]::Equals($_.Name, $ExecutableName, [System.StringComparison]::OrdinalIgnoreCase)
        } | Sort-Object FullName)
    if ($matches.Count -eq 0) {
        throw "解压目录中未找到可执行文件: $ExecutableName"
    }

    if ($matches.Count -gt 1) {
        throw "解压目录中找到多个同名可执行文件，请配置 binary_path: $($matches.FullName -join ', ')"
    }

    return $matches[0].FullName
}

function Install-GitHubCliExecutable {
    <#
    .SYNOPSIS
        将 CLI 可执行文件复制到安装目录。

    .PARAMETER SourcePath
        解压目录中的源可执行文件路径。

    .PARAMETER InstallDirectory
        目标安装目录。

    .PARAMETER ExecutableName
        安装后的可执行文件名。

    .PARAMETER Platform
        当前平台描述，用于非 Windows 设置执行权限。

    .PARAMETER NoOverwrite
        目标文件已存在时跳过安装。

    .OUTPUTS
        PSCustomObject。包含安装状态与目标路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$InstallDirectory,

        [Parameter(Mandatory)]
        [string]$ExecutableName,

        [Parameter(Mandatory)]
        [pscustomobject]$Platform,

        [switch]$NoOverwrite
    )

    New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
    $targetPath = Join-Path $InstallDirectory $ExecutableName
    if ($NoOverwrite -and (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        return [pscustomobject]@{
            Status = 'Skipped'
            Path   = $targetPath
        }
    }

    Copy-Item -LiteralPath $SourcePath -Destination $targetPath -Force
    if ($Platform.OperatingSystem -ne 'windows') {
        $chmodCommand = Get-Command chmod -ErrorAction SilentlyContinue
        if ($chmodCommand) {
            & $chmodCommand.Source '+x' $targetPath
        }
    }

    return [pscustomobject]@{
        Status = 'Installed'
        Path   = $targetPath
    }
}

function Test-GitHubCliDirectoryInPath {
    <#
    .SYNOPSIS
        判断安装目录是否已经位于 PATH 中。

    .PARAMETER Directory
        待检查的安装目录。

    .PARAMETER Platform
        当前平台描述，用于决定路径比较是否忽略大小写。

    .PARAMETER PathValue
        可选 PATH 字符串；默认读取当前进程 PATH。

    .OUTPUTS
        bool。目录已在 PATH 中时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [pscustomobject]$Platform,

        [AllowNull()]
        [string]$PathValue = $env:PATH
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $false
    }

    $comparison = if ($Platform.OperatingSystem -eq 'windows') {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $target = [System.IO.Path]::GetFullPath($Directory).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

    foreach ($entry in ($PathValue -split [regex]::Escape([System.IO.Path]::PathSeparator))) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }

        $entryPath = [System.IO.Path]::GetFullPath($entry).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        if ([string]::Equals($target, $entryPath, $comparison)) {
            return $true
        }
    }

    return $false
}

function Get-GitHubCliPathHint {
    <#
    .SYNOPSIS
        生成平台化 PATH 添加提示。

    .PARAMETER InstallDirectory
        CLI 安装目录。

    .PARAMETER Platform
        当前平台描述。

    .OUTPUTS
        string[]。可展示给用户的 PATH 添加命令或操作方法。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallDirectory,

        [Parameter(Mandatory)]
        [pscustomobject]$Platform
    )

    $escapedForSingleQuote = $InstallDirectory -replace "'", "''"
    switch ($Platform.OperatingSystem) {
        'windows' {
            return @(
                '安装目录尚未在 PATH 中。可在 PowerShell 中执行：',
                "[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User') + ';$escapedForSingleQuote', 'User')",
                '然后重新打开终端。'
            )
        }
        'macos' {
            return @(
                '安装目录尚未在 PATH 中。zsh 用户可执行：',
                "mkdir -p '$escapedForSingleQuote'",
                ('echo ''export PATH="{0}:$PATH"'' >> ~/.zshrc' -f $escapedForSingleQuote),
                '然后执行 source ~/.zshrc 或重新打开终端。'
            )
        }
        default {
            return @(
                '安装目录尚未在 PATH 中。bash/zsh 用户可执行：',
                "mkdir -p '$escapedForSingleQuote'",
                ('echo ''export PATH="{0}:$PATH"'' >> ~/.profile' -f $escapedForSingleQuote),
                '然后执行 source ~/.profile 或重新打开终端。'
            )
        }
    }
}

function Invoke-GitHubCliToolInstall {
    <#
    .SYNOPSIS
        执行单个 CLI 工具的下载、解压和安装。

    .PARAMETER Spec
        单个工具下载与安装计划。

    .PARAMETER NoOverwrite
        目标文件已存在时跳过安装。

    .PARAMETER KeepTemp
        安装结束后保留临时工作目录。

    .OUTPUTS
        PSCustomObject。包含安装状态、目标路径和 PATH 状态。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Spec,

        [switch]$NoOverwrite,

        [switch]$KeepTemp
    )

    $targetPath = Join-Path $Spec.InstallDirectory $Spec.ExecutableName
    if ($NoOverwrite -and (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        return [pscustomobject]@{
            Name        = $Spec.Name
            Status      = 'Skipped'
            Path        = $targetPath
            InPath      = Test-GitHubCliDirectoryInPath -Directory $Spec.InstallDirectory -Platform $Spec.Platform
            PathHints   = Get-GitHubCliPathHint -InstallDirectory $Spec.InstallDirectory -Platform $Spec.Platform
            Workspace   = ''
            Asset       = ''
        }
    }

    $workspace = New-GitHubCliWorkspace -Spec $Spec
    try {
        Invoke-GitHubCliReleaseDownload -Spec $Spec -Destination $workspace
        $assetPath = Get-GitHubCliDownloadedAsset -Directory $workspace
        $extractDirectory = Join-Path $workspace 'extract'
        Expand-GitHubCliArchive -ArchivePath $assetPath -Destination $extractDirectory
        $sourcePath = Find-GitHubCliExecutableCandidate -ExtractDirectory $extractDirectory -ExecutableName $Spec.ExecutableName -BinaryPath $Spec.BinaryPath
        $installResult = Install-GitHubCliExecutable -SourcePath $sourcePath -InstallDirectory $Spec.InstallDirectory -ExecutableName $Spec.ExecutableName -Platform $Spec.Platform -NoOverwrite:$NoOverwrite
        $inPath = Test-GitHubCliDirectoryInPath -Directory $Spec.InstallDirectory -Platform $Spec.Platform

        return [pscustomobject]@{
            Name        = $Spec.Name
            Status      = $installResult.Status
            Path        = $installResult.Path
            InPath      = $inPath
            PathHints   = if ($inPath) { @() } else { Get-GitHubCliPathHint -InstallDirectory $Spec.InstallDirectory -Platform $Spec.Platform }
            Workspace   = $workspace
            Asset       = $assetPath
        }
    }
    finally {
        if (-not $KeepTemp -and (Test-Path -LiteralPath $workspace)) {
            Remove-Item -LiteralPath $workspace -Recurse -Force
        }
    }
}

function Show-GitHubCliInstallResult {
    <#
    .SYNOPSIS
        输出单个工具安装结果。

    .PARAMETER Result
        `Invoke-GitHubCliToolInstall` 返回的结果对象。

    .OUTPUTS
        None。向终端输出状态信息。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Result
    )

    Write-Host ("{0}: {1} -> {2}" -f $Result.Name, $Result.Status, $Result.Path)
    if (-not $Result.InPath) {
        foreach ($line in $Result.PathHints) {
            Write-Host $line
        }
    }
}

function Invoke-GitHubCliDownloadMain {
    <#
    .SYNOPSIS
        下载脚本主入口。

    .PARAMETER ConfigPath
        JSON 配置文件路径。

    .PARAMETER Name
        需要安装的工具名称筛选列表。

    .PARAMETER DownloadDir
        下载缓存目录覆盖值。

    .PARAMETER NoOverwrite
        目标文件已存在时跳过安装。

    .PARAMETER KeepTemp
        保留临时工作目录。

    .PARAMETER DryRun
        只输出安装计划，不执行下载和安装。

    .OUTPUTS
        int。进程退出码。
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$ConfigPath,

        [string[]]$Name = @(),

        [string]$DownloadDir = '',

        [switch]$NoOverwrite,

        [switch]$KeepTemp,

        [switch]$DryRun
    )

    $cliParameters = @{}
    if (-not [string]::IsNullOrWhiteSpace($DownloadDir)) {
        $cliParameters['DownloadDir'] = $DownloadDir
    }

    $effectiveConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { Resolve-GitHubCliDefaultConfigPath } else { $ConfigPath }
    $config = Read-GitHubCliDownloadConfig -ConfigPath $effectiveConfigPath -CliParameters $cliParameters
    $platform = New-GitHubCliPlatform
    $specs = Resolve-GitHubCliDownloadSpecs -Config $config -Platform $platform -Name $Name

    if ($DryRun) {
        $preview = $specs | Format-Table Name, Repo, Tag, AssetPattern, ExecutableName, InstallDirectory | Out-String
        Write-Host $preview.TrimEnd()
        return 0
    }

    foreach ($spec in $specs) {
        $result = Invoke-GitHubCliToolInstall -Spec $spec -NoOverwrite:$NoOverwrite -KeepTemp:$KeepTemp
        Show-GitHubCliInstallResult -Result $result
    }

    return 0
}

if ($env:GITHUB_CLI_DOWNLOAD_SKIP_MAIN -ne '1') {
    try {
        exit (Invoke-GitHubCliDownloadMain -ConfigPath $ConfigPath -Name $Name -DownloadDir $DownloadDir -NoOverwrite:$NoOverwrite -KeepTemp:$KeepTemp -DryRun:$DryRun)
    }
    catch {
        Write-Error $_
        exit 1
    }
}
