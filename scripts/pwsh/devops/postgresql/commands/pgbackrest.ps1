Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    生成 pgBackRest 维护命令描述。

.DESCRIPTION
    将 CLI 参数与 `PGBR_*` env 文件默认值翻译为 `pgbackrest` 参数数组，
    用于统一封装远程 stanza 检查、创建、备份、查看和过期清理。

.PARAMETER CliOptions
    解析后的子命令参数表。

.OUTPUTS
    PSCustomObject
    返回可交给 `Invoke-PgNativeCommand` 的命令描述对象。
#>
function New-PgBackRestCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CliOptions
    )

    $envValues = Resolve-PgBackRestEnvValues -CliOptions $CliOptions
    $action = Get-PgBackRestOptionValue -CliOptions $CliOptions -EnvValues $envValues -OptionName 'action' -EnvName 'PGBR_ACTION' -DefaultValue 'info'
    $stanza = Get-PgBackRestOptionValue -CliOptions $CliOptions -EnvValues $envValues -OptionName 'stanza' -EnvName 'PGBR_STANZA' -DefaultValue 'lobechat'
    $config = Get-PgBackRestOptionValue -CliOptions $CliOptions -EnvValues $envValues -OptionName 'config' -EnvName 'PGBR_CONFIG'
    $repo = Get-PgBackRestOptionValue -CliOptions $CliOptions -EnvValues $envValues -OptionName 'repo' -EnvName 'PGBR_REPO'
    $repo1Path = Get-PgBackRestOptionValue -CliOptions $CliOptions -EnvValues $envValues -OptionName 'repo1_path' -EnvName 'PGBR_REPO1_PATH'
    $pg1Host = Get-PgBackRestOptionValue -CliOptions $CliOptions -EnvValues $envValues -OptionName 'pg1_host' -EnvName 'PGBR_PG1_HOST'
    $pg1HostType = Get-PgBackRestOptionValue -CliOptions $CliOptions -EnvValues $envValues -OptionName 'pg1_host_type' -EnvName 'PGBR_PG1_HOST_TYPE'
    $pg1HostUser = Get-PgBackRestOptionValue -CliOptions $CliOptions -EnvValues $envValues -OptionName 'pg1_host_user' -EnvName 'PGBR_PG1_HOST_USER'
    $pg1Path = Get-PgBackRestOptionValue -CliOptions $CliOptions -EnvValues $envValues -OptionName 'pg1_path' -EnvName 'PGBR_PG1_PATH'
    $backupType = Get-PgBackRestOptionValue -CliOptions $CliOptions -EnvValues $envValues -OptionName 'type' -EnvName 'PGBR_BACKUP_TYPE' -DefaultValue 'full'

    Assert-PgBackRestAction -Action $action
    if ($action -eq 'backup') {
        Assert-PgBackRestBackupType -BackupType $backupType
    }

    $arguments = @()
    if (-not [string]::IsNullOrWhiteSpace($config)) { $arguments += "--config=$config" }
    if (-not [string]::IsNullOrWhiteSpace($stanza)) { $arguments += "--stanza=$stanza" }
    if (-not [string]::IsNullOrWhiteSpace($repo)) { $arguments += "--repo=$repo" }
    if (-not [string]::IsNullOrWhiteSpace($repo1Path)) { $arguments += "--repo1-path=$repo1Path" }
    if (-not [string]::IsNullOrWhiteSpace($pg1Host)) { $arguments += "--pg1-host=$pg1Host" }
    if (-not [string]::IsNullOrWhiteSpace($pg1HostType)) { $arguments += "--pg1-host-type=$pg1HostType" }
    if (-not [string]::IsNullOrWhiteSpace($pg1HostUser)) { $arguments += "--pg1-host-user=$pg1HostUser" }
    if (-not [string]::IsNullOrWhiteSpace($pg1Path)) { $arguments += "--pg1-path=$pg1Path" }

    if ($action -eq 'backup') {
        $arguments += "--type=$backupType"
    }

    $arguments += $action

    return New-PgNativeCommandSpec -FilePath 'pgbackrest' -ArgumentList $arguments -Environment @{}
}

<#
.SYNOPSIS
    读取 pgBackRest 命令专属 env 默认值。

.DESCRIPTION
    仅在传入 `--env-file` 时读取指定文件，不走 PostgreSQL 连接上下文的默认 `.env` 发现规则，
    避免仓库根目录的应用 `.env` 干扰 pgBackRest 维护命令。

.PARAMETER CliOptions
    解析后的子命令参数表。

.OUTPUTS
    hashtable
    返回 env 文件中的配置键值。
#>
function Resolve-PgBackRestEnvValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CliOptions
    )

    if (-not $CliOptions.ContainsKey('env_file')) {
        return @{}
    }

    $envFilePath = [string]$CliOptions['env_file']
    if (-not (Test-Path -LiteralPath $envFilePath -PathType Leaf)) {
        throw "配置文件不存在: $envFilePath"
    }

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $envFilePath) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
            continue
        }

        if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            throw "无效 pgBackRest env 行: $envFilePath"
        }

        $values[$Matches[1].Trim()] = $Matches[2].Trim()
    }

    return $values
}

<#
.SYNOPSIS
    按 CLI 优先、env 次之、默认值最后的顺序读取 pgBackRest 选项。

.DESCRIPTION
    让 `pgbackrest` 子命令可以复用 `pgbackrest.env.local`，同时允许命令行显式覆盖单个字段。

.PARAMETER CliOptions
    解析后的子命令参数表。

.PARAMETER EnvValues
    `Resolve-PgBackRestEnvValues` 返回的 env 值。

.PARAMETER OptionName
    CLI 参数键名，使用下划线风格。

.PARAMETER EnvName
    env 文件中的变量名。

.PARAMETER DefaultValue
    CLI 和 env 都未设置时的默认值。

.OUTPUTS
    string
    返回解析后的字符串值；未设置时返回 `$null`。
#>
function Get-PgBackRestOptionValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CliOptions,

        [Parameter(Mandatory)]
        [hashtable]$EnvValues,

        [Parameter(Mandatory)]
        [string]$OptionName,

        [Parameter(Mandatory)]
        [string]$EnvName,

        [AllowNull()]
        [string]$DefaultValue
    )

    if ($CliOptions.ContainsKey($OptionName)) {
        return [string]$CliOptions[$OptionName]
    }

    if ($EnvValues.ContainsKey($EnvName)) {
        return [string]$EnvValues[$EnvName]
    }

    return $DefaultValue
}

<#
.SYNOPSIS
    校验 pgBackRest action 是否属于当前封装支持的维护动作。

.PARAMETER Action
    用户传入的 action 名称。

.OUTPUTS
    System.Void
    校验失败时抛出异常；成功时无输出。
#>
function Assert-PgBackRestAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Action
    )

    $allowedActions = @('check', 'stanza-create', 'backup', 'info', 'expire')
    if ($Action -notin $allowedActions) {
        throw "pgbackrest --action 只支持: $($allowedActions -join ', ')。"
    }
}

<#
.SYNOPSIS
    校验 pgBackRest backup 类型。

.PARAMETER BackupType
    用户传入的 backup 类型。

.OUTPUTS
    System.Void
    校验失败时抛出异常；成功时无输出。
#>
function Assert-PgBackRestBackupType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupType
    )

    $allowedTypes = @('full', 'diff', 'incr')
    if ($BackupType -notin $allowedTypes) {
        throw "pgbackrest backup --type 只支持: $($allowedTypes -join ', ')。"
    }
}
