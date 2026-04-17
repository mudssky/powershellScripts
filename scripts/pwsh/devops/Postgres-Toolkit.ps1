#!/usr/bin/env pwsh
<#
.SYNOPSIS
    PostgreSQL 常用备份、恢复、CSV 导入与工具安装命令行工具。

.DESCRIPTION
    单文件分发产物，内嵌 PostgreSQL Toolkit 的核心 helper、命令翻译和帮助输出。

.PARAMETER CommandName
    要执行的子命令名称，例如 `backup`、`restore`、`import-csv`、`install-tools`。

.PARAMETER RawArguments
    透传给子命令解析器的剩余参数数组。
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$CommandName,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RawArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# region shared-config
function Read-ConfigEnvFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $pairs = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
            continue
        }

        if ($line -notmatch '^\s*([^=]+)=(.*)$') {
            throw '无效 env 行'
        }

        $pairs[$Matches[1].Trim()] = $Matches[2].Trim()
    }

    return $pairs
}
# endregion shared-config

# region shared-config
function Get-ConfigSourceDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Source,

        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $sourcePath = if ($Source.ContainsKey('Path')) { [string]$Source['Path'] } else { '' }
    $sourceName = if ($Source.ContainsKey('Name')) { [string]$Source['Name'] } else { '' }
    $sourceData = if ($Source.ContainsKey('Data')) { $Source['Data'] } else { $null }

    if (-not [string]::IsNullOrWhiteSpace($sourcePath) -and -not [System.IO.Path]::IsPathRooted($sourcePath)) {
        $resolvedPath = Join-Path $BasePath $sourcePath
    }
    else {
        $resolvedPath = $sourcePath
    }

    $type = [string]$Source.Type
    $name = if ([string]::IsNullOrWhiteSpace($sourceName)) {
        if ($type -eq 'ProcessEnv') {
            'ProcessEnv'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($resolvedPath)) {
            [System.IO.Path]::GetFileName($resolvedPath)
        }
        else {
            $type
        }
    }
    else {
        [string]$Source.Name
    }

    return @{
        Type = $type
        Name = $name
        Path = $resolvedPath
        Data = $sourceData
    }
}
# endregion shared-config

# region shared-config
function ConvertTo-ConfigHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return @{}
    }

    if ($InputObject -is [hashtable]) {
        return @{} + $InputObject
    }

    $result = @{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }

    return $result
}
# endregion shared-config

# region shared-config
function Read-ConfigSourceValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Source,

        [switch]$ErrorOnMissing
    )

    switch ($Source.Type) {
        'Hashtable' {
            return ConvertTo-ConfigHashtable -InputObject $Source.Data
        }
        'ProcessEnv' {
            $values = @{}
            Get-ChildItem Env: | ForEach-Object {
                $values[$_.Name] = $_.Value
            }

            return $values
        }
        'EnvFile' {
            if (-not (Test-Path -LiteralPath $Source.Path)) {
                if ($ErrorOnMissing) {
                    throw "配置文件不存在: $($Source.Path)"
                }

                return @{}
            }

            return Read-ConfigEnvFile -Path $Source.Path
        }
        'JsonFile' {
            if (-not (Test-Path -LiteralPath $Source.Path)) {
                if ($ErrorOnMissing) {
                    throw "配置文件不存在: $($Source.Path)"
                }

                return @{}
            }

            $rawObject = Get-Content -LiteralPath $Source.Path -Raw | ConvertFrom-Json
            return ConvertTo-ConfigHashtable -InputObject $rawObject
        }
        default {
            throw "不支持的配置来源类型: $($Source.Type)"
        }
    }
}
# endregion shared-config

# region shared-config
function Resolve-DefaultEnvFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PrimaryBasePath,

        [string]$FallbackBasePath
    )

    $candidateBases = @($PrimaryBasePath)
    if (-not [string]::IsNullOrWhiteSpace($FallbackBasePath)) {
        $candidateBases += $FallbackBasePath
    }

    foreach ($basePath in $candidateBases) {
        if ([string]::IsNullOrWhiteSpace($basePath) -or -not (Test-Path -LiteralPath $basePath -PathType Container)) {
            continue
        }

        $paths = New-Object 'System.Collections.Generic.List[string]'
        foreach ($fileName in @('.env', '.env.local')) {
            $candidatePath = Join-Path $basePath $fileName
            if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
                $paths.Add($candidatePath) | Out-Null
            }
        }

        if ($paths.Count -gt 0) {
            return [pscustomobject]@{
                BasePath = $basePath
                Paths    = @($paths)
            }
        }
    }

    return [pscustomobject]@{
        BasePath = $null
        Paths    = @()
    }
}
# endregion shared-config

