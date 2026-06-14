#!/usr/bin/env pwsh
<#
.SYNOPSIS
    从 SSH config 与 JSON 增量配置启动项目入口。

.DESCRIPTION
    汇总 OpenSSH client config 的普通 Host 与 JSON 中声明的 WSL 启动项。
    未指定名称时复用 psutils 的交互选择封装；指定名称时直接生成并执行启动计划。

.PARAMETER Name
    要启动的入口名称。为空时进入交互选择。

.PARAMETER ConfigPath
    自定义 JSON 增量配置路径。传入 `foo.json` 时会额外读取同目录的 `foo.local.json`。
    未传入时自动读取当前目录的 `project-launcher.json` 与 `project-launcher.local.json`。

.PARAMETER SshConfigPath
    SSH client config 路径，默认使用当前用户的 `~/.ssh/config`。

.PARAMETER DryRun
    只输出将执行的命令计划，不启动 SSH 或 WSL。

.PARAMETER Inline
    在当前终端内直接执行 SSH 或 WSL。默认在 Windows 下打开新终端，避免交互会话占住选择器所在的 shell。

.PARAMETER Platform
    平台覆盖值，支持 `windows`、`linux`、`macos`，主要用于测试平台过滤。

.PARAMETER JsonDepth
    dry-run JSON 输出深度。
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$Name,

    [string]$ConfigPath,

    [string]$SshConfigPath,

    [switch]$DryRun,

    [switch]$Inline,

    [ValidateSet('windows', 'linux', 'macos')]
    [string]$Platform,

    [ValidateRange(3, 100)]
    [int]$JsonDepth = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    获取仓库根目录。

.DESCRIPTION
    基于当前脚本目录向上回溯，定位共享 psutils 模块所在的仓库根目录。

.OUTPUTS
    string
    返回仓库根目录绝对路径。
#>
function Get-ProjectLauncherRepoRoot {
    [CmdletBinding()]
    param()

    return (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..')).Path
}

<#
.SYNOPSIS
    导入启动器依赖的共享 psutils 模块。

.DESCRIPTION
    只导入公共配置读取与交互选择模块，保证启动器复用项目已有封装。

.PARAMETER RepoRoot
    仓库根目录。

.OUTPUTS
    None
    仅导入依赖模块，不返回值。
#>
function Import-ProjectLauncherDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $configModulePath = Join-Path $RepoRoot 'psutils' 'modules' 'config.psm1'
    $selectionModulePath = Join-Path $RepoRoot 'psutils' 'modules' 'selection.psm1'
    $processModulePath = Join-Path $RepoRoot 'psutils' 'modules' 'process.psm1'

    if (-not (Test-Path -LiteralPath $configModulePath -PathType Leaf)) {
        throw "配置模块不存在: $configModulePath"
    }
    if (-not (Test-Path -LiteralPath $selectionModulePath -PathType Leaf)) {
        throw "交互选择模块不存在: $selectionModulePath"
    }
    if (-not (Test-Path -LiteralPath $processModulePath -PathType Leaf)) {
        throw "进程工具模块不存在: $processModulePath"
    }

    Import-Module $configModulePath -Force -ErrorAction Stop
    Import-Module $selectionModulePath -Force -ErrorAction Stop
    Import-Module $processModulePath -Force -ErrorAction Stop
}

<#
.SYNOPSIS
    获取默认 SSH config 路径。

.DESCRIPTION
    使用当前用户主目录拼接 `.ssh/config`。该函数只解析路径，不验证文件存在。

.OUTPUTS
    string
    返回默认 SSH config 路径。
#>
function Resolve-ProjectLauncherDefaultSshConfigPath {
    [CmdletBinding()]
    param()

    $userHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if ([string]::IsNullOrWhiteSpace($userHome)) {
        $userHome = $env:HOME
    }
    if ([string]::IsNullOrWhiteSpace($userHome)) {
        throw '无法解析用户主目录。'
    }

    return [System.IO.Path]::Combine($userHome, '.ssh', 'config')
}

<#
.SYNOPSIS
    获取当前或覆盖的平台名称。

.DESCRIPTION
    将 PowerShell 平台变量规范化为 `windows`、`linux`、`macos`。

.PARAMETER Platform
    可选平台覆盖值。

.OUTPUTS
    string
    返回平台名称。
#>
function Resolve-ProjectLauncherPlatform {
    [CmdletBinding()]
    param(
        [string]$Platform
    )

    if (-not [string]::IsNullOrWhiteSpace($Platform)) {
        return $Platform.Trim().ToLowerInvariant()
    }

    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        return 'windows'
    }
    if ($IsMacOS) {
        return 'macos'
    }
    if ($IsLinux) {
        return 'linux'
    }

    throw '无法识别当前平台。'
}

<#
.SYNOPSIS
    判断启动器配置文件是否存在。

.DESCRIPTION
    通过共享路径解析器支持相对路径、`~` 与环境变量占位符，再判断文件是否存在。

.PARAMETER Path
    待检测的配置路径。

.PARAMETER BasePath
    相对路径解析基准。

.OUTPUTS
    bool
    返回配置文件是否存在。
#>
function Test-ProjectLauncherConfigFileExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $resolvedPath = Resolve-ConfigPath -Path $Path -BasePath $BasePath -Context 'projectLauncher.configPath'
    return (Test-Path -LiteralPath $resolvedPath -PathType Leaf)
}

<#
.SYNOPSIS
    生成显式配置文件对应的本机覆盖文件路径。

.DESCRIPTION
    `foo.json` 对应 `foo.local.json`；非 `.json` 结尾路径追加 `.local.json`。
    已经是 `.local.json` 的路径不会再生成二级覆盖文件。

.PARAMETER Path
    显式传入的配置路径。

.OUTPUTS
    string
    返回本机覆盖文件路径；无需覆盖文件时返回空字符串。
