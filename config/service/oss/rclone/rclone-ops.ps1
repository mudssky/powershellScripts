#!/usr/bin/env pwsh

<#
.SYNOPSIS
    通用 rclone 运维入口。

.DESCRIPTION
    从 JSON 主配置生成本地 rclone.conf，并提供 WebUI/RC、挂载、复制、同步、校验等常用入口。
    JSON 使用 remotes 列表表达多 remote；密钥可直接写入本地 JSON，或用 ${ENV_VAR} 从进程环境变量注入。
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ArgumentList = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RcloneOpsRoot = Split-Path -Parent $PSCommandPath
$script:DefaultSourcePath = Join-Path $script:RcloneOpsRoot 'rclone.config.local.json'
$script:DefaultConfigPath = Join-Path $script:RcloneOpsRoot 'rclone.conf'
$script:DefaultRuntimeDir = Join-Path $script:RcloneOpsRoot '.runtime'
$script:DefaultLogDir = Join-Path $script:DefaultRuntimeDir 'logs'
$script:DefaultRcAddr = '127.0.0.1:5572'
$script:DefaultRcUser = 'admin'
$script:ConfigParserLoaded = $false

function Split-RcloneOpsArguments {
    <#
    .SYNOPSIS
        解析 rclone-ops 命令参数。

    .PARAMETER ArgumentList
        待解析的参数数组，`--` 之后的内容会作为 rclone 透传参数保留。

    .OUTPUTS
        PSCustomObject。包含 Positionals、Flags 与 Passthrough 三个字段。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ArgumentList
    )

    $positionals = [System.Collections.Generic.List[string]]::new()
    $passthrough = [System.Collections.Generic.List[string]]::new()
    $flags = @{}
    $passthroughMode = $false

    for ($index = 0; $index -lt $ArgumentList.Count; $index++) {
        $item = $ArgumentList[$index]
        if ($passthroughMode) {
            $passthrough.Add($item)
            continue
        }

        if ($item -eq '--') {
            $passthroughMode = $true
            continue
        }

        if (-not $item.StartsWith('--')) {
            $positionals.Add($item)
            continue
        }

        $flagText = $item.Substring(2)
        $equalsIndex = $flagText.IndexOf('=')
        if ($equalsIndex -ge 0) {
            $flags[$flagText.Substring(0, $equalsIndex)] = $flagText.Substring($equalsIndex + 1)
            continue
        }

        $nextIndex = $index + 1
        if ($nextIndex -lt $ArgumentList.Count -and -not $ArgumentList[$nextIndex].StartsWith('--')) {
            $flags[$flagText] = $ArgumentList[$nextIndex]
            $index++
            continue
        }

        $flags[$flagText] = $true
    }

    [PSCustomObject]@{
        Positionals = [string[]]$positionals.ToArray()
        Flags       = $flags
        Passthrough = [string[]]$passthrough.ToArray()
    }
}

function Get-RcloneOpsOption {
    <#
    .SYNOPSIS
        按 flag、环境变量、默认值的优先级解析选项。

    .PARAMETER Flags
        Split-RcloneOpsArguments 返回的 Flags 哈希表。

    .PARAMETER Name
        命令行 flag 名称，不包含前缀 `--`。

    .PARAMETER EnvName
        环境变量名称。

    .PARAMETER DefaultValue
        未提供 flag 与环境变量时使用的默认值。

    .OUTPUTS
        System.String。解析后的选项值。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Flags,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$EnvName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$DefaultValue
    )

    if ($Flags.ContainsKey($Name) -and $Flags[$Name] -is [string] -and -not [string]::IsNullOrWhiteSpace($Flags[$Name])) {
        return [string]$Flags[$Name]
    }

    $envValue = [Environment]::GetEnvironmentVariable($EnvName, 'Process')
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
        return $envValue
    }

    return $DefaultValue
}

function Import-RcloneOpsConfigParser {
    <#
    .SYNOPSIS
        加载仓库共享配置解析器。

    .DESCRIPTION
        运行脚本可能不在模块上下文中，通过 config.psm1 复用 `psutils/src/config` 的严格 dotenv/JSON 解析逻辑，
        避免 rclone 运维脚本继续维护一套独立 parser。

    .OUTPUTS
        None。加载 Resolve-ConfigSources 等函数到当前作用域。
    #>
    [CmdletBinding()]
    param()

    if ($script:ConfigParserLoaded) {
        return
    }

    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $script:RcloneOpsRoot '../../../..'))
    $configModulePath = Join-Path $repoRoot 'psutils/modules/config.psm1'
    if (-not (Test-Path -LiteralPath $configModulePath -PathType Leaf)) {
        throw "未找到共享配置解析器模块: $configModulePath"
    }

    # config.psm1 以 source-first 方式加载 psutils/src/config，脚本只依赖导出的公共入口。
    Import-Module $configModulePath -Force
    $script:ConfigParserLoaded = $true
}

function Read-RcloneOpsConfigValues {
    <#
    .SYNOPSIS
        读取 rclone JSON 主配置。

    .PARAMETER ConfigPath
        JSON 配置文件路径；相对路径按当前工作目录解析。

    .OUTPUTS
        hashtable。由 psutils/src/config 解析出的 JSON 顶层配置键值。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if ($ConfigPath -notmatch '\.json$') {
        throw 'rclone-ops 仅支持 JSON 主配置；.env 不再用于表达多 remote 配置。'
    }

    Import-RcloneOpsConfigParser
    $resolved = Resolve-ConfigSources -ConfigFile $ConfigPath -BasePath (Get-Location).Path -ErrorOnMissing
    return $resolved.Values
}

function ConvertTo-RcloneOpsHashtable {
    <#
    .SYNOPSIS
        将配置对象转换为 hashtable。

    .PARAMETER InputObject
        待转换的配置对象，可为 hashtable、PSCustomObject 或 JSON 解析后的对象。

    .OUTPUTS
        hashtable。转换后的浅层键值表。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$InputObject
    )

    Import-RcloneOpsConfigParser
    return ConvertTo-ConfigHashtable -InputObject $InputObject
}

function Get-RcloneOpsConfigValue {
    <#
    .SYNOPSIS
        按大小写不敏感方式读取配置键。

    .PARAMETER Values
        配置键值表。

    .PARAMETER Name
        要读取的键名。

    .OUTPUTS
        object。命中的配置值；未命中时返回 $null。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Values,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Import-RcloneOpsConfigParser
    return Get-ConfigValue -Values $Values -Name $Name
}

