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

    $arguments = @(
        '-h', $Context.Host,
        '-p', [string]$Context.Port,
        '-U', $Context.User,
        '-d', $Context.Database,
        '-v', 'ON_ERROR_STOP=1',
        '-c', $copySql
    )

    return New-PgNativeCommandSpec -FilePath 'psql' -ArgumentList $arguments -Environment @{
        PGPASSWORD = $Context.Password
    }
}