# region shared-config
function Resolve-ConfigSources {
    [CmdletBinding()]
    param(
        [string[]]$ConfigFile,
        [hashtable[]]$Sources,
        [string]$BasePath = (Get-Location).Path,
        [switch]$IncludeTrace,
        [switch]$ErrorOnMissing
    )

    $resolvedSources = @()

    if ($PSBoundParameters.ContainsKey('Sources') -and $Sources.Count -gt 0) {
        foreach ($source in $Sources) {
            $resolvedSources += Get-ConfigSourceDescriptor -Source $source -BasePath $BasePath
        }
    }
    else {
        $fileList = if ($PSBoundParameters.ContainsKey('ConfigFile') -and $ConfigFile.Count -gt 0) {
            $ConfigFile
        }
        else {
            (Resolve-DefaultEnvFiles -PrimaryBasePath $BasePath).Paths
        }

        foreach ($path in $fileList) {
            $sourceType = if ($path -match '\.json$') { 'JsonFile' } else { 'EnvFile' }
            $resolvedSources += Get-ConfigSourceDescriptor -Source @{
                Type = $sourceType
                Path = $path
            } -BasePath $BasePath
        }
    }

    $values = @{}
    $sourcesMap = @{}
    $trace = @{}

    foreach ($source in $resolvedSources) {
        $sourceValues = Read-ConfigSourceValues -Source $source -ErrorOnMissing:$ErrorOnMissing
        foreach ($entry in $sourceValues.GetEnumerator()) {
            $values[$entry.Key] = $entry.Value
            $sourcesMap[$entry.Key] = $source.Name

            if ($IncludeTrace) {
                if (-not $trace.ContainsKey($entry.Key)) {
                    $trace[$entry.Key] = [pscustomobject]@{
                        Candidates = New-Object 'System.Collections.Generic.List[object]'
                    }
                }

                $trace[$entry.Key].Candidates.Add([pscustomobject]@{
                    Source = $source.Name
                    Value  = $entry.Value
                })
            }
        }
    }

    return [pscustomobject]@{
        Values  = $values
        Sources = $sourcesMap
        Trace   = $trace
    }
}
# endregion shared-config

# region core/logging.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    统一输出 PostgreSQL Toolkit 的控制台消息。

.DESCRIPTION
    为脚本内部提供统一的日志前缀，便于后续区分信息、警告和错误消息。

.PARAMETER Level
    日志级别，仅支持 `info`、`warn`、`error`。

.PARAMETER Message
    要输出的消息文本。
#>
function Write-PostgresToolkitMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('info', 'warn', 'error')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $rendered = "[postgres-toolkit][$Level] $Message"
    switch ($Level) {
        'warn' { Write-Warning $rendered }
        'error' { Write-Error $rendered }
        default { Write-Host $rendered }
    }
}

# endregion core/logging.ps1

# region core/process.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    生成 native command 的预览文本。

.DESCRIPTION
    将命令名和参数数组渲染为一行字符串，供 `--dry-run` 输出使用。

.PARAMETER Spec
    由 `New-PgNativeCommandSpec` 生成的命令描述对象。

.OUTPUTS
    string
    返回可直接展示给用户的命令预览文本。
#>
function Format-PgNativeCommandPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Spec
    )

    $arguments = $Spec.ArgumentList -join ' '
    return ("{0} {1}" -f $Spec.FilePath, $arguments).Trim()
}

<#
.SYNOPSIS
    创建统一的原生命令描述对象。

.DESCRIPTION
    把命令路径、参数列表和需要注入的环境变量统一封装，方便 dry-run 与真实执行共享。

.PARAMETER FilePath
    要执行的命令名或完整路径。

.PARAMETER ArgumentList
    传递给命令的参数数组。

.PARAMETER Environment
    进程级环境变量覆盖值，例如 `PGPASSWORD`。

.OUTPUTS
    PSCustomObject
    返回包含 `FilePath`、`ArgumentList`、`Environment` 的命令描述对象。
#>
function New-PgNativeCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [AllowNull()]
        [hashtable]$Environment
    )

    return [PSCustomObject]@{
        FilePath     = $FilePath
        ArgumentList = $ArgumentList
        Environment  = if ($null -eq $Environment) { @{} } else { $Environment }
    }
}

<#
.SYNOPSIS
    以 dry-run 或真实执行方式运行 PostgreSQL 原生命令。

.DESCRIPTION
    `--dry-run` 场景只返回命令预览；真实执行场景会临时注入环境变量后调用目标命令，
    并在结束后恢复进程环境，避免把敏感变量泄露给后续步骤。

.PARAMETER Spec
    由 `New-PgNativeCommandSpec` 生成的命令描述对象。

.PARAMETER DryRun
    是否仅输出命令预览而不真正执行。

.OUTPUTS
    PSCustomObject
    返回包含 `ExitCode` 与 `Output` 的结果对象。
#>
function Invoke-PgNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Spec,

        [switch]$DryRun
    )

    if ($DryRun) {
        return [PSCustomObject]@{
            ExitCode = 0
            Output   = Format-PgNativeCommandPreview -Spec $Spec
        }
    }

    $previousValues = @{}
    foreach ($entry in $Spec.Environment.GetEnumerator()) {
        $previousValues[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }

    try {
        $argumentList = @($Spec.ArgumentList)
        $output = @(& $Spec.FilePath @argumentList)
        return [PSCustomObject]@{
            ExitCode = $LASTEXITCODE
            Output   = ($output -join [Environment]::NewLine)
        }
    }
    finally {
        foreach ($entry in $previousValues.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
        }
    }
}

# endregion core/process.ps1

# region core/arguments.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    解析 GNU 风格的长参数列表。

.DESCRIPTION
    把 `--flag value`、`--flag=value` 和单独布尔开关转换为 hashtable，
    统一后续子命令读取参数的方式。

.PARAMETER Arguments
    从 CLI 入口透传进来的剩余参数数组。

.OUTPUTS
    hashtable
    返回键名转为下划线风格的参数表，例如 `--env-file` 会变成 `env_file`。