#>
function Resolve-ProjectLauncherLocalConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($Path -match '(?i)\.local\.json$') {
        return ''
    }

    if ($Path -match '(?i)\.json$') {
        return ($Path -replace '(?i)\.json$', '.local.json')
    }

    return "$Path.local.json"
}

<#
.SYNOPSIS
    解析启动器需要读取的 JSON 配置文件。

.DESCRIPTION
    显式配置文件必须存在；对应 `.local.json` 覆盖文件仅在存在时读取。
    未显式指定时，自动读取当前目录下存在的默认配置与本机覆盖配置。

.PARAMETER ConfigPath
    显式配置路径。

.PARAMETER BasePath
    相对路径解析基准。

.OUTPUTS
    PSCustomObject[]
    返回包含 `Path` 与 `Required` 的配置来源描述。
#>
function Resolve-ProjectLauncherConfigFiles {
    [CmdletBinding()]
    param(
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $files = New-Object 'System.Collections.Generic.List[object]'
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $files.Add([pscustomobject]@{
                Path     = $ConfigPath
                Required = $true
            }) | Out-Null

        $localPath = Resolve-ProjectLauncherLocalConfigPath -Path $ConfigPath
        if (
            -not [string]::IsNullOrWhiteSpace($localPath) -and
            (Test-ProjectLauncherConfigFileExists -Path $localPath -BasePath $BasePath)
        ) {
            $files.Add([pscustomobject]@{
                    Path     = $localPath
                    Required = $false
                }) | Out-Null
        }

        return $files.ToArray()
    }

    foreach ($defaultPath in @('project-launcher.json', 'project-launcher.local.json')) {
        if (Test-ProjectLauncherConfigFileExists -Path $defaultPath -BasePath $BasePath) {
            $files.Add([pscustomobject]@{
                    Path     = $defaultPath
                    Required = $false
                }) | Out-Null
        }
    }

    return $files.ToArray()
}

<#
.SYNOPSIS
    判断配置值是否适合按对象浅合并。

.DESCRIPTION
    仅 hashtable、字典和 PSCustomObject 参与浅合并；字符串、数组和数字等标量保持整体覆盖，
    避免把字符串的 Length 等属性误当作配置键。

.PARAMETER Value
    待判断的配置值。

.OUTPUTS
    bool
    返回该值是否适合转换为配置表并浅合并。
#>
function Test-ProjectLauncherMergeableConfigObject {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [string] -or $Value -is [array] -or $Value.GetType().IsPrimitive) {
        return $false
    }

    return (
        $Value -is [hashtable] -or
        $Value -is [System.Collections.IDictionary] -or
        $Value -is [pscustomobject]
    )
}

<#
.SYNOPSIS
    合并启动器 defaults 配置。

.DESCRIPTION
    defaults 下的普通键按后者覆盖前者；嵌套表按一层浅合并处理，
    用于让 `defaults.wsl.distro` 这类本机配置覆盖基础配置。

.PARAMETER CurrentDefaults
    当前已合并的 defaults。

.PARAMETER FragmentDefaults
    待合入的 defaults 片段。

.OUTPUTS
    hashtable
    返回合并后的 defaults。
#>
function Merge-ProjectLauncherDefaults {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$CurrentDefaults,

        [AllowNull()]
        [object]$FragmentDefaults
    )

    $merged = ConvertTo-ProjectLauncherHashtable -Value $CurrentDefaults
    $incoming = ConvertTo-ProjectLauncherHashtable -Value $FragmentDefaults

    foreach ($entry in $incoming.GetEnumerator()) {
        $existingValue = if ($merged.ContainsKey($entry.Key)) { $merged[$entry.Key] } else { $null }
        $canMergeNested = (
            (Test-ProjectLauncherMergeableConfigObject -Value $existingValue) -and
            (Test-ProjectLauncherMergeableConfigObject -Value $entry.Value)
        )

        if ($canMergeNested) {
            $existingTable = ConvertTo-ProjectLauncherHashtable -Value $existingValue
            $incomingTable = ConvertTo-ProjectLauncherHashtable -Value $entry.Value
            foreach ($nestedEntry in $incomingTable.GetEnumerator()) {
                $existingTable[$nestedEntry.Key] = $nestedEntry.Value
            }

            $merged[$entry.Key] = $existingTable
            continue
        }

        $merged[$entry.Key] = $entry.Value
    }

    return $merged
}

<#
.SYNOPSIS
    合并启动器 JSON 配置片段。

.DESCRIPTION
    `entries` 按来源顺序追加，避免本机 `.local.json` 覆盖基础配置；
    `defaults` 做浅层覆盖，其它键保留后者覆盖前者的常规配置语义。

.PARAMETER CurrentConfig
    当前已合并配置。

.PARAMETER Fragment
    待合入配置片段。

.OUTPUTS
    hashtable
    返回合并后的启动器配置。
#>
function Merge-ProjectLauncherConfigFragment {
    [CmdletBinding()]
    param(
        [hashtable]$CurrentConfig,

        [hashtable]$Fragment
    )

    $result = ConvertTo-ProjectLauncherHashtable -Value $CurrentConfig
    foreach ($entry in $Fragment.GetEnumerator()) {
        if ([string]::Equals([string]$entry.Key, 'entries', [System.StringComparison]::OrdinalIgnoreCase)) {
            $currentEntries = @(Get-ProjectLauncherConfigEntries -Config $result)
            $fragmentEntries = @(Get-ProjectLauncherConfigEntries -Config @{ entries = $entry.Value })
            $result.entries = @($currentEntries + $fragmentEntries)
            continue
        }

        if ([string]::Equals([string]$entry.Key, 'defaults', [System.StringComparison]::OrdinalIgnoreCase)) {
            $result.defaults = Merge-ProjectLauncherDefaults `
                -CurrentDefaults (Get-ConfigValue -Values $result -Name 'defaults') `
                -FragmentDefaults $entry.Value
            continue
        }

        $result[$entry.Key] = $entry.Value
    }

    return $result
}