function Get-RcloneOpsOptionalConfigValues {
    <#
    .SYNOPSIS
        读取可选的 rclone JSON 主配置。

    .PARAMETER ConfigPath
        JSON 配置文件路径；文件不存在时返回空表。

    .OUTPUTS
        hashtable。存在配置时返回顶层配置键值，否则返回空 hashtable。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $resolvedPath = if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
        $ConfigPath
    }
    else {
        Join-Path (Get-Location).Path $ConfigPath
    }

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        return @{}
    }

    return Read-RcloneOpsConfigValues -ConfigPath $ConfigPath
}

function Get-RcloneOpsNestedConfigValue {
    <#
    .SYNOPSIS
        读取嵌套 JSON 配置值。

    .PARAMETER ConfigValues
        顶层 JSON 配置键值。

    .PARAMETER Section
        顶层 section 名称，例如 `webui`。

    .PARAMETER Name
        section 内部键名。

    .OUTPUTS
        object。命中的嵌套配置值；未命中时返回 $null。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ConfigValues,

        [Parameter(Mandatory = $true)]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $sectionValue = Get-RcloneOpsConfigValue -Values $ConfigValues -Name $Section
    if ($null -eq $sectionValue) {
        return $null
    }

    $sectionTable = ConvertTo-RcloneOpsHashtable -InputObject $sectionValue
    return Get-RcloneOpsConfigValue -Values $sectionTable -Name $Name
}

function Get-RcloneOpsOptionWithConfig {
    <#
    .SYNOPSIS
        按 flag、环境变量、JSON 配置、默认值的优先级解析选项。

    .PARAMETER Flags
        Split-RcloneOpsArguments 返回的 Flags 哈希表。

    .PARAMETER Name
        命令行 flag 名称，不包含前缀 `--`。

    .PARAMETER EnvName
        环境变量名称。

    .PARAMETER ConfigValues
        顶层 JSON 配置键值。

    .PARAMETER Section
        JSON section 名称。

    .PARAMETER ConfigName
        JSON section 内部键名。

    .PARAMETER DefaultValue
        未提供 flag、环境变量与 JSON 配置时使用的默认值。

    .OUTPUTS
        System.String。解析后的选项值。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Flags,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$EnvName,

        [Parameter(Mandatory = $true)]
        [hashtable]$ConfigValues,

        [Parameter(Mandatory = $true)]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$ConfigName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$DefaultValue
    )

    if ($Flags.ContainsKey($Name) -and $Flags[$Name] -is [string] -and -not [string]::IsNullOrWhiteSpace($Flags[$Name])) {
        return [string]$Flags[$Name]
    }

    $envValue = [Environment]::GetEnvironmentVariable($EnvName, 'Process')
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
        return $envValue
    }

    $configValue = Get-RcloneOpsNestedConfigValue -ConfigValues $ConfigValues -Section $Section -Name $ConfigName
    if ($null -ne $configValue -and -not [string]::IsNullOrWhiteSpace([string]$configValue)) {
        return [string](Resolve-RcloneOpsEnvPlaceholder -Value $configValue -Context "$Section.$ConfigName")
    }

    return $DefaultValue
}

function Get-RcloneOpsWebUiLogFile {
    <#
    .SYNOPSIS
        解析 WebUI 后台日志文件路径。

    .PARAMETER Flags
        Split-RcloneOpsArguments 返回的 Flags 哈希表。

    .PARAMETER ConfigValues
        顶层 JSON 配置键值。

    .PARAMETER BasePath
        JSON 主配置所在目录，用于解析 JSON 中的相对日志路径。

    .OUTPUTS
        System.String。WebUI 后台日志文件路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Flags,

        [Parameter(Mandatory = $true)]
        [hashtable]$ConfigValues,

        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    if ($Flags.ContainsKey('log-file') -and $Flags['log-file'] -is [string] -and -not [string]::IsNullOrWhiteSpace($Flags['log-file'])) {
        return [string]$Flags['log-file']
    }

    $envValue = [Environment]::GetEnvironmentVariable('RCLONE_LOG_FILE', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
        return $envValue
    }

    $configValue = Get-RcloneOpsNestedConfigValue -ConfigValues $ConfigValues -Section 'webui' -Name 'log-file'
    if ($null -ne $configValue -and -not [string]::IsNullOrWhiteSpace([string]$configValue)) {
        $resolvedValue = Resolve-RcloneOpsEnvPlaceholder -Value $configValue -Context 'webui.log-file'
        return Resolve-RcloneOpsFileSystemPath -Path $resolvedValue -BasePath $BasePath -Context 'webui.log-file'
    }

    return (Join-Path $script:DefaultLogDir 'webui.log')
}

function Resolve-RcloneOpsEnvPlaceholder {
    <#
    .SYNOPSIS
        替换 JSON 配置字符串中的环境变量占位符。

    .DESCRIPTION
        支持 `${VAR_NAME}` 形式的占位符。缺失变量直接抛错，避免静默生成不可用的 rclone.conf。

    .PARAMETER Value
        待替换的配置值。

    .PARAMETER Context
        当前值所在配置路径，用于错误提示。

    .OUTPUTS
        object。替换后的配置值；非字符串值原样返回。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    if ($Value -isnot [string]) {
        return $Value
    }

    Import-RcloneOpsConfigParser
    return Resolve-ConfigEnvPlaceholder -Value $Value -Context $Context
}

function Resolve-RcloneOpsFileSystemPath {
    <#
    .SYNOPSIS
        按配置文件上下文解析文件系统路径。

    .PARAMETER Path
        待解析路径，支持 `~`、环境变量占位符与相对路径。

    .PARAMETER BasePath
        相对路径解析基准目录。

    .PARAMETER Context
        当前路径所在配置位置，用于错误提示。

    .OUTPUTS
        System.String。解析后的绝对路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    Import-RcloneOpsConfigParser
    return Resolve-ConfigPath -Path $Path -BasePath $BasePath -Context $Context
}

function Resolve-RcloneOpsLocalPath {
    <#
    .SYNOPSIS
        将命令行路径解析成本地绝对路径。

    .PARAMETER Path
        命令行或默认路径，可为相对路径或绝对路径。

    .OUTPUTS
        System.String。基于当前工作目录解析后的绝对路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        Join-Path (Get-Location).Path $Path
    }
    return [System.IO.Path]::GetFullPath($resolvedPath)
}