#>
function ConvertFrom-LongOptionList {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$Arguments
    )

    if ($null -eq $Arguments -or $Arguments.Count -eq 0) {
        return @{}
    }

    $result = @{}
    $index = 0

    while ($index -lt $Arguments.Count) {
        $token = $Arguments[$index]
        if (-not $token.StartsWith('--')) {
            throw "仅支持 GNU 风格长参数，收到: $token"
        }

        $trimmed = $token.Substring(2)
        if ($trimmed.Contains('=')) {
            $parts = $trimmed.Split('=', 2)
            $result[$parts[0].Replace('-', '_')] = $parts[1]
            $index++
            continue
        }

        if (($index + 1) -lt $Arguments.Count -and -not $Arguments[$index + 1].StartsWith('--')) {
            $result[$trimmed.Replace('-', '_')] = $Arguments[$index + 1]
            $index += 2
            continue
        }

        $result[$trimmed.Replace('-', '_')] = $true
        $index++
    }

    return $result
}

# endregion core/arguments.ps1

# region core/connection.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    解析 PostgreSQL 连接串为结构化字段。

.DESCRIPTION
    目前按 URI 方式解析 `postgresql://user:password@host:port/database`，
    供统一连接上下文组装逻辑复用。

.PARAMETER ConnectionString
    PostgreSQL 连接串；为空时返回空结果。

.OUTPUTS
    hashtable
    返回 `Host`、`Port`、`User`、`Password`、`Database` 字段。
#>
function ConvertFrom-PgConnectionString {
    [CmdletBinding()]
    param(
        [string]$ConnectionString
    )

    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        return @{}
    }

    $builder = [System.Uri]$ConnectionString
    $userInfoParts = $builder.UserInfo.Split(':', 2)
    return @{
        Host     = $builder.Host
        Port     = if ($builder.Port -gt 0) { $builder.Port } else { $null }
        User     = $userInfoParts[0]
        Password = if ($userInfoParts.Count -gt 1) { $userInfoParts[1] } else { $null }
        Database = $builder.AbsolutePath.TrimStart('/')
    }
}

<#
.SYNOPSIS
    在日志里屏蔽敏感值。

.DESCRIPTION
    当前主要用于密码等敏感信息展示时的统一脱敏处理。

.PARAMETER Value
    待脱敏的原始字符串。

.OUTPUTS
    string
    当输入非空时返回 `***`，否则返回原值。
#>
function Mask-PgSecret {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    return '***'
}

# endregion core/connection.ps1

# region core/context.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    解析 PostgreSQL toolkit 的默认 env 文件来源。

.DESCRIPTION
    按“当前工作目录优先，必要时回退脚本目录”的规则定位 `.env` 与 `.env.local`，
    并且一旦首选目录命中任意默认文件，就不再跨目录补缺。

.PARAMETER WorkingDirectory
    当前工作目录，默认使用 `Get-Location`。

.PARAMETER ScriptDirectory
    脚本目录，默认使用当前脚本所在目录。

.OUTPUTS
    PSCustomObject
    返回包含 `BasePath` 与 `Paths` 的默认 env 文件来源描述。
#>
function Resolve-PgDefaultEnvSource {
    [CmdletBinding()]
    param(
        [string]$WorkingDirectory = (Get-Location).Path,
        [string]$ScriptDirectory = $PSScriptRoot
    )

    return Resolve-DefaultEnvFiles -PrimaryBasePath $WorkingDirectory -FallbackBasePath $ScriptDirectory
}

<#
.SYNOPSIS
    解析一个或多个 PostgreSQL env 文件并按顺序合并。

.DESCRIPTION
    通过共享配置解析器复用严格 dotenv 语义，避免 PostgreSQL toolkit 继续维护独立 parser。

.PARAMETER Paths
    要解析的 env 文件路径列表。

.OUTPUTS
    hashtable
    返回合并后的 `PG*` 变量字典。
#>
function Import-PgEnvFiles {
    [CmdletBinding()]
    param(
        [string[]]$Paths
    )

    if ($null -eq $Paths -or $Paths.Count -eq 0) {
        return @{}
    }

    return (Resolve-ConfigSources -ConfigFile $Paths).Values
}

<#
.SYNOPSIS
    生成统一的 PostgreSQL 连接上下文。

.DESCRIPTION
    按“显式参数 > 连接串 > 显式 env-file > 当前进程环境变量 > 自动发现 env 文件”的优先级合并连接配置，
    让后续命令构建逻辑只依赖一个规范化对象。

.PARAMETER CliOptions
    由 `ConvertFrom-LongOptionList` 返回的参数表。

.PARAMETER WorkingDirectory
    当前工作目录，默认使用 `Get-Location`。

.PARAMETER ScriptDirectory
    脚本目录，默认使用当前脚本所在目录。

.OUTPUTS
    PSCustomObject
    返回统一的连接上下文，至少包含 `Host`、`Port`、`User`、`Password`、`Database`。
