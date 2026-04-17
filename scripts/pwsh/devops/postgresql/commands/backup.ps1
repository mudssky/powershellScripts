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