function Get-RcloneOpsConfigDirectory {
    <#
    .SYNOPSIS
        获取 JSON 主配置所在目录。

    .PARAMETER ConfigPath
        JSON 主配置路径，可为相对路径或绝对路径。

    .OUTPUTS
        System.String。配置文件目录的绝对路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    return (Split-Path -Parent (Resolve-RcloneOpsLocalPath -Path $ConfigPath))
}

function ConvertTo-RcloneOpsBoolean {
    <#
    .SYNOPSIS
        将 JSON 配置值转换为布尔值。

    .PARAMETER Value
        JSON 配置中的布尔、数字或字符串值。

    .PARAMETER Context
        当前值所在配置位置，用于错误提示。

    .PARAMETER DefaultValue
        值缺失或为空字符串时使用的默认值。

    .OUTPUTS
        System.Boolean。解析后的布尔值。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Context,

        [Parameter(Mandatory = $true)]
        [bool]$DefaultValue
    )

    if ($null -eq $Value) {
        return $DefaultValue
    }
    if ($Value -is [bool]) {
        return [bool]$Value
    }

    $text = [string](Resolve-RcloneOpsEnvPlaceholder -Value $Value -Context $Context)
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $DefaultValue
    }

    switch ($text.Trim().ToLowerInvariant()) {
        { $_ -in @('1', 'true', 'yes', 'on') } { return $true }
        { $_ -in @('0', 'false', 'no', 'off') } { return $false }
        default { throw "$Context 需要布尔值，当前值为 '$text'。" }
    }
}

function ConvertTo-RcloneOpsSafeName {
    <#
    .SYNOPSIS
        将配置名称转换为适合文件名使用的安全片段。

    .PARAMETER Name
        mount profile、remote 或挂载点名称。

    .OUTPUTS
        System.String。仅包含字母、数字、点、下划线和短横线的名称。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $safeName = [regex]::Replace($Name, '[^A-Za-z0-9_.-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        throw "名称 '$Name' 无法转换为安全文件名。"
    }
    return $safeName
}

function Test-RcloneOpsMountPathOption {
    <#
    .SYNOPSIS
        判断 mount option 是否表示本地路径。

    .PARAMETER Name
        rclone mount option 名称，不包含 `--` 前缀。

    .OUTPUTS
        System.Boolean。需要按本地路径解析时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $Name -in @('cache-dir', 'log-file')
}

function Test-RcloneOpsMountPoint {
    <#
    .SYNOPSIS
        判断路径当前是否为系统挂载点。

    .PARAMETER Path
        需要检查的本地路径。

    .OUTPUTS
        System.Boolean。路径是挂载点时返回 true，否则返回 false。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    if ($IsMacOS) {
        & diskutil info $Path *> $null
        return $LASTEXITCODE -eq 0
    }

    if ($IsLinux -and (Get-Command 'findmnt' -ErrorAction SilentlyContinue)) {
        & findmnt --mountpoint $Path *> $null
        return $LASTEXITCODE -eq 0
    }

    $mountLines = if ($IsWindows) { @() } else { & mount 2>$null }
    foreach ($line in $mountLines) {
        if ($line -match '\son\s(.+?)\s\(' -and $Matches[1] -eq $Path) {
            return $true
        }
    }
    return $false
}

function New-RcloneOpsRemoteSection {
    <#
    .SYNOPSIS
        创建 rclone.conf 中单个 remote 的配置段。

    .PARAMETER Name
        remote 名称。

    .PARAMETER Settings
        remote 配置键值。

    .OUTPUTS
        System.String。rclone.conf 配置段文本。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )

    $preferredOrder = @(
        'type'
        'provider'
        'env_auth'
        'access_key_id'
        'secret_access_key'
        'endpoint'
        'region'
        'acl'
        'force_path_style'
        'no_check_bucket'
    )
    $orderedKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $preferredOrder) {
        if ($Settings.ContainsKey($key)) {
            $orderedKeys.Add($key)
        }
    }
    foreach ($key in ($Settings.Keys | Where-Object { $_ -notin $preferredOrder } | Sort-Object)) {
        $orderedKeys.Add([string]$key)
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("[$Name]")
    foreach ($key in $orderedKeys) {
        $value = [string]$Settings[$key]
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }
        $lines.Add("$key = $value")
    }
    return ($lines -join "`n")
}