#>
function Resolve-PgContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CliOptions,

        [string]$WorkingDirectory = (Get-Location).Path,

        [string]$ScriptDirectory = $PSScriptRoot
    )

    $explicitEnvFilePath = if ($CliOptions.ContainsKey('env_file')) { [string]$CliOptions['env_file'] } else { $null }
    $connectionString = if ($CliOptions.ContainsKey('connection_string')) { [string]$CliOptions['connection_string'] } else { $null }
    $explicitEnvValues = if ([string]::IsNullOrWhiteSpace($explicitEnvFilePath)) { @{} } else { Read-ConfigEnvFile -Path $explicitEnvFilePath }
    $defaultEnvSource = if ([string]::IsNullOrWhiteSpace($explicitEnvFilePath)) {
        Resolve-PgDefaultEnvSource -WorkingDirectory $WorkingDirectory -ScriptDirectory $ScriptDirectory
    }
    else {
        [pscustomobject]@{
            BasePath = $null
            Paths    = @()
        }
    }
    $defaultEnvValues = Import-PgEnvFiles -Paths $defaultEnvSource.Paths
    $connectionValues = ConvertFrom-PgConnectionString -ConnectionString $connectionString

    $connectionHost = if ($connectionValues.ContainsKey('Host')) { $connectionValues['Host'] } else { $null }
    $connectionPort = if ($connectionValues.ContainsKey('Port')) { $connectionValues['Port'] } else { $null }
    $connectionUser = if ($connectionValues.ContainsKey('User')) { $connectionValues['User'] } else { $null }
    $connectionPassword = if ($connectionValues.ContainsKey('Password')) { $connectionValues['Password'] } else { $null }
    $connectionDatabase = if ($connectionValues.ContainsKey('Database')) { $connectionValues['Database'] } else { $null }

    $explicitEnvHost = if ($explicitEnvValues.ContainsKey('PGHOST')) { $explicitEnvValues['PGHOST'] } else { $null }
    $explicitEnvPort = if ($explicitEnvValues.ContainsKey('PGPORT')) { $explicitEnvValues['PGPORT'] } else { $null }
    $explicitEnvUser = if ($explicitEnvValues.ContainsKey('PGUSER')) { $explicitEnvValues['PGUSER'] } else { $null }
    $explicitEnvPassword = if ($explicitEnvValues.ContainsKey('PGPASSWORD')) { $explicitEnvValues['PGPASSWORD'] } else { $null }
    $explicitEnvDatabase = if ($explicitEnvValues.ContainsKey('PGDATABASE')) { $explicitEnvValues['PGDATABASE'] } else { $null }

    $defaultEnvHost = if ($defaultEnvValues.ContainsKey('PGHOST')) { $defaultEnvValues['PGHOST'] } else { $null }
    $defaultEnvPort = if ($defaultEnvValues.ContainsKey('PGPORT')) { $defaultEnvValues['PGPORT'] } else { $null }
    $defaultEnvUser = if ($defaultEnvValues.ContainsKey('PGUSER')) { $defaultEnvValues['PGUSER'] } else { $null }
    $defaultEnvPassword = if ($defaultEnvValues.ContainsKey('PGPASSWORD')) { $defaultEnvValues['PGPASSWORD'] } else { $null }
    $defaultEnvDatabase = if ($defaultEnvValues.ContainsKey('PGDATABASE')) { $defaultEnvValues['PGDATABASE'] } else { $null }

    $resolvedHost = if ($CliOptions.ContainsKey('host')) { [string]$CliOptions['host'] } elseif ($connectionHost) { $connectionHost } elseif ($explicitEnvHost) { $explicitEnvHost } elseif ($env:PGHOST) { $env:PGHOST } else { $defaultEnvHost }
    $resolvedPort = if ($CliOptions.ContainsKey('port')) { [int]$CliOptions['port'] } elseif ($connectionPort) { [int]$connectionPort } elseif ($explicitEnvPort) { [int]$explicitEnvPort } elseif ($env:PGPORT) { [int]$env:PGPORT } elseif ($defaultEnvPort) { [int]$defaultEnvPort } else { 5432 }
    $resolvedUser = if ($CliOptions.ContainsKey('user')) { [string]$CliOptions['user'] } elseif ($connectionUser) { $connectionUser } elseif ($explicitEnvUser) { $explicitEnvUser } elseif ($env:PGUSER) { $env:PGUSER } else { $defaultEnvUser }
    $resolvedPassword = if ($CliOptions.ContainsKey('password')) { [string]$CliOptions['password'] } elseif ($connectionPassword) { $connectionPassword } elseif ($explicitEnvPassword) { $explicitEnvPassword } elseif ($env:PGPASSWORD) { $env:PGPASSWORD } else { $defaultEnvPassword }
    $resolvedDatabase = if ($CliOptions.ContainsKey('database')) { [string]$CliOptions['database'] } elseif ($connectionDatabase) { $connectionDatabase } elseif ($explicitEnvDatabase) { $explicitEnvDatabase } elseif ($env:PGDATABASE) { $env:PGDATABASE } else { $defaultEnvDatabase }

    return [PSCustomObject]@{
        Host         = $resolvedHost
        Port         = $resolvedPort
        User         = $resolvedUser
        Password     = $resolvedPassword
        Database     = $resolvedDatabase
        EnvFile      = $explicitEnvFilePath
        AutoEnvFiles = @($defaultEnvSource.Paths)
        AutoEnvBase  = $defaultEnvSource.BasePath
    }
}

# endregion core/context.ps1

# region core/formats.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    识别 PostgreSQL 恢复输入类型。

.DESCRIPTION
    根据输入路径判断是 SQL 文本、归档文件还是目录格式，
    供 `restore` 子命令选择 `psql` 或 `pg_restore` 路径。