<#
.SYNOPSIS
    读取启动器 JSON 增量配置。

.DESCRIPTION
    通过 `Resolve-ConfigSources` 读取 JSON 文件，让缺失文件处理与类型转换复用共享配置解析器。
    业务层再按 additive 语义追加 `entries`，避免 `.local.json` 覆盖基础配置。

.PARAMETER ConfigPath
    JSON 配置路径。为空时读取当前目录存在的默认配置与 `.local.json` 本机覆盖配置。

.PARAMETER BasePath
    相对配置路径解析基准。

.OUTPUTS
    hashtable
    返回配置键值表。
#>
function Read-ProjectLauncherJsonConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $sources = New-Object 'System.Collections.Generic.List[hashtable]'
    $sources.Add(@{
            Type = 'Hashtable'
            Name = 'Defaults'
            Data = @{
                defaults = @{}
                entries  = @()
            }
        }) | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $null = Resolve-ProjectLauncherConfigFiles -ConfigPath $ConfigPath -BasePath $BasePath
    }

    $config = (Resolve-ConfigSources -Sources $sources.ToArray() -BasePath $BasePath -ErrorOnMissing).Values
    foreach ($configFile in Resolve-ProjectLauncherConfigFiles -ConfigPath $ConfigPath -BasePath $BasePath) {
        $fragment = (Resolve-ConfigSources -Sources @(
                @{
                    Type = 'JsonFile'
                    Name = [System.IO.Path]::GetFileName([string]$configFile.Path)
                    Path = [string]$configFile.Path
                }
            ) -BasePath $BasePath -ErrorOnMissing:([bool]$configFile.Required)).Values
        $config = Merge-ProjectLauncherConfigFragment -CurrentConfig $config -Fragment $fragment
    }

    return $config
}

<#
.SYNOPSIS
    将配置值规范化为 hashtable。

.DESCRIPTION
    包装共享 `ConvertTo-ConfigHashtable`，允许调用方传入空值时得到空表。

.PARAMETER Value
    待转换的配置值。

.OUTPUTS
    hashtable
    返回普通 hashtable。
#>
function ConvertTo-ProjectLauncherHashtable {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return @{}
    }

    return ConvertTo-ConfigHashtable -InputObject $Value
}

<#
.SYNOPSIS
    将配置中的 entries 规范化为数组。

.DESCRIPTION
    PowerShell 对单个 JSON 对象与数组的枚举语义不同，启动器在边界处统一转成数组。

.PARAMETER Config
    已合并的配置表。

.OUTPUTS
    object[]
    返回 entry 配置数组。
#>
function Get-ProjectLauncherConfigEntries {
    [CmdletBinding()]
    param(
        [hashtable]$Config
    )

    $entries = Get-ConfigValue -Values $Config -Name 'entries' -DefaultValue @()
    if ($null -eq $entries) {
        return @()
    }

    if ($entries -is [array]) {
        return @($entries)
    }

    return @($entries)
}

<#
.SYNOPSIS
    读取 WSL 默认发行版。

.DESCRIPTION
    从 `defaults.wsl.distro` 读取默认值，不支持顶层旧字段。

.PARAMETER Config
    已合并的配置表。

.OUTPUTS
    string
    返回默认 WSL 发行版；未配置时返回空字符串。
#>
function Get-ProjectLauncherDefaultWslDistro {
    [CmdletBinding()]
    param(
        [hashtable]$Config
    )

    $defaults = ConvertTo-ProjectLauncherHashtable -Value (Get-ConfigValue -Values $Config -Name 'defaults')
    $wslDefaults = ConvertTo-ProjectLauncherHashtable -Value (Get-ConfigValue -Values $defaults -Name 'wsl')
    return [string](Get-ConfigValue -Values $wslDefaults -Name 'distro' -DefaultValue '')
}

<#
.SYNOPSIS
    将 SSH Host block 转换为启动项。

.DESCRIPTION
    只接收共享 SSH config 解析器标记为可启动的 Host，并保留连接字段供展示和测试使用。

.PARAMETER Block
    `Read-ConfigSshClientConfig` 返回的 Host block。

.OUTPUTS
    PSCustomObject
    返回启动项对象。
#>
function ConvertFrom-ProjectLauncherSshHostBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Block
    )

    $targetParts = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace([string]$Block.User)) {
        $targetParts.Add([string]$Block.User) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Block.HostName)) {
        $hostSummary = [string]$Block.HostName
        if (-not [string]::IsNullOrWhiteSpace([string]$Block.Port)) {
            $hostSummary = "{0}:{1}" -f $hostSummary, $Block.Port
        }
        $targetParts.Add($hostSummary) | Out-Null
    }

    $target = if ($targetParts.Count -eq 2) {
        "{0}@{1}" -f $targetParts[0], $targetParts[1]
    }
    elseif ($targetParts.Count -eq 1) {
        $targetParts[0]
    }
    else {
        [string]$Block.Host
    }

    return [pscustomobject]@{
        Name           = [string]$Block.Host
        Type           = 'ssh'
        DisplayName    = [string]$Block.Host
        Target         = $target
        CommandSummary = [string]$Block.RemoteCommand
        Source         = 'ssh-config'
        Hidden         = $false
        Order          = $null
        Tags           = @()
        Raw            = $Block
    }
}

<#
.SYNOPSIS
    从 SSH config 读取 SSH 启动项。

.DESCRIPTION
    缺失默认 SSH config 时返回空列表；显式传入路径时缺失会由共享读取器抛错。

.PARAMETER SshConfigPath
    SSH config 路径。