function ConvertTo-RcloneOpsRemoteDefinitions {
    <#
    .SYNOPSIS
        将 JSON remotes 数组转换为 rclone remote 定义。

    .PARAMETER ConfigValues
        Read-RcloneOpsConfigValues 返回的配置键值。必须包含 `remotes` 数组。

    .OUTPUTS
        hashtable[]。每个元素包含 Name 与 Settings。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ConfigValues
    )

    if ($ConfigValues.ContainsKey('RCLONE_REMOTE_NAMES')) {
        throw '旧平铺格式已不支持；请改用 JSON remotes 数组。'
    }

    $remotesValue = Get-RcloneOpsConfigValue -Values $ConfigValues -Name 'remotes'
    if ($null -eq $remotesValue) {
        throw '配置缺少 remotes 数组，无法生成 rclone remote。'
    }

    $remoteItems = @($remotesValue)
    if ($remoteItems.Count -eq 0) {
        throw '配置 remotes 数组不能为空。'
    }

    $definitions = [System.Collections.Generic.List[hashtable]]::new()
    for ($index = 0; $index -lt $remoteItems.Count; $index++) {
        $remoteTable = ConvertTo-RcloneOpsHashtable -InputObject $remoteItems[$index]
        $remoteName = [string](Get-RcloneOpsConfigValue -Values $remoteTable -Name 'name')
        if ([string]::IsNullOrWhiteSpace($remoteName)) {
            throw "remotes[$index] 缺少 name。"
        }

        $settings = @{}
        foreach ($entry in $remoteTable.GetEnumerator()) {
            $key = [string]$entry.Key
            if ([string]::Equals($key, 'name', [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $settings[$key] = Resolve-RcloneOpsEnvPlaceholder -Value $entry.Value -Context "remotes[$index].$key"
        }

        if (-not $settings.ContainsKey('type') -or [string]::IsNullOrWhiteSpace([string]$settings['type'])) {
            throw "remote '$remoteName' 缺少 type。"
        }

        $definitions.Add(@{
                Name     = $remoteName
                Settings = $settings
            })
    }

    return [hashtable[]]$definitions.ToArray()
}

function ConvertTo-RcloneOpsConfig {
    <#
    .SYNOPSIS
        将 JSON remotes 配置转换为 rclone.conf 内容。

    .PARAMETER ConfigValues
        Read-RcloneOpsConfigValues 返回的配置键值。必须包含 `remotes` 数组。

    .OUTPUTS
        System.String。完整 rclone.conf 文本。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ConfigValues
    )

    $sections = [System.Collections.Generic.List[string]]::new()
    foreach ($definition in (ConvertTo-RcloneOpsRemoteDefinitions -ConfigValues $ConfigValues)) {
        $sections.Add((New-RcloneOpsRemoteSection -Name $definition.Name -Settings $definition.Settings))
    }

    return (($sections.ToArray() -join "`n`n") + "`n")
}

function ConvertTo-RcloneOpsMountDefinitions {
    <#
    .SYNOPSIS
        将 JSON mounts 数组转换为 mount profile 定义。

    .PARAMETER ConfigValues
        Read-RcloneOpsConfigValues 返回的配置键值。

    .PARAMETER BasePath
        本地路径解析基准目录，通常为 JSON 主配置所在目录。

    .OUTPUTS
        PSCustomObject[]。每个对象包含 Name、Remote、MountPoint、Options、PidFile 等字段。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ConfigValues,

        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $mountsValue = Get-RcloneOpsConfigValue -Values $ConfigValues -Name 'mounts'
    if ($null -eq $mountsValue) {
        return @()
    }

    $mountItems = @($mountsValue)
    $definitions = [System.Collections.Generic.List[pscustomobject]]::new()
    for ($index = 0; $index -lt $mountItems.Count; $index++) {
        $mountTable = ConvertTo-RcloneOpsHashtable -InputObject $mountItems[$index]
        $context = "mounts[$index]"
        $name = [string](Get-RcloneOpsConfigValue -Values $mountTable -Name 'name')
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "$context 缺少 name。"
        }

        $enabledValue = Get-RcloneOpsConfigValue -Values $mountTable -Name 'enabled'
        $enabled = ConvertTo-RcloneOpsBoolean -Value $enabledValue -Context "$context.enabled" -DefaultValue $true
        if (-not $enabled) {
            continue
        }

        $remote = [string](Resolve-RcloneOpsEnvPlaceholder -Value (Get-RcloneOpsConfigValue -Values $mountTable -Name 'remote') -Context "$context.remote")
        if ([string]::IsNullOrWhiteSpace($remote)) {
            throw "$context 缺少 remote。"
        }

        $mountPointValue = [string](Get-RcloneOpsConfigValue -Values $mountTable -Name 'mountPoint')
        if ([string]::IsNullOrWhiteSpace($mountPointValue)) {
            throw "$context 缺少 mountPoint。"
        }
        $mountPoint = Resolve-RcloneOpsFileSystemPath -Path $mountPointValue -BasePath $BasePath -Context "$context.mountPoint"

        $optionsValue = Get-RcloneOpsConfigValue -Values $mountTable -Name 'options'
        $options = if ($null -eq $optionsValue) { @{} } else { ConvertTo-RcloneOpsHashtable -InputObject $optionsValue }
        $safeName = ConvertTo-RcloneOpsSafeName -Name $name
        $defaultLogFile = Resolve-RcloneOpsFileSystemPath -Path ".runtime/logs/mount-$safeName.log" -BasePath $BasePath -Context "$context.options.log-file"
        $defaultCacheDir = Resolve-RcloneOpsFileSystemPath -Path ".runtime/cache/$safeName" -BasePath $BasePath -Context "$context.options.cache-dir"
        if (-not (Get-RcloneOpsConfigValue -Values $options -Name 'log-file')) {
            $options['log-file'] = $defaultLogFile
        }
        if (-not (Get-RcloneOpsConfigValue -Values $options -Name 'cache-dir')) {
            $options['cache-dir'] = $defaultCacheDir
        }

        $definitions.Add([PSCustomObject]@{
                Name       = $name
                SafeName   = $safeName
                Remote     = $remote
                MountPoint = $mountPoint
                Options    = $options
                PidFile    = (Join-Path $script:DefaultRuntimeDir "mounts/$safeName.pid")
            })
    }

    return [pscustomobject[]]$definitions.ToArray()
}

function New-RcloneOpsMountArguments {
    <#
    .SYNOPSIS
        根据 mount profile 创建 rclone mount 参数。

    .PARAMETER Definition
        ConvertTo-RcloneOpsMountDefinitions 返回的单个 mount profile。

    .PARAMETER ConfigPath
        rclone.conf 路径。

    .PARAMETER BasePath
        本地路径解析基准目录，通常为 JSON 主配置所在目录。

    .OUTPUTS
        System.String[]。传给 rclone 的参数数组。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add('mount')
    $arguments.Add([string]$Definition.Remote)
    $arguments.Add([string]$Definition.MountPoint)
    $arguments.Add("--config=$ConfigPath")

    $optionTable = ConvertTo-RcloneOpsHashtable -InputObject $Definition.Options
    foreach ($key in ($optionTable.Keys | Sort-Object)) {
        $name = [string]$key
        $value = $optionTable[$key]
        if ($null -eq $value) {
            continue
        }

        if ($value -is [bool]) {
            if ([bool]$value) {
                $arguments.Add("--$name")
            }
            continue
        }

        $resolvedValue = [string](Resolve-RcloneOpsEnvPlaceholder -Value $value -Context "mounts.$($Definition.Name).options.$name")
        if ([string]::IsNullOrWhiteSpace($resolvedValue)) {
            continue
        }
        if (Test-RcloneOpsMountPathOption -Name $name) {
            $resolvedValue = Resolve-RcloneOpsFileSystemPath -Path $resolvedValue -BasePath $BasePath -Context "mounts.$($Definition.Name).options.$name"
        }
        $arguments.Add("--$name=$resolvedValue")
    }

    return [string[]]$arguments.ToArray()
}