.PARAMETER InputPath
    用户传入的恢复输入路径。

.OUTPUTS
    string
    返回 `sql`、`archive` 或 `directory`。
#>
function Resolve-PgRestoreInputKind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputPath
    )

    if (Test-Path -Path $InputPath -PathType Container) {
        return 'directory'
    }

    $extension = [System.IO.Path]::GetExtension($InputPath).ToLowerInvariant()
    switch ($extension) {
        '.sql' { return 'sql' }
        '.dump' { return 'archive' }
        '.backup' { return 'archive' }
        '.tar' { return 'archive' }
        default { throw "不支持的恢复输入类型: $InputPath" }
    }
}

# endregion core/formats.ps1

# region core/validation.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    断言两个参数不能同时出现。

.DESCRIPTION
    用于封装常见的互斥选项校验，例如 `--schema-only` 与 `--data-only`。

.PARAMETER Left
    左侧参数是否被启用。

.PARAMETER Right
    右侧参数是否被启用。

.PARAMETER LeftName
    左侧参数名称，用于错误消息。

.PARAMETER RightName
    右侧参数名称，用于错误消息。
#>
function Assert-PgMutuallyExclusiveOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Left,

        [Parameter(Mandatory)]
        [bool]$Right,

        [Parameter(Mandatory)]
        [string]$LeftName,

        [Parameter(Mandatory)]
        [string]$RightName
    )

    if ($Left -and $Right) {
        throw "参数冲突: $LeftName 与 $RightName 不能同时使用。"
    }
}

# endregion core/validation.ps1

# region platforms/windows.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    生成 Windows 下的 PostgreSQL CLI 安装方案。

.DESCRIPTION
    当前默认优先使用 `winget`，并支持显式切换到 `choco`。

.PARAMETER PackageManager
    指定包管理器名称；`auto` 会自动选择默认策略。

.OUTPUTS
    PSCustomObject
    返回包管理器名称和待执行命令列表。
#>
function Get-PgWindowsInstallPlan {
    [CmdletBinding()]
    param(
        [string]$PackageManager = 'auto'
    )

    $manager = if ($PackageManager -eq 'auto') { 'winget' } else { $PackageManager }
    $command = switch ($manager) {
        'winget' { 'winget install --id PostgreSQL.PostgreSQL --source winget' }
        'choco' { 'choco install postgresql --yes' }
        default { throw "Windows 不支持的包管理器: $manager" }
    }

    return [PSCustomObject]@{
        PackageManager = $manager
        Commands       = @($command)
    }
}

# endregion platforms/windows.ps1

# region platforms/macos.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    生成 macOS 下的 PostgreSQL CLI 安装方案。

.DESCRIPTION
    当前只支持 Homebrew 路径，`auto` 会默认选择 `brew`。

.PARAMETER PackageManager
    指定包管理器名称；`auto` 会自动选择默认策略。

.OUTPUTS
    PSCustomObject
    返回包管理器名称和待执行命令列表。
#>
function Get-PgMacOSInstallPlan {
    [CmdletBinding()]
    param(
        [string]$PackageManager = 'auto'
    )

    $manager = if ($PackageManager -eq 'auto') { 'brew' } else { $PackageManager }
    if ($manager -ne 'brew') {
        throw "macOS 不支持的包管理器: $manager"
    }

    return [PSCustomObject]@{
        PackageManager = $manager
        Commands       = @('brew install libpq', 'brew link --force libpq')
    }
}

# endregion platforms/macos.ps1

# region platforms/linux.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    生成 Linux 下的 PostgreSQL CLI 安装方案。

.DESCRIPTION
    当前支持 `apt`、`dnf`、`yum`、`apk`，`auto` 默认选择 `apt`。

.PARAMETER PackageManager
    指定包管理器名称；`auto` 会自动选择默认策略。

.OUTPUTS
    PSCustomObject
    返回包管理器名称和待执行命令列表。
#>
function Get-PgLinuxInstallPlan {
    [CmdletBinding()]
    param(
        [string]$PackageManager = 'auto'
    )

    $manager = if ($PackageManager -eq 'auto') { 'apt' } else { $PackageManager }
    $command = switch ($manager) {
        'apt' { 'sudo apt-get update && sudo apt-get install -y postgresql-client' }
        'dnf' { 'sudo dnf install -y postgresql' }
        'yum' { 'sudo yum install -y postgresql' }
        'apk' { 'sudo apk add postgresql-client' }
        default { throw "Linux 不支持的包管理器: $manager" }
    }

    return [PSCustomObject]@{
        PackageManager = $manager
        Commands       = @($command)
    }
}

# endregion platforms/linux.ps1

# region commands/help.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    返回 PostgreSQL Toolkit 的帮助文本。

.DESCRIPTION
    统一生成 CLI 使用说明，后续子命令级帮助也从这里扩展，
    让控制台帮助与独立帮助文档尽量保持一致。

.PARAMETER CommandName
    可选的子命令名称；当前最小实现统一返回总览帮助。

.OUTPUTS
    string
    返回可直接打印到控制台的帮助文本。
