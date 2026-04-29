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

    foreach ($entry in $Values.GetEnumerator()) {
        if ([string]::Equals([string]$entry.Key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $entry.Value
        }
    }

    return $null
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

    $pattern = '\$\{([A-Za-z_][A-Za-z0-9_]*)\}'
    foreach ($match in [regex]::Matches($Value, $pattern)) {
        $envName = $match.Groups[1].Value
        if ($null -eq [Environment]::GetEnvironmentVariable($envName, 'Process')) {
            throw "环境变量未设置: $envName（$Context）"
        }
    }

    return [regex]::Replace($Value, $pattern, {
            param($Match)
            $envName = $Match.Groups[1].Value
            return [Environment]::GetEnvironmentVariable($envName, 'Process')
        })
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
        [string]$PidFile
    )

    if ($Background) {
        if ($PidFile) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $PidFile) -Force | Out-Null
        }
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru
        if ($PidFile) {
            Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding utf8NoBOM
        }
        Write-Host "已后台启动 $FilePath，PID=$($process.Id)"
        return 0
    }

    & $FilePath @Arguments
    return $LASTEXITCODE
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

    $sourcePath = Get-RcloneOpsOption -Flags $Flags -Name 'source' -EnvName 'RCLONE_SOURCE_CONFIG_PATH' -DefaultValue $script:DefaultSourcePath
    $sourceValues = Get-RcloneOpsOptionalConfigValues -ConfigPath $sourcePath
    $rclone = Get-RcloneOpsOption -Flags $Flags -Name 'rclone' -EnvName 'RCLONE_BIN' -DefaultValue 'rclone'
    $configPath = Get-RcloneOpsOption -Flags $Flags -Name 'config' -EnvName 'RCLONE_CONFIG_PATH' -DefaultValue $script:DefaultConfigPath
    $rcAddr = Get-RcloneOpsOptionWithConfig -Flags $Flags -Name 'addr' -EnvName 'RCLONE_RC_ADDR' -ConfigValues $sourceValues -Section 'webui' -ConfigName 'addr' -DefaultValue $script:DefaultRcAddr
    $rcPass = Get-RcloneOpsOptionWithConfig -Flags $Flags -Name 'pass' -EnvName 'RCLONE_RC_PASS' -ConfigValues $sourceValues -Section 'webui' -ConfigName 'pass' -DefaultValue ''
    $rcUser = if ($rcPass) { Get-RcloneOpsOptionWithConfig -Flags $Flags -Name 'user' -EnvName 'RCLONE_RC_USER' -ConfigValues $sourceValues -Section 'webui' -ConfigName 'user' -DefaultValue $script:DefaultRcUser } else { '' }
    $isBackground = $Flags.ContainsKey('background')
    $logFile = Get-RcloneOpsOption -Flags $Flags -Name 'log-file' -EnvName 'RCLONE_LOG_FILE' -DefaultValue (Join-Path $script:DefaultLogDir 'webui.log')
    if ($isBackground) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $logFile) -Force | Out-Null
    }

    if (-not (Get-Command $rclone -ErrorAction SilentlyContinue)) {
        throw "未找到 rclone 命令：$rclone。请先安装 rclone，或通过 --rclone / RCLONE_BIN 指定路径。"
    }

    # 前台模式保留 rclone 的 stderr/stdout，后台模式才写日志文件，避免用户误判“没反应”。
    $rcloneArgs = @('rcd', '--rc-web-gui', "--rc-addr=$rcAddr", "--config=$configPath")
    if ($isBackground) { $rcloneArgs += "--log-file=$logFile" }
    if ($rcPass) { $rcloneArgs += @("--rc-user=$rcUser", "--rc-pass=$rcPass") }
    if ($Flags.ContainsKey('no-open-browser')) { $rcloneArgs += '--rc-web-gui-no-open-browser' }
    $rcloneArgs += $Passthrough

    Write-Host '准备启动 rclone WebUI/RC：'
    Write-Host "  地址: http://$rcAddr"
    Write-Host "  配置: $configPath"
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

    Invoke-RcloneOpsProcess -FilePath $rclone -Arguments $rcloneArgs -Background:$isBackground -PidFile (Join-Path $script:DefaultRuntimeDir 'webui.pid')
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
    Stop-Process -Id $processId -ErrorAction Stop
    Write-Host "已停止 WebUI 进程：$processId"
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
    Invoke-RcloneOpsProcess -FilePath $rclone -Arguments @($Action) + $ParsedArgs.Positionals + @("--config=$configPath") + $ParsedArgs.Passthrough -Background:($ParsedArgs.Flags.ContainsKey('background')) -PidFile (Join-Path $script:DefaultRuntimeDir "$Action.pid")
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
  pwsh ./rclone-ops.ps1 webui [--background] [--addr 127.0.0.1:5572] [--user admin] [--pass ***] [--no-open-browser]
  pwsh ./rclone-ops.ps1 stop-webui
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
        'webui' { return Start-RcloneOpsWebUi -Flags $parsed.Flags -Passthrough $parsed.Passthrough }
        'stop-webui' { Stop-RcloneOpsWebUi; return 0 }
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