function New-RcloneOpsManualMountPidFile {
    <#
    .SYNOPSIS
        为手工后台 mount 生成独立 PID 文件路径。

    .PARAMETER Positionals
        mount 命令的位置参数，包含 remote 与 mount-point。

    .OUTPUTS
        System.String。PID 文件路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Positionals
    )

    $nameSource = if ($Positionals.Count -ge 2) { $Positionals[1] } elseif ($Positionals.Count -ge 1) { $Positionals[0] } else { 'manual' }
    $safeName = ConvertTo-RcloneOpsSafeName -Name $nameSource
    return (Join-Path $script:DefaultRuntimeDir "mounts/manual-$safeName.pid")
}

function Get-RcloneOpsRemoteName {
    <#
    .SYNOPSIS
        从 rclone.conf 文本读取 remote 名称。

    .PARAMETER Content
        rclone.conf 文本内容。

    .OUTPUTS
        System.String[]。remote 名称数组。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    [string[]]([regex]::Matches($Content, '(?m)^\[([^\]]+)\]\s*$') | ForEach-Object { $_.Groups[1].Value })
}

function Initialize-RcloneOpsConfig {
    <#
    .SYNOPSIS
        从 JSON 主配置生成本地 rclone.conf。

    .PARAMETER Flags
        命令行 flag 哈希表。

    .OUTPUTS
        None。生成配置文件并输出摘要。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Flags
    )

    $sourcePath = Get-RcloneOpsOption -Flags $Flags -Name 'source' -EnvName 'RCLONE_SOURCE_CONFIG_PATH' -DefaultValue $script:DefaultSourcePath
    $configPath = Get-RcloneOpsOption -Flags $Flags -Name 'config' -EnvName 'RCLONE_CONFIG_PATH' -DefaultValue $script:DefaultConfigPath
    if ((Test-Path -LiteralPath $configPath) -and -not $Flags.ContainsKey('overwrite')) {
        throw "配置已存在：$configPath。如需覆盖请追加 --overwrite。"
    }

    $values = Read-RcloneOpsConfigValues -ConfigPath $sourcePath
    $config = ConvertTo-RcloneOpsConfig -ConfigValues $values
    New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
    Set-Content -LiteralPath $configPath -Value $config -Encoding utf8NoBOM
    if (-not $IsWindows) {
        chmod 600 $configPath
    }
    Write-Host "已生成 $configPath，remote: $((Get-RcloneOpsRemoteName -Content $config) -join ', ')"
}

function Invoke-RcloneOpsDoctor {
    <#
    .SYNOPSIS
        检查 rclone 命令与本地配置状态。

    .PARAMETER Flags
        命令行 flag 哈希表。

    .OUTPUTS
        None。输出诊断信息。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Flags
    )

    $rclone = Get-RcloneOpsOption -Flags $Flags -Name 'rclone' -EnvName 'RCLONE_BIN' -DefaultValue 'rclone'
    $configPath = Get-RcloneOpsOption -Flags $Flags -Name 'config' -EnvName 'RCLONE_CONFIG_PATH' -DefaultValue $script:DefaultConfigPath
    $rcloneCommand = Get-Command $rclone -ErrorAction SilentlyContinue
    Write-Host ("rclone: {0} ({1})" -f ($(if ($rcloneCommand) { 'OK' } else { 'MISSING' }), $rclone))
    Write-Host ("config: {0} ({1})" -f ($(if (Test-Path -LiteralPath $configPath) { 'OK' } else { 'MISSING' }), $configPath))
    if (Test-Path -LiteralPath $configPath) {
        $names = Get-RcloneOpsRemoteName -Content (Get-Content -LiteralPath $configPath -Raw)
        Write-Host "remotes: $($names -join ', ')"
    }
}

function Invoke-RcloneOpsProcess {
    <#
    .SYNOPSIS
        执行或后台启动外部命令。

    .PARAMETER FilePath
        可执行文件路径或命令名。

    .PARAMETER Arguments
        命令参数数组。

    .PARAMETER Background
        是否后台启动。

    .PARAMETER PidFile
        后台进程 PID 文件路径。

    .PARAMETER FailureLogFile
        后台进程快速退出时读取的日志文件，用于输出真实失败原因。

    .OUTPUTS
        System.Int32。前台命令退出码；后台启动成功返回 0。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Arguments,

        [Parameter(Mandatory = $false)]
        [switch]$Background,

        [Parameter(Mandatory = $false)]
        [string]$PidFile,

        [Parameter(Mandatory = $false)]
        [string]$FailureLogFile
    )

    if ($Background) {
        if ($PidFile) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $PidFile) -Force | Out-Null
        }
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru
        Start-Sleep -Milliseconds 300
        if ($process.HasExited) {
            if ($PidFile -and (Test-Path -LiteralPath $PidFile)) {
                Remove-Item -LiteralPath $PidFile -Force
            }
            if ($FailureLogFile -and (Test-Path -LiteralPath $FailureLogFile)) {
                $lastLines = @(Get-Content -LiteralPath $FailureLogFile -Tail 12 -ErrorAction SilentlyContinue)
                if ($lastLines.Count -gt 0) {
                    Write-Warning "后台进程日志 $FailureLogFile：`n$($lastLines -join [Environment]::NewLine)"
                }
            }
            Write-Warning "后台进程启动后已退出：$FilePath，ExitCode=$($process.ExitCode)"
            return $process.ExitCode
        }

        if ($PidFile) {
            Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding utf8NoBOM
        }
        Write-Host "已后台启动 $FilePath，PID=$($process.Id)"
        return 0
    }

    & $FilePath @Arguments
    return $LASTEXITCODE
}

function Get-RcloneOpsServiceContext {
    <#
    .SYNOPSIS
        解析 rclone-ops 服务类命令的公共上下文。

    .PARAMETER Flags
        Split-RcloneOpsArguments 返回的 Flags 哈希表。

    .PARAMETER RequireSource
        是否要求 JSON 主配置必须存在。

    .OUTPUTS
        PSCustomObject。包含 SourcePath、SourceValues、SourceBasePath、ConfigPath 与 Rclone。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Flags,

        [Parameter(Mandatory = $false)]
        [switch]$RequireSource
    )

    $sourcePath = Get-RcloneOpsOption -Flags $Flags -Name 'source' -EnvName 'RCLONE_SOURCE_CONFIG_PATH' -DefaultValue $script:DefaultSourcePath
    $sourceValues = if ($RequireSource) {
        Read-RcloneOpsConfigValues -ConfigPath $sourcePath
    }
    else {
        Get-RcloneOpsOptionalConfigValues -ConfigPath $sourcePath
    }

    [PSCustomObject]@{
        SourcePath     = $sourcePath
        SourceValues   = $sourceValues
        SourceBasePath = Get-RcloneOpsConfigDirectory -ConfigPath $sourcePath
        Rclone         = Get-RcloneOpsOption -Flags $Flags -Name 'rclone' -EnvName 'RCLONE_BIN' -DefaultValue 'rclone'
        ConfigPath     = Get-RcloneOpsOption -Flags $Flags -Name 'config' -EnvName 'RCLONE_CONFIG_PATH' -DefaultValue $script:DefaultConfigPath
    }
}