#>
function Get-PostgresToolkitHelpText {
    [CmdletBinding()]
    param(
        [string]$CommandName
    )

    $defaultHelp = @'
Usage:
  ./Postgres-Toolkit.ps1 <command> [options]

Commands:
  backup
  restore
  import-csv
  install-tools
  help

Connection Defaults:
  If --env-file is provided, the toolkit reads only that file.
  If --env-file is omitted, the toolkit auto-discovers .env and .env.local from the current working directory first, then falls back to the script directory only when the current working directory has neither file.
  Connection precedence is: explicit options, --connection-string, explicit --env-file, current process PG* variables, then auto-discovered env files.

Examples:
  ./Postgres-Toolkit.ps1 backup --database app --output ./app.dump --format custom
  ./Postgres-Toolkit.ps1 restore --input ./app.dump --target-database app_restore --clean
  ./Postgres-Toolkit.ps1 import-csv --input ./users.csv --table users --header
  ./Postgres-Toolkit.ps1 install-tools --apply
'@

    return $defaultHelp.Trim()
}

# endregion commands/help.ps1

# region commands/backup.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    生成 PostgreSQL 备份命令描述。

.DESCRIPTION
    将 CLI 参数和已解析的连接上下文翻译为 `pg_dump` 的参数数组，
    供 dry-run 和真实执行共用。

.PARAMETER CliOptions
    解析后的子命令参数表。

.PARAMETER Context
    由 `Resolve-PgContext` 返回的统一连接上下文。

.OUTPUTS
    PSCustomObject
    返回可交给 `Invoke-PgNativeCommand` 的命令描述对象。
#>
function New-PgBackupCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CliOptions,

        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $format = if ($CliOptions.ContainsKey('format')) { [string]$CliOptions['format'] } else { 'custom' }
    if ($format -ne 'directory' -and $CliOptions.ContainsKey('jobs')) {
        throw '只有 directory 格式支持 --jobs。'
    }

    Assert-PgMutuallyExclusiveOptions `
        -Left ($CliOptions.ContainsKey('schema_only')) `
        -Right ($CliOptions.ContainsKey('data_only')) `
        -LeftName '--schema-only' `
        -RightName '--data-only'

    $arguments = @()

    # 仅附加已解析到的连接参数，避免 dry-run 在缺省值为空时生成非法参数对。
    if (-not [string]::IsNullOrWhiteSpace($Context.Host)) { $arguments += @('-h', $Context.Host) }
    if ($null -ne $Context.Port) { $arguments += @('-p', [string]$Context.Port) }
    if (-not [string]::IsNullOrWhiteSpace($Context.User)) { $arguments += @('-U', $Context.User) }
    if (-not [string]::IsNullOrWhiteSpace($Context.Database)) { $arguments += @('-d', $Context.Database) }

    $arguments += switch ($format) {
        'plain' { '-Fp' }
        'directory' { '-Fd' }
        'tar' { '-Ft' }
        default { '-Fc' }
    }

    if ($CliOptions.ContainsKey('output')) { $arguments += @('-f', [string]$CliOptions['output']) }
    if ($CliOptions.ContainsKey('table')) { $arguments += @('-t', [string]$CliOptions['table']) }
    if ($CliOptions.ContainsKey('schema')) { $arguments += @('-n', [string]$CliOptions['schema']) }
    if ($CliOptions.ContainsKey('exclude_table')) { $arguments += "--exclude-table=$($CliOptions['exclude_table'])" }
    if ($CliOptions.ContainsKey('schema_only')) { $arguments += '-s' }
    if ($CliOptions.ContainsKey('data_only')) { $arguments += '-a' }
    if ($CliOptions.ContainsKey('jobs')) { $arguments += @('-j', [string]$CliOptions['jobs']) }

    return New-PgNativeCommandSpec -FilePath 'pg_dump' -ArgumentList $arguments -Environment @{
        PGPASSWORD = $Context.Password
    }
}

# endregion commands/backup.ps1

# region commands/restore.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    生成 PostgreSQL 恢复命令描述。

.DESCRIPTION
    根据输入类型自动在 `psql` 与 `pg_restore` 之间切换，
    并把 CLI 参数翻译成对应的参数数组。

.PARAMETER CliOptions
    解析后的子命令参数表。

.PARAMETER Context
    由 `Resolve-PgContext` 返回的统一连接上下文。

.OUTPUTS
    PSCustomObject
    返回可交给 `Invoke-PgNativeCommand` 的命令描述对象。