.PARAMETER IsExplicitPath
    是否为用户显式提供的路径。

.OUTPUTS
    object[]
    返回 SSH 启动项数组。
#>
function Get-ProjectLauncherSshItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SshConfigPath,

        [switch]$IsExplicitPath
    )

    if (-not (Test-Path -LiteralPath $SshConfigPath -PathType Leaf)) {
        if ($IsExplicitPath) {
            $null = Read-ConfigSshClientConfig -Path $SshConfigPath
        }

        return @()
    }

    $blocks = @(Read-ConfigSshClientConfig -Path $SshConfigPath)
    return @($blocks | Where-Object { $_.IsLaunchCandidate } | ForEach-Object {
            ConvertFrom-ProjectLauncherSshHostBlock -Block $_
        })
}

<#
.SYNOPSIS
    生成默认 zellij WSL 命令。

.DESCRIPTION
    当 WSL entry 没有显式 `command` 时，使用 `workDir` 与 `session`
    生成 `cd ... && exec zellij attach -c ...`。

.PARAMETER EntryName
    启动项名称，用于错误提示。

.PARAMETER WorkDir
    WSL 内工作目录。

.PARAMETER Session
    zellij session 名称。

.OUTPUTS
    string
    返回 WSL shell 命令。
#>
function New-ProjectLauncherWslZellijCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EntryName,

        [string]$WorkDir,

        [string]$Session
    )

    if ([string]::IsNullOrWhiteSpace($WorkDir) -or [string]::IsNullOrWhiteSpace($Session)) {
        throw "WSL 启动项缺少 command，且无法由 workDir/session 生成命令: $EntryName"
    }

    return "cd $WorkDir && exec zellij attach -c $Session"
}

<#
.SYNOPSIS
    创建 WSL 启动项。

.DESCRIPTION
    解析 entry 级 distro、全局默认 distro、command 与 zellij fallback。

.PARAMETER Entry
    JSON entry 配置表。

.PARAMETER DefaultDistro
    `defaults.wsl.distro` 默认发行版。

.OUTPUTS
    PSCustomObject
    返回 WSL 启动项。
#>
function New-ProjectLauncherWslItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Entry,

        [string]$DefaultDistro
    )

    $entryName = [string](Get-ConfigValue -Values $Entry -Name 'name')
    if ([string]::IsNullOrWhiteSpace($entryName)) {
        throw 'WSL 启动项必须声明 name。'
    }

    $distro = [string](Get-ConfigValue -Values $Entry -Name 'distro' -DefaultValue $DefaultDistro)
    if ([string]::IsNullOrWhiteSpace($distro)) {
        throw "WSL 启动项缺少 distro，且 defaults.wsl.distro 未配置: $entryName"
    }

    $command = [string](Get-ConfigValue -Values $Entry -Name 'command')
    if ([string]::IsNullOrWhiteSpace($command)) {
        $command = New-ProjectLauncherWslZellijCommand `
            -EntryName $entryName `
            -WorkDir ([string](Get-ConfigValue -Values $Entry -Name 'workDir')) `
            -Session ([string](Get-ConfigValue -Values $Entry -Name 'session'))
    }

    $displayName = [string](Get-ConfigValue -Values $Entry -Name 'displayName' -DefaultValue $entryName)
    $order = Get-ConfigValue -Values $Entry -Name 'order'
    $tags = Get-ConfigValue -Values $Entry -Name 'tags' -DefaultValue @()

    return [pscustomobject]@{
        Name           = $entryName
        Type           = 'wsl'
        DisplayName    = $displayName
        Target         = "WSL:$distro"
        CommandSummary = $command
        Source         = 'json'
        Hidden         = [bool](Get-ConfigValue -Values $Entry -Name 'hidden' -DefaultValue $false)
        Order          = $order
        Tags           = @($tags)
        Raw            = [pscustomobject]@{
            Distro  = $distro
            Command = $command
            Entry   = $Entry
        }
    }
}

<#
.SYNOPSIS
    将 JSON metadata 合并进已有启动项。

.DESCRIPTION
    只合并显示相关字段，不覆盖 SSH 连接字段或 WSL 命令字段。

.PARAMETER Item
    现有启动项。

.PARAMETER Entry
    JSON entry 配置表。

.OUTPUTS
    PSCustomObject
    返回更新后的启动项。
#>
function Merge-ProjectLauncherItemMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Item,

        [Parameter(Mandatory)]
        [hashtable]$Entry
    )

    $displayName = [string](Get-ConfigValue -Values $Entry -Name 'displayName')
    if (-not [string]::IsNullOrWhiteSpace($displayName)) {
        $Item.DisplayName = $displayName
    }

    if ($Entry.ContainsKey('hidden')) {
        $Item.Hidden = [bool](Get-ConfigValue -Values $Entry -Name 'hidden')
    }

    $order = Get-ConfigValue -Values $Entry -Name 'order'
    if ($null -ne $order) {
        $Item.Order = $order
    }

    $tags = Get-ConfigValue -Values $Entry -Name 'tags'
    if ($null -ne $tags) {
        $Item.Tags = @($tags)
    }

    if ($Item.Source -notmatch '\+json$') {
        $Item.Source = "$($Item.Source)+json"
    }

    return $Item
}

<#
.SYNOPSIS
    根据 SSH 与 JSON 来源构建启动 catalog。

.DESCRIPTION
    SSH config 是连接真相源。JSON entry 同名时只补显示元数据；
    JSON entry 为 `type=wsl` 且不同名时新增 WSL 启动项。

.PARAMETER SshItems
    SSH 启动项数组。

.PARAMETER Config
    JSON 配置表。

.PARAMETER Platform
    当前平台名称。非 Windows 平台会在构建阶段跳过 WSL entry，避免校验不可用配置。

.OUTPUTS
    object[]
    返回合并后的启动项列表。
#>
function New-ProjectLauncherCatalog {
    [CmdletBinding()]
    param(
        [object[]]$SshItems = @(),

        [hashtable]$Config = @{},

        [string]$Platform = 'windows'
    )

    $normalizedPlatform = if ([string]::IsNullOrWhiteSpace($Platform)) {
        'windows'
    }
    else {
        $Platform.Trim().ToLowerInvariant()
    }

    $catalogByName = [ordered]@{}
    foreach ($item in @($SshItems)) {
        if ([string]::IsNullOrWhiteSpace([string]$item.Name)) {
            continue
        }

        $catalogByName[[string]$item.Name] = $item
    }

    $defaultWslDistro = Get-ProjectLauncherDefaultWslDistro -Config $Config
    foreach ($rawEntry in Get-ProjectLauncherConfigEntries -Config $Config) {
        $entry = ConvertTo-ProjectLauncherHashtable -Value $rawEntry
        $type = [string](Get-ConfigValue -Values $entry -Name 'type')
        $entryName = [string](Get-ConfigValue -Values $entry -Name 'name')
        if ($normalizedPlatform -ne 'windows' -and $type.Trim().ToLowerInvariant() -eq 'wsl' -and [string]::IsNullOrWhiteSpace($entryName)) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($entryName)) {
            throw 'JSON entries 中的每一项都必须声明 name。'
        }

        if ($catalogByName.Contains($entryName)) {
            $catalogByName[$entryName] = Merge-ProjectLauncherItemMetadata -Item $catalogByName[$entryName] -Entry $entry
            continue
        }

        if ($normalizedPlatform -ne 'windows' -and $type.Trim().ToLowerInvariant() -eq 'wsl') {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($type)) {
            continue
        }

        switch ($type.ToLowerInvariant()) {
            'wsl' {
                $catalogByName[$entryName] = New-ProjectLauncherWslItem -Entry $entry -DefaultDistro $defaultWslDistro
            }
            default {
                throw "不支持的启动项类型: $type（$entryName）"
            }
        }
    }

    $items = @($catalogByName.Values | Where-Object { -not $_.Hidden })
    return @($items | Sort-Object `
            @{ Expression = { if ($null -eq $_.Order) { [int]::MaxValue } else { [int]$_.Order } } }, `
            @{ Expression = { $_.DisplayName } }, `
            @{ Expression = { $_.Name } })
}