function Start-RcloneOpsWebUi {
    <#
    .SYNOPSIS
        启动 rclone RC/WebUI。

    .PARAMETER Flags
        命令行 flag 哈希表。

    .PARAMETER Passthrough
        透传给 rclone 的额外参数。

    .OUTPUTS
        System.Int32。rclone 退出码。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Flags,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Passthrough
    )

    $context = Get-RcloneOpsServiceContext -Flags $Flags
    $rcAddr = Get-RcloneOpsOptionWithConfig -Flags $Flags -Name 'addr' -EnvName 'RCLONE_RC_ADDR' -ConfigValues $context.SourceValues -Section 'webui' -ConfigName 'addr' -DefaultValue $script:DefaultRcAddr
    $rcPass = Get-RcloneOpsOptionWithConfig -Flags $Flags -Name 'pass' -EnvName 'RCLONE_RC_PASS' -ConfigValues $context.SourceValues -Section 'webui' -ConfigName 'pass' -DefaultValue ''
    $rcUser = if ($rcPass) { Get-RcloneOpsOptionWithConfig -Flags $Flags -Name 'user' -EnvName 'RCLONE_RC_USER' -ConfigValues $context.SourceValues -Section 'webui' -ConfigName 'user' -DefaultValue $script:DefaultRcUser } else { '' }
    $isBackground = $Flags.ContainsKey('background')
    $logFile = Get-RcloneOpsWebUiLogFile -Flags $Flags -ConfigValues $context.SourceValues -BasePath $context.SourceBasePath
    if ($isBackground) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $logFile) -Force | Out-Null
    }

    if (-not (Get-Command $context.Rclone -ErrorAction SilentlyContinue)) {
        throw "未找到 rclone 命令：$($context.Rclone)。请先安装 rclone，或通过 --rclone / RCLONE_BIN 指定路径。"
    }

    # 前台模式保留 rclone 的 stderr/stdout，后台模式才写日志文件，避免用户误判“没反应”。
    $rcloneArgs = @('rcd', '--rc-web-gui', "--rc-addr=$rcAddr", "--config=$($context.ConfigPath)")
    if ($isBackground) { $rcloneArgs += "--log-file=$logFile" }
    if ($rcPass) { $rcloneArgs += @("--rc-user=$rcUser", "--rc-pass=$rcPass") }
    if ($Flags.ContainsKey('no-open-browser')) { $rcloneArgs += '--rc-web-gui-no-open-browser' }
    $rcloneArgs += $Passthrough

    Write-Host '准备启动 rclone WebUI/RC：'
    Write-Host "  地址: http://$rcAddr"
    Write-Host "  配置: $($context.ConfigPath)"
    Write-Host ("  日志: {0}" -f ($(if ($isBackground) { $logFile } else { '当前终端（rclone stdout/stderr）' })))
    if (-not $rcPass) {
        Write-Host '  认证: 未设置 RCLONE_RC_PASS，rclone 会生成临时认证信息；建议日常运维显式设置强密码。'
    }
    if ($isBackground) {
        Write-Host '  模式: 后台启动，可用 stop-webui 停止。'
    }
    else {
        Write-Host '  模式: 前台运行，rclone 日志会直接显示在当前终端，按 Ctrl+C 停止。'
        Write-Host '  提示: 如需命令立即返回，请使用 --background --no-open-browser。'
    }

    $failureLogFile = if ($isBackground) { $logFile } else { $null }
    Invoke-RcloneOpsProcess -FilePath $context.Rclone -Arguments $rcloneArgs -Background:$isBackground -PidFile (Join-Path $script:DefaultRuntimeDir 'webui.pid') -FailureLogFile $failureLogFile
}

function Stop-RcloneOpsWebUi {
    <#
    .SYNOPSIS
        停止后台启动的 WebUI。

    .OUTPUTS
        None。发送停止信号并输出结果。
    #>
    [CmdletBinding()]
    param()

    $pidFile = Join-Path $script:DefaultRuntimeDir 'webui.pid'
    if (-not (Test-Path -LiteralPath $pidFile)) {
        Write-Host '未找到 WebUI PID 文件。'
        return
    }
    $processId = [int](Get-Content -LiteralPath $pidFile -Raw)
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        Remove-Item -LiteralPath $pidFile -Force
        Write-Host "WebUI PID 文件已过期，已清理：$processId"
        return
    }

    Stop-Process -Id $processId -ErrorAction Stop
    Remove-Item -LiteralPath $pidFile -Force
    Write-Host "已停止 WebUI 进程：$processId"
}

function Start-RcloneOpsConfiguredMounts {
    <#
    .SYNOPSIS
        启动 JSON 主配置中的所有 enabled mount profile。

    .PARAMETER Flags
        Split-RcloneOpsArguments 返回的 Flags 哈希表。

    .OUTPUTS
        System.Int32。所有挂载启动成功返回 0，否则返回 1。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Flags
    )

    $context = Get-RcloneOpsServiceContext -Flags $Flags -RequireSource
    $definitions = @(ConvertTo-RcloneOpsMountDefinitions -ConfigValues $context.SourceValues -BasePath $context.SourceBasePath)
    if ($definitions.Count -eq 0) {
        Write-Host '未找到 enabled mounts，跳过挂载。'
        return 0
    }
    if (-not (Get-Command $context.Rclone -ErrorAction SilentlyContinue)) {
        throw "未找到 rclone 命令：$($context.Rclone)。请先安装 rclone，或通过 --rclone / RCLONE_BIN 指定路径。"
    }

    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($definition in $definitions) {
        New-Item -ItemType Directory -Path $definition.MountPoint -Force | Out-Null
        $arguments = New-RcloneOpsMountArguments -Definition $definition -ConfigPath $context.ConfigPath -BasePath $context.SourceBasePath
        foreach ($argument in $arguments) {
            if ($argument -like '--cache-dir=*') {
                $targetPath = $argument.Substring($argument.IndexOf('=') + 1)
                New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            }
            elseif ($argument -like '--log-file=*') {
                $targetPath = $argument.Substring($argument.IndexOf('=') + 1)
                New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
            }
        }

        Write-Host "准备挂载 $($definition.Name)：$($definition.Remote) -> $($definition.MountPoint)"
        $failureLogFile = $null
        foreach ($argument in $arguments) {
            if ($argument -like '--log-file=*') {
                $failureLogFile = $argument.Substring($argument.IndexOf('=') + 1)
                break
            }
        }

        $exitCode = Invoke-RcloneOpsProcess -FilePath $context.Rclone -Arguments $arguments -Background -PidFile $definition.PidFile -FailureLogFile $failureLogFile
        if ($exitCode -ne 0) {
            $failed.Add($definition.Name)
        }
    }

    if ($failed.Count -gt 0) {
        Write-Error "以下挂载启动失败：$($failed -join ', ')"
        return 1
    }
    return 0
}