#>
function New-PgRestoreCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CliOptions,

        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    if (-not $CliOptions.ContainsKey('input')) {
        throw 'restore 命令缺少 --input。'
    }

    $inputPath = [string]$CliOptions['input']
    $inputKind = Resolve-PgRestoreInputKind -InputPath $inputPath
    $targetDatabase = if ($CliOptions.ContainsKey('target_database')) { [string]$CliOptions['target_database'] } else { $Context.Database }

    if ($inputKind -eq 'sql') {
        $arguments = @()

        # 仅附加已解析到的连接参数，避免缺省值为空时生成非法参数对。
        if (-not [string]::IsNullOrWhiteSpace($Context.Host)) { $arguments += @('-h', $Context.Host) }
        if ($null -ne $Context.Port) { $arguments += @('-p', [string]$Context.Port) }
        if (-not [string]::IsNullOrWhiteSpace($Context.User)) { $arguments += @('-U', $Context.User) }
        if (-not [string]::IsNullOrWhiteSpace($targetDatabase)) { $arguments += @('-d', $targetDatabase) }
        $arguments += @(
            '-v', 'ON_ERROR_STOP=1',
            '-f', $inputPath
        )

        return New-PgNativeCommandSpec -FilePath 'psql' -ArgumentList $arguments -Environment @{
            PGPASSWORD = $Context.Password
        }
    }

    $arguments = @()

    # 仅附加已解析到的连接参数，避免缺省值为空时生成非法参数对。
    if (-not [string]::IsNullOrWhiteSpace($Context.Host)) { $arguments += @('-h', $Context.Host) }
    if ($null -ne $Context.Port) { $arguments += @('-p', [string]$Context.Port) }
    if (-not [string]::IsNullOrWhiteSpace($Context.User)) { $arguments += @('-U', $Context.User) }
    if (-not [string]::IsNullOrWhiteSpace($targetDatabase)) { $arguments += @('-d', $targetDatabase) }

    if ($CliOptions.ContainsKey('clean')) { $arguments += '--clean' }
    if ($CliOptions.ContainsKey('if_exists')) { $arguments += '--if-exists' }
    if ($CliOptions.ContainsKey('no_owner')) { $arguments += '--no-owner' }
    if ($CliOptions.ContainsKey('no_privileges')) { $arguments += '--no-privileges' }
    if ($CliOptions.ContainsKey('schema_only')) { $arguments += '-s' }
    if ($CliOptions.ContainsKey('data_only')) { $arguments += '-a' }
    if ($CliOptions.ContainsKey('table')) { $arguments += @('-t', [string]$CliOptions['table']) }
    if ($CliOptions.ContainsKey('schema')) { $arguments += @('-n', [string]$CliOptions['schema']) }
    if ($CliOptions.ContainsKey('jobs')) { $arguments += @('-j', [string]$CliOptions['jobs']) }
    $arguments += $inputPath

    return New-PgNativeCommandSpec -FilePath 'pg_restore' -ArgumentList $arguments -Environment @{
        PGPASSWORD = $Context.Password
    }
}

# endregion commands/restore.ps1

# region commands/import-csv.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    生成 PostgreSQL CSV 导入命令描述。

.DESCRIPTION
    使用 `psql -c "\copy ..."` 方式构建本地 CSV 导入命令，
    第一版只覆盖“导入到已存在表”的场景。

.PARAMETER CliOptions
    解析后的子命令参数表。

.PARAMETER Context
    由 `Resolve-PgContext` 返回的统一连接上下文。

.OUTPUTS
    PSCustomObject
    返回可交给 `Invoke-PgNativeCommand` 的命令描述对象。
#>
function New-PgImportCsvCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CliOptions,

        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    if (-not $CliOptions.ContainsKey('input')) {
        throw 'import-csv 命令缺少 --input。'
    }

    if (-not $CliOptions.ContainsKey('table')) {
        throw 'import-csv 命令缺少 --table。'
    }

    $schema = if ($CliOptions.ContainsKey('schema')) { [string]$CliOptions['schema'] } else { 'public' }
    $delimiter = if ($CliOptions.ContainsKey('delimiter')) { [string]$CliOptions['delimiter'] } else { ',' }
    $header = if ($CliOptions.ContainsKey('header')) { 'true' } else { 'false' }
    $columns = if ($CliOptions.ContainsKey('columns')) { "($($CliOptions['columns']))" } else { '' }
    $nullString = if ($CliOptions.ContainsKey('null_string')) { ", NULL '$($CliOptions['null_string'])'" } else { '' }
    $truncateSql = if ($CliOptions.ContainsKey('truncate_first')) { "TRUNCATE TABLE $schema.$($CliOptions['table']); " } else { '' }
    $copySql = "$truncateSql\copy $schema.$($CliOptions['table'])$columns FROM '$($CliOptions['input'])' WITH (FORMAT csv, HEADER $header, DELIMITER '$delimiter'$nullString);"

    $arguments = @()

    # 仅附加已解析到的连接参数，避免缺省值为空时生成非法参数对。
    if (-not [string]::IsNullOrWhiteSpace($Context.Host)) { $arguments += @('-h', $Context.Host) }
    if ($null -ne $Context.Port) { $arguments += @('-p', [string]$Context.Port) }
    if (-not [string]::IsNullOrWhiteSpace($Context.User)) { $arguments += @('-U', $Context.User) }
    if (-not [string]::IsNullOrWhiteSpace($Context.Database)) { $arguments += @('-d', $Context.Database) }
    $arguments += @(
        '-v', 'ON_ERROR_STOP=1',
        '-c', $copySql
    )

    return New-PgNativeCommandSpec -FilePath 'psql' -ArgumentList $arguments -Environment @{
        PGPASSWORD = $Context.Password
    }
}

# endregion commands/import-csv.ps1

# region commands/install-tools.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    检测缺失的 PostgreSQL CLI 工具。

.DESCRIPTION
    默认检查 `psql`、`pg_dump`、`pg_restore`、`pg_dumpall`，
    为 `install-tools` 决定是否需要输出或执行安装计划。

.PARAMETER Tools
    要检查的工具名称列表。

.OUTPUTS
    string[]
    返回当前环境中缺失的工具名数组。
#>
function Get-MissingPgTools {
    [CmdletBinding()]
    param(
        [string[]]$Tools = @('psql', 'pg_dump', 'pg_restore', 'pg_dumpall')
    )

    return @(
        foreach ($tool in $Tools) {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
                $tool
            }
        }
    )
}