<#
.SYNOPSIS
    按平台过滤启动项。

.DESCRIPTION
    非 Windows 平台过滤 WSL 项，普通 SSH 项保持可见。

.PARAMETER Items
    启动项数组。

.PARAMETER Platform
    当前平台名称。

.OUTPUTS
    object[]
    返回过滤后的启动项。
#>
function Filter-ProjectLauncherItemsForPlatform {
    [CmdletBinding()]
    param(
        [object[]]$Items,

        [Parameter(Mandatory)]
        [string]$Platform
    )

    return @($Items | Where-Object {
            $_.Type -ne 'wsl' -or $Platform -eq 'windows'
        })
}

<#
.SYNOPSIS
    格式化启动项的交互展示行。

.DESCRIPTION
    展示名称、类型、目标和命令摘要，供 `Select-InteractiveItem` 使用。

.PARAMETER Item
    启动项。

.OUTPUTS
    string
    返回单行展示文本。
#>
function Format-ProjectLauncherItemDisplay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Item
    )

    $parts = @(
        $Item.DisplayName
        "[$($Item.Type)]"
        $Item.Target
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$Item.CommandSummary)) {
        $parts += [string]$Item.CommandSummary
    }

    return ($parts -join '  ')
}

<#
.SYNOPSIS
    解析要启动的启动项。

.DESCRIPTION
    显式名称优先；未指定名称时复用 `Select-InteractiveItem` 交互选择。

.PARAMETER Items
    可用启动项。

.PARAMETER Name
    显式入口名称。

.OUTPUTS
    PSCustomObject
    返回选中的启动项；交互取消时返回 `$null`。
#>
function Resolve-ProjectLauncherItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Items,

        [string]$Name
    )

    if ($Items.Count -eq 0) {
        throw '没有可用的项目启动项。'
    }

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $selected = $Items | Where-Object { $_.Name -eq $Name -or $_.DisplayName -eq $Name } | Select-Object -First 1
        if ($null -ne $selected) {
            return $selected
        }

        $availableNames = ($Items | ForEach-Object { $_.Name } | Sort-Object) -join ', '
        throw "未知项目启动项: $Name。可用值: $availableNames"
    }

    return Select-InteractiveItem `
        -Items $Items `
        -DisplayScriptBlock { Format-ProjectLauncherItemDisplay -Item $_ } `
        -Prompt 'Project > ' `
        -Header '请选择要启动的项目'
}

<#
.SYNOPSIS
    判断 SSH 启动项是否应强制分配 TTY。

.DESCRIPTION
    项目启动器面向交互式会话，默认使用 `ssh -tt <Host>`，避免脚本环境下
    OpenSSH 未分配伪终端导致远端 shell 无提示符。若 SSH config 明确声明
    `RequestTTY no`，则尊重用户配置，不额外添加 TTY 参数。

.PARAMETER Item
    SSH 启动项。

.OUTPUTS
    bool
    返回是否应为该 SSH 启动项追加 `-tt`。
#>
function Test-ProjectLauncherSshForceTty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Item
    )

    $requestTty = [string]$Item.Raw.RequestTTY
    return -not [string]::Equals($requestTty.Trim(), 'no', [System.StringComparison]::OrdinalIgnoreCase)
}

<#
.SYNOPSIS
    为启动项生成执行计划。

.DESCRIPTION
    执行计划包含可执行程序、参数数组和展示用命令行。

.PARAMETER Item
    启动项。