function Stop-RcloneOpsConfiguredMounts {
    <#
    .SYNOPSIS
        卸载 JSON 主配置中的所有 enabled mount profile。

    .PARAMETER Flags
        Split-RcloneOpsArguments 返回的 Flags 哈希表。

    .OUTPUTS
        System.Int32。所有卸载命令成功返回 0，否则返回 1。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Flags
    )

    $context = Get-RcloneOpsServiceContext -Flags $Flags -RequireSource
    $definitions = @(ConvertTo-RcloneOpsMountDefinitions -ConfigValues $context.SourceValues -BasePath $context.SourceBasePath)
    if ($definitions.Count -eq 0) {
        Write-Host '未找到 enabled mounts，跳过卸载。'
        return 0
    }

    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($definition in ([array]$definitions)[($definitions.Count - 1)..0]) {
        Write-Host "准备卸载 $($definition.Name)：$($definition.MountPoint)"
        if (-not (Test-RcloneOpsMountPoint -Path $definition.MountPoint)) {
            Write-Host "  跳过：当前路径不是挂载点。"
            if (Test-Path -LiteralPath $definition.PidFile) {
                Remove-Item -LiteralPath $definition.PidFile -Force
            }
            continue
        }

        $exitCode = Dismount-RcloneOpsMount -Positionals @($definition.MountPoint)
        if ($exitCode -ne 0) {
            $failed.Add($definition.Name)
            continue
        }
        if (Test-Path -LiteralPath $definition.PidFile) {
            Remove-Item -LiteralPath $definition.PidFile -Force
        }
    }

    if ($failed.Count -gt 0) {
        Write-Error "以下挂载卸载失败：$($failed -join ', ')"
        return 1
    }
    return 0
}

function Start-RcloneOpsStack {
    <#
    .SYNOPSIS
        启动 rclone WebUI 并自动挂载配置中的 OSS/S3 remote。

    .PARAMETER Flags
        Split-RcloneOpsArguments 返回的 Flags 哈希表。

    .OUTPUTS
        System.Int32。启动成功返回 0，否则返回非 0。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Flags
    )

    $context = Get-RcloneOpsServiceContext -Flags $Flags -RequireSource
    $initFlags = @{}
    foreach ($entry in $Flags.GetEnumerator()) {
        $initFlags[$entry.Key] = $entry.Value
    }
    $initFlags['overwrite'] = $true
    Write-Host "从 $($context.SourcePath) 刷新 rclone.conf。"
    Initialize-RcloneOpsConfig -Flags $initFlags

    $webUiFlags = @{} + $Flags
    $webUiFlags['background'] = $true
    $webUiFlags['no-open-browser'] = $true
    $webUiExitCode = Start-RcloneOpsWebUi -Flags $webUiFlags -Passthrough @()
    if ($webUiExitCode -ne 0) {
        return $webUiExitCode
    }

    return Start-RcloneOpsConfiguredMounts -Flags $Flags
}

function Stop-RcloneOpsStack {
    <#
    .SYNOPSIS
        卸载配置中的 mounts 并停止后台 WebUI。

    .PARAMETER Flags
        Split-RcloneOpsArguments 返回的 Flags 哈希表。

    .OUTPUTS
        System.Int32。停止流程成功返回 0，否则返回非 0。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Flags
    )

    $mountExitCode = Stop-RcloneOpsConfiguredMounts -Flags $Flags
    Stop-RcloneOpsWebUi
    return $mountExitCode
}

function Invoke-RcloneOpsTransfer {
    <#
    .SYNOPSIS
        执行 copy、sync、check 等双端 rclone 命令。

    .PARAMETER Action
        rclone 子命令。

    .PARAMETER ParsedArgs
        Split-RcloneOpsArguments 返回的对象。

    .OUTPUTS
        System.Int32。rclone 退出码。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('copy', 'sync', 'check')]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$ParsedArgs
    )

    if ($ParsedArgs.Positionals.Count -lt 2) {
        throw "$Action 需要 <source> <dest> 两个参数。"
    }
    $rclone = Get-RcloneOpsOption -Flags $ParsedArgs.Flags -Name 'rclone' -EnvName 'RCLONE_BIN' -DefaultValue 'rclone'
    $configPath = Get-RcloneOpsOption -Flags $ParsedArgs.Flags -Name 'config' -EnvName 'RCLONE_CONFIG_PATH' -DefaultValue $script:DefaultConfigPath
    $safetyArgs = @()
    if ($Action -eq 'sync' -and -not $ParsedArgs.Flags.ContainsKey('run')) {
        Write-Host '安全默认：sync 当前为 dry-run；确认无误后追加 --run 才会真实执行。'
        $safetyArgs += '--dry-run'
    }
    Invoke-RcloneOpsProcess -FilePath $rclone -Arguments @($Action, $ParsedArgs.Positionals[0], $ParsedArgs.Positionals[1], "--config=$configPath") + $safetyArgs + $ParsedArgs.Passthrough
}