<#
.SYNOPSIS
    生成 PostgreSQL CLI 安装计划。

.DESCRIPTION
    根据平台与包管理器策略选择对应的安装命令列表。

.PARAMETER Platform
    目标平台，只支持 `windows`、`macos`、`linux`。

.PARAMETER PackageManager
    指定包管理器名称；`auto` 会自动选择默认策略。

.PARAMETER Tools
    需要安装或检测的 PostgreSQL CLI 工具名列表。

.OUTPUTS
    PSCustomObject
    返回包管理器名称和待执行命令列表。
#>
function Get-PgInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('windows', 'macos', 'linux')]
        [string]$Platform,

        [string]$PackageManager = 'auto',

        [string[]]$Tools = @('psql', 'pg_dump', 'pg_restore', 'pg_dumpall')
    )

    switch ($Platform) {
        'windows' { return (Get-PgWindowsInstallPlan -PackageManager $PackageManager) }
        'macos' { return (Get-PgMacOSInstallPlan -PackageManager $PackageManager) }
        'linux' { return (Get-PgLinuxInstallPlan -PackageManager $PackageManager) }
    }
}

<#
.SYNOPSIS
    输出或执行 PostgreSQL CLI 安装计划。

.DESCRIPTION
    默认仅返回安装命令文本；传入 `-Apply` 时按平台选择 shell 执行命令。

.PARAMETER Plan
    由 `Get-PgInstallPlan` 返回的安装计划对象。

.PARAMETER Apply
    是否执行安装命令。

.OUTPUTS
    PSCustomObject
    返回包含 `ExitCode` 与 `Output` 的标准结果对象。
#>
function Invoke-PgInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Plan,

        [switch]$Apply
    )

    if (-not $Apply) {
        return [PSCustomObject]@{
            ExitCode = 0
            Output   = ($Plan.Commands -join [Environment]::NewLine)
        }
    }

    $runner = if ($IsWindows) {
        @{
            FilePath     = 'pwsh'
            ArgumentList = @('-NoProfile', '-Command')
        }
    }
    else {
        @{
            FilePath     = '/bin/sh'
            ArgumentList = @('-lc')
        }
    }

    foreach ($commandText in $Plan.Commands) {
        Write-PostgresToolkitMessage -Level info -Message ("执行安装命令: {0}" -f $commandText)
        $null = & $runner.FilePath @($runner.ArgumentList + $commandText)
        if ($LASTEXITCODE -ne 0) {
            throw "安装命令执行失败: $commandText"
        }
    }

    return [PSCustomObject]@{
        ExitCode = 0
        Output   = ($Plan.Commands -join [Environment]::NewLine)
    }
}

# endregion commands/install-tools.ps1

# region main-dispatch
function Invoke-PostgresToolkitCommand {
    [CmdletBinding()]
    param(
        [string]$CommandName,
        [string[]]$RawArguments
    )

    $options = ConvertFrom-LongOptionList -Arguments $RawArguments
    $dryRun = $options.ContainsKey('dry_run')

    if ([string]::IsNullOrWhiteSpace($CommandName) -or $CommandName -eq 'help') {
        return [PSCustomObject]@{
            ExitCode = 0
            Output   = Get-PostgresToolkitHelpText
        }
    }

    $context = Resolve-PgContext -CliOptions $options
    switch ($CommandName) {
        'backup' {
            $spec = New-PgBackupCommandSpec -CliOptions $options -Context $context
            return Invoke-PgNativeCommand -Spec $spec -DryRun:$dryRun
        }
        'restore' {
            $spec = New-PgRestoreCommandSpec -CliOptions $options -Context $context
            return Invoke-PgNativeCommand -Spec $spec -DryRun:$dryRun
        }
        'import-csv' {
            $spec = New-PgImportCsvCommandSpec -CliOptions $options -Context $context
            return Invoke-PgNativeCommand -Spec $spec -DryRun:$dryRun
        }
        'install-tools' {
            $platform = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
            $requestedTools = if ($options.ContainsKey('tool')) {
                @([string]$options['tool'] -split ',')
            }
            else {
                @('psql', 'pg_dump', 'pg_restore', 'pg_dumpall')
            }
            $missingTools = Get-MissingPgTools -Tools $requestedTools
            if ($missingTools.Count -eq 0) {
                return [PSCustomObject]@{
                    ExitCode = 0
                    Output   = '所有 PostgreSQL CLI 工具已可用。'
                }
            }

            $packageManager = if ($options.ContainsKey('package_manager')) { [string]$options['package_manager'] } else { 'auto' }
            $plan = Get-PgInstallPlan -Platform $platform -PackageManager $packageManager -Tools $missingTools
            return Invoke-PgInstallPlan -Plan $plan -Apply:$($options.ContainsKey('apply'))
        }
        default {
            return [PSCustomObject]@{
                ExitCode = 0
                Output   = Get-PostgresToolkitHelpText
            }
        }
    }
}
# endregion main-dispatch

if ($env:PWSH_TEST_SKIP_POSTGRES_TOOLKIT_MAIN -ne '1') {
    $result = Invoke-PostgresToolkitCommand -CommandName $CommandName -RawArguments $RawArguments
    if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
        Write-Output $result.Output
    }

    exit $result.ExitCode
}