.OUTPUTS
    PSCustomObject
    返回执行计划。
#>
function New-ProjectLauncherExecutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Item
    )

    switch ($Item.Type) {
        'ssh' {
            $args = if (Test-ProjectLauncherSshForceTty -Item $Item) {
                @('-tt', [string]$Item.Name)
            }
            else {
                @([string]$Item.Name)
            }

            return [pscustomobject]@{
                Type        = 'ssh'
                Executable  = 'ssh'
                Arguments   = $args
                CommandLine = Format-NativeCommandLine -Command 'ssh' -ArgumentList $args
                Item        = $Item
            }
        }
        'wsl' {
            $distro = [string]$Item.Raw.Distro
            $command = [string]$Item.Raw.Command
            $args = @('-d', $distro, '--', 'bash', '-lc', $command)
            return [pscustomobject]@{
                Type        = 'wsl'
                Executable  = 'wsl.exe'
                Arguments   = $args
                CommandLine = Format-NativeCommandLine -Command 'wsl.exe' -ArgumentList $args
                Item        = $Item
            }
        }
        default {
            throw "不支持的启动项类型: $($Item.Type)"
        }
    }
}

<#
.SYNOPSIS
    判断执行计划是否适合在新终端中启动。

.DESCRIPTION
    SSH 与 WSL 会话通常需要完整交互式终端。Windows 下默认把它们放到新终端，
    避免 fzf 或宿主 shell 的输入模式影响远端会话。

.PARAMETER Plan
    `New-ProjectLauncherExecutionPlan` 生成的执行计划。

.PARAMETER Platform
    当前平台名称。

.PARAMETER Inline
    是否强制在当前终端内执行。

.OUTPUTS
    bool
    返回是否应使用新终端启动。
#>
function Test-ProjectLauncherShouldOpenTerminal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,

        [Parameter(Mandatory)]
        [string]$Platform,

        [switch]$Inline
    )

    if ($Inline) {
        return $false
    }

    $typeProperty = $Plan.PSObject.Properties['Type']
    if ($null -eq $typeProperty) {
        return $false
    }

    return (
        [string]::Equals($Platform, 'windows', [System.StringComparison]::OrdinalIgnoreCase) -and
        @('ssh', 'wsl') -contains [string]$typeProperty.Value
    )
}

<#
.SYNOPSIS
    查找 Windows Terminal 可执行文件。

.DESCRIPTION
    启动器优先用 Windows Terminal 承载 SSH/WSL 交互会话，找不到时返回空字符串，
    后续调用方会降级到独立 PowerShell 控制台。

.OUTPUTS
    string
    返回 `wt.exe` 路径；未找到时返回空字符串。
#>
function Resolve-ProjectLauncherWindowsTerminalPath {
    [CmdletBinding()]
    param()

    $command = Get-Command -Name 'wt.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        return ''
    }

    return [string]$command.Source
}

<#
.SYNOPSIS
    查找当前 PowerShell 可执行文件。

.DESCRIPTION
    新终端承载层需要一个 PowerShell 进程执行临时脚本，再由临时脚本按参数数组调用 SSH/WSL。
    这样可以避免 Windows Terminal 或 `cmd.exe` 对分号、引号和 `&&` 做二次解释。

.OUTPUTS
    string
    返回 PowerShell 可执行文件路径；找不到具体文件时返回 `pwsh`。
#>
function Resolve-ProjectLauncherPowerShellPath {
    [CmdletBinding()]
    param()

    $pwshPath = Join-Path $PSHOME 'pwsh.exe'
    if (Test-Path -LiteralPath $pwshPath -PathType Leaf) {
        return $pwshPath
    }

    $pwshCommand = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $pwshCommand) {
        return [string]$pwshCommand.Source
    }

    return 'pwsh'
}

<#
.SYNOPSIS
    将值转换成 PowerShell 单引号字面量。

.DESCRIPTION
    用于生成新终端内执行的短脚本。所有原生命令参数都按单引号字面量写入数组，
    避免 shell 重新拆分空格、引号或 `&&`。

.PARAMETER Value
    待转换的值。

.OUTPUTS
    string
    返回 PowerShell 单引号字符串字面量。
#>
function ConvertTo-ProjectLauncherPowerShellLiteral {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    return "'{0}'" -f ([string]$Value -replace "'", "''")
}

<#
.SYNOPSIS
    生成新终端内执行的 PowerShell 脚本内容。

.DESCRIPTION
    脚本以 `& <executable> @(<args>)` 形式调用真实 SSH/WSL，保留参数数组边界。
    脚本结束时会尝试删除自身，避免临时目录长期积累启动脚本。

.PARAMETER Plan
    `New-ProjectLauncherExecutionPlan` 生成的执行计划。

.OUTPUTS
    string
    返回临时启动脚本内容。
#>
function New-ProjectLauncherTerminalScriptContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

    $executableLiteral = ConvertTo-ProjectLauncherPowerShellLiteral -Value $Plan.Executable
    $argumentLiterals = @($Plan.Arguments | ForEach-Object {
            ConvertTo-ProjectLauncherPowerShellLiteral -Value $_
        })
    $argumentExpression = if ($argumentLiterals.Count -gt 0) {
        '@({0})' -f ($argumentLiterals -join ', ')
    }
    else {
        '@()'
    }

    return @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
