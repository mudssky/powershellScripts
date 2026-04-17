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