function Invoke-RcloneOpsGeneric {
    <#
    .SYNOPSIS
        执行 ls、lsd、mount、serve 等通用 rclone 命令。

    .PARAMETER Action
        rclone 子命令。

    .PARAMETER ParsedArgs
        Split-RcloneOpsArguments 返回的对象。

    .OUTPUTS
        System.Int32。rclone 退出码。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ls', 'lsd', 'mount', 'serve')]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$ParsedArgs
    )

    $rclone = Get-RcloneOpsOption -Flags $ParsedArgs.Flags -Name 'rclone' -EnvName 'RCLONE_BIN' -DefaultValue 'rclone'
    $configPath = Get-RcloneOpsOption -Flags $ParsedArgs.Flags -Name 'config' -EnvName 'RCLONE_CONFIG_PATH' -DefaultValue $script:DefaultConfigPath
    $pidFile = if ($Action -eq 'mount') {
        New-RcloneOpsManualMountPidFile -Positionals $ParsedArgs.Positionals
    }
    else {
        Join-Path $script:DefaultRuntimeDir "$Action.pid"
    }
    Invoke-RcloneOpsProcess -FilePath $rclone -Arguments @($Action) + $ParsedArgs.Positionals + @("--config=$configPath") + $ParsedArgs.Passthrough -Background:($ParsedArgs.Flags.ContainsKey('background')) -PidFile $pidFile
}

function Dismount-RcloneOpsMount {
    <#
    .SYNOPSIS
        卸载本地挂载点。

    .PARAMETER Positionals
        位置参数，第一项为挂载点。

    .OUTPUTS
        System.Int32。卸载命令退出码。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Positionals
    )

    if ($Positionals.Count -lt 1) { throw 'unmount 需要 <mount-point> 参数。' }
    if (-not (Test-RcloneOpsMountPoint -Path $Positionals[0])) {
        Write-Host "当前路径不是挂载点，跳过卸载：$($Positionals[0])"
        return 0
    }

    if ($IsMacOS) { return Invoke-RcloneOpsProcess -FilePath 'diskutil' -Arguments @('unmount', $Positionals[0]) }
    if ($IsLinux) { return Invoke-RcloneOpsProcess -FilePath 'fusermount' -Arguments @('-u', $Positionals[0]) }
    return Invoke-RcloneOpsProcess -FilePath 'umount' -Arguments @($Positionals[0])
}

function Show-RcloneOpsHelp {
    <#
    .SYNOPSIS
        输出 CLI 帮助信息。

    .OUTPUTS
        None。向控制台写入帮助文本。
    #>
    [CmdletBinding()]
    param()

    @"
rclone 通用运维脚本（PowerShell）

用法：
  pwsh ./rclone-ops.ps1 init-config [--overwrite] [--source rclone.config.local.json] [--config rclone.conf]
  pwsh ./rclone-ops.ps1 doctor [--config rclone.conf]
  pwsh ./rclone-ops.ps1 up [--source rclone.config.local.json] [--config rclone.conf]
  pwsh ./rclone-ops.ps1 down [--source rclone.config.local.json]
  pwsh ./rclone-ops.ps1 webui [--background] [--addr 127.0.0.1:5572] [--user admin] [--pass ***] [--no-open-browser]
  pwsh ./rclone-ops.ps1 stop-webui
  pwsh ./rclone-ops.ps1 mount-all [--source rclone.config.local.json] [--config rclone.conf]
  pwsh ./rclone-ops.ps1 unmount-all [--source rclone.config.local.json]
  pwsh ./rclone-ops.ps1 lsd <remote:>
  pwsh ./rclone-ops.ps1 ls <remote:path>
  pwsh ./rclone-ops.ps1 mount <remote:path> <mount-point> [--background] -- [额外 rclone 参数]
  pwsh ./rclone-ops.ps1 unmount <mount-point>
  pwsh ./rclone-ops.ps1 copy <source> <dest> -- [额外 rclone 参数]
  pwsh ./rclone-ops.ps1 sync <source> <dest> [--run] -- [额外 rclone 参数]
  pwsh ./rclone-ops.ps1 check <source> <dest> -- [额外 rclone 参数]

安全默认：
  - sync 默认追加 --dry-run，只有显式传入 --run 才真实执行。
  - WebUI 默认监听 $script:DefaultRcAddr；未设置 RCLONE_RC_PASS 时由 rclone WebUI 自动生成临时认证信息。
  - rclone.conf 由 init-config 本地生成，默认不应提交到 Git。
"@ | Write-Host
}

function Invoke-RcloneOpsMain {
    <#
    .SYNOPSIS
        rclone-ops.ps1 主调度入口。

    .PARAMETER Command
        子命令名称。

    .PARAMETER ArgumentList
        子命令参数。

    .OUTPUTS
        System.Int32。命令退出码。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ArgumentList
    )

    $parsed = Split-RcloneOpsArguments -ArgumentList $ArgumentList
    switch ($Command) {
        { $_ -in @('help', '--help', '-h') } { Show-RcloneOpsHelp; return 0 }
        'init-config' { Initialize-RcloneOpsConfig -Flags $parsed.Flags; return 0 }
        'doctor' { Invoke-RcloneOpsDoctor -Flags $parsed.Flags; return 0 }
        'up' { return Start-RcloneOpsStack -Flags $parsed.Flags }
        'down' { return Stop-RcloneOpsStack -Flags $parsed.Flags }
        'webui' { return Start-RcloneOpsWebUi -Flags $parsed.Flags -Passthrough $parsed.Passthrough }
        'stop-webui' { Stop-RcloneOpsWebUi; return 0 }
        'mount-all' { return Start-RcloneOpsConfiguredMounts -Flags $parsed.Flags }
        'unmount-all' { return Stop-RcloneOpsConfiguredMounts -Flags $parsed.Flags }
        { $_ -in @('copy', 'sync', 'check') } { return Invoke-RcloneOpsTransfer -Action $Command -ParsedArgs $parsed }
        { $_ -in @('ls', 'lsd', 'mount', 'serve') } { return Invoke-RcloneOpsGeneric -Action $Command -ParsedArgs $parsed }
        'unmount' { return Dismount-RcloneOpsMount -Positionals $parsed.Positionals }
        default { throw "未知命令：$Command。执行 pwsh ./rclone-ops.ps1 help 查看用法。" }
    }
}

if ($env:RCLONE_OPS_SKIP_MAIN -ne '1') {
    try {
        exit (Invoke-RcloneOpsMain -Command $Command -ArgumentList $ArgumentList)
    }
    catch {
        Write-Error $_
        exit 1
    }
}