`$exitCode = 0
try {
    & $executableLiteral $argumentExpression
    if (`$null -ne `$global:LASTEXITCODE) {
        `$exitCode = [int]`$global:LASTEXITCODE
    }
}
catch {
    Write-Error `$_.Exception.Message
    `$exitCode = 1
}
finally {
    if (-not [string]::IsNullOrWhiteSpace(`$PSCommandPath)) {
        Remove-Item -LiteralPath `$PSCommandPath -Force -ErrorAction SilentlyContinue
    }
}

if (`$exitCode -ne 0) {
    Write-Host ''
    Write-Host ("退出码: {0}" -f `$exitCode) -ForegroundColor DarkGray
}
"@
}

<#
.SYNOPSIS
    为新终端会话创建临时启动脚本。

.DESCRIPTION
    将执行计划写入用户临时目录中的 `.ps1` 文件，供 `pwsh -File` 使用。
    使用临时脚本可以避开 Windows Terminal 对 `;` 的命令分隔解析。

.PARAMETER Plan
    `New-ProjectLauncherExecutionPlan` 生成的执行计划。

.OUTPUTS
    string
    返回临时脚本路径。
#>
function New-ProjectLauncherTerminalScriptFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

    $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ('project-launcher-{0}.ps1' -f [Guid]::NewGuid().ToString('N'))
    Set-Content -LiteralPath $scriptPath -Encoding utf8NoBOM -Value (New-ProjectLauncherTerminalScriptContent -Plan $Plan)
    return $scriptPath
}

<#
.SYNOPSIS
    为执行计划生成 PowerShell 承载参数。

.DESCRIPTION
    使用 `-NoExit -File <script>` 保留终端窗口，用户能看到 SSH/WSL 退出后的错误或状态。

.PARAMETER ScriptPath
    `New-ProjectLauncherTerminalScriptFile` 创建的临时脚本路径。

.OUTPUTS
    string[]
    返回传给 PowerShell 可执行文件的参数数组。
#>
function New-ProjectLauncherTerminalPowerShellArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    return @(
        '-NoLogo',
        '-NoProfile',
        '-NoExit',
        '-File',
        $ScriptPath
    )
}

<#
.SYNOPSIS
    启动一个原生子进程。

.DESCRIPTION
    使用 `ProcessStartInfo.ArgumentList` 传参，避免把带空格的 WSL shell 命令手工拼成
    易错的命令行字符串。函数只负责启动，不等待交互会话退出。

.PARAMETER FilePath
    要启动的可执行文件路径或命令名。

.PARAMETER ArgumentList
    原生命令参数数组。

.OUTPUTS
    int
    返回新进程 PID；如果平台未返回进程对象则返回 0。
#>
function Start-ProjectLauncherNativeProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList = @()
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = Resolve-NativeExecutablePath -Command $FilePath
    foreach ($argument in @($ArgumentList)) {
        [void]$startInfo.ArgumentList.Add([string]$argument)
    }
    $startInfo.UseShellExecute = $true

    $process = [System.Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) {
        return 0
    }

    try {
        return [int]$process.Id
    }
    finally {
        $process.Dispose()
    }
}

<#
.SYNOPSIS
    为执行计划生成 Windows Terminal 参数。

.DESCRIPTION
    使用 `wt.exe -w 0 new-tab --title <title> pwsh -NoExit -File <script>`，
    优先复用最近的 Windows Terminal 窗口；如果当前没有窗口，Windows Terminal 会创建新窗口。
    临时脚本内部通过 PowerShell 参数数组调用真实命令，避免展示命令行被 `wt.exe` 或 `cmd.exe` 重新解释。

.PARAMETER Plan
    `New-ProjectLauncherExecutionPlan` 生成的执行计划。

.PARAMETER ScriptPath
    `New-ProjectLauncherTerminalScriptFile` 创建的临时脚本路径。

.OUTPUTS
    string[]
    返回传给 `wt.exe` 的参数数组。
#>
function New-ProjectLauncherWindowsTerminalArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,

        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    $title = [string]$Plan.Item.DisplayName
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = [string]$Plan.Item.Name
    }
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = [string]$Plan.Type
    }

    return @('-w', '0', 'new-tab', '--title', $title, (Resolve-ProjectLauncherPowerShellPath)) +
        (New-ProjectLauncherTerminalPowerShellArguments -ScriptPath $ScriptPath)
}

<#
.SYNOPSIS
    为执行计划生成传统控制台 fallback 参数。

.DESCRIPTION
    当 Windows Terminal 不可用时直接启动新的 PowerShell 控制台承载 SSH/WSL。

.PARAMETER ScriptPath
    `New-ProjectLauncherTerminalScriptFile` 创建的临时脚本路径。

.OUTPUTS
    string[]
    返回传给 PowerShell 可执行文件的参数数组。
#>
function New-ProjectLauncherPowerShellFallbackArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    return New-ProjectLauncherTerminalPowerShellArguments -ScriptPath $ScriptPath
}

<#
.SYNOPSIS
    在新终端中启动执行计划。

.DESCRIPTION
    Windows 下优先打开 Windows Terminal 新标签页；没有 `wt.exe` 时退到独立 PowerShell 控制台。
    函数立即返回，不等待 SSH/WSL 交互会话结束。

.PARAMETER Plan
    `New-ProjectLauncherExecutionPlan` 生成的执行计划。

.OUTPUTS
    PSCustomObject
    返回启动结果，包含实际承载终端与 PID。
#>
function Start-ProjectLauncherTerminalSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

    $scriptPath = New-ProjectLauncherTerminalScriptFile -Plan $Plan
    $terminalPath = Resolve-ProjectLauncherWindowsTerminalPath
    if (-not [string]::IsNullOrWhiteSpace($terminalPath)) {
        $terminalArguments = New-ProjectLauncherWindowsTerminalArguments -Plan $Plan -ScriptPath $scriptPath
        $processId = Start-ProjectLauncherNativeProcess -FilePath $terminalPath -ArgumentList $terminalArguments
        return [pscustomobject]@{
            Mode       = 'windows-terminal'
            FilePath   = $terminalPath
            Arguments  = $terminalArguments
            ScriptPath = $scriptPath
            ProcessId  = $processId
            Detached   = $true
        }
    }

    $fallbackPath = Resolve-ProjectLauncherPowerShellPath
    $fallbackArguments = New-ProjectLauncherPowerShellFallbackArguments -ScriptPath $scriptPath
    $fallbackProcessId = Start-ProjectLauncherNativeProcess -FilePath $fallbackPath -ArgumentList $fallbackArguments
    return [pscustomobject]@{
        Mode       = 'powershell'
        FilePath   = $fallbackPath
        Arguments  = $fallbackArguments
        ScriptPath = $scriptPath
        ProcessId  = $fallbackProcessId
        Detached   = $true
    }
}

<#
.SYNOPSIS
    执行启动计划。

.DESCRIPTION
    dry-run 返回计划对象；真实执行时调用外部命令并返回退出码。

.PARAMETER Plan
    `New-ProjectLauncherExecutionPlan` 生成的执行计划。

.PARAMETER DryRun
    是否只预览计划。

.PARAMETER Platform
    当前平台名称，用于判断是否需要在新终端中启动交互会话。

.PARAMETER Inline
    是否强制在当前终端内执行。

.OUTPUTS
    PSCustomObject
    返回执行结果。
#>
function Invoke-ProjectLauncherExecutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,

        [switch]$DryRun,

        [string]$Platform = 'windows',

        [switch]$Inline
    )

    if ($DryRun) {
        return [pscustomobject]@{
            ExitCode = 0
            Plan     = $Plan
            DryRun   = $true
            Detached = $false
        }
    }

    Write-Host ("启动: {0}" -f $Plan.CommandLine) -ForegroundColor Cyan
    if (Test-ProjectLauncherShouldOpenTerminal -Plan $Plan -Platform $Platform -Inline:$Inline) {
        $terminalResult = Start-ProjectLauncherTerminalSession -Plan $Plan
        Write-Host ("已打开新终端: {0}" -f $terminalResult.Mode) -ForegroundColor DarkGray
        return [pscustomobject]@{
            ExitCode       = 0
            Plan           = $Plan
            DryRun         = $false
            Detached       = $true
            TerminalResult = $terminalResult
        }
    }

    & $Plan.Executable @($Plan.Arguments)
    $lastExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $exitCode = if ($null -eq $lastExitCodeVariable -or $null -eq $lastExitCodeVariable.Value) {
        0
    }
    else {
        [int]$lastExitCodeVariable.Value
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Plan     = $Plan
        DryRun   = $false
        Detached = $false
    }
}

<#
.SYNOPSIS
    执行项目启动器主流程。

.DESCRIPTION
    读取配置来源、构建 catalog、过滤平台、解析选中项并执行或预览。

.PARAMETER Name
    要启动的入口名称。

.PARAMETER ConfigPath
    JSON 增量配置路径。

.PARAMETER SshConfigPath
    SSH config 路径。

.PARAMETER DryRun
    是否预览执行计划。

.PARAMETER Inline
    是否在当前终端内执行 SSH/WSL。默认 Windows 下打开新终端。

.PARAMETER Platform
    平台覆盖值。

.OUTPUTS
    PSCustomObject
    返回启动器执行结果。
#>
function Invoke-ProjectLauncherCommand {
    [CmdletBinding()]
    param(
        [string]$Name,

        [string]$ConfigPath,

        [string]$SshConfigPath,

        [switch]$DryRun,

        [switch]$Inline,

        [string]$Platform
    )

    $repoRoot = Get-ProjectLauncherRepoRoot
    Import-ProjectLauncherDependencies -RepoRoot $repoRoot

    $resolvedPlatform = Resolve-ProjectLauncherPlatform -Platform $Platform
    $effectiveSshConfigPath = if ([string]::IsNullOrWhiteSpace($SshConfigPath)) {
        Resolve-ProjectLauncherDefaultSshConfigPath
    }
    else {
        $SshConfigPath
    }

    $config = Read-ProjectLauncherJsonConfig -ConfigPath $ConfigPath -BasePath (Get-Location).Path
    $sshItems = Get-ProjectLauncherSshItems `
        -SshConfigPath $effectiveSshConfigPath `
        -IsExplicitPath:($PSBoundParameters.ContainsKey('SshConfigPath') -and -not [string]::IsNullOrWhiteSpace($SshConfigPath))
    $catalog = New-ProjectLauncherCatalog -SshItems $sshItems -Config $config -Platform $resolvedPlatform
    $filteredCatalog = Filter-ProjectLauncherItemsForPlatform -Items $catalog -Platform $resolvedPlatform
    $selected = Resolve-ProjectLauncherItem -Items $filteredCatalog -Name $Name

    if ($null -eq $selected) {
        return [pscustomobject]@{
            ExitCode = 0
            Selected = $null
            Plan     = $null
            DryRun   = [bool]$DryRun
            Detached = $false
        }
    }

    $plan = New-ProjectLauncherExecutionPlan -Item $selected
    $result = Invoke-ProjectLauncherExecutionPlan -Plan $plan -DryRun:$DryRun -Platform $resolvedPlatform -Inline:$Inline
    return [pscustomobject]@{
        ExitCode = $result.ExitCode
        Selected = $selected
        Plan     = $plan
        DryRun   = [bool]$DryRun
        Detached = [bool]$result.Detached
    }
}

if ($env:PWSH_TEST_SKIP_PROJECT_LAUNCHER_MAIN -eq '1') {
    return
}

try {
    $commandResult = Invoke-ProjectLauncherCommand `
        -Name $Name `
        -ConfigPath $ConfigPath `
        -SshConfigPath $SshConfigPath `
        -DryRun:$DryRun `
        -Inline:$Inline `
        -Platform $Platform

    if ($DryRun -and $null -ne $commandResult.Plan) {
        $commandResult.Plan | Select-Object Type, Executable, Arguments, CommandLine | ConvertTo-Json -Depth $JsonDepth
    }

    exit $commandResult.ExitCode
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
