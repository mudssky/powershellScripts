#!/usr/bin/env pwsh
<#
.SYNOPSIS
    PostgreSQL 常用备份、恢复、CSV 导入与工具安装命令行工具。

.DESCRIPTION
    当前入口先负责子命令分发与帮助输出，后续命令实现会逐步挂到这里。

.PARAMETER CommandName
    要执行的子命令名称，例如 `backup`、`restore`、`help`。

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

<#
.SYNOPSIS
    执行 PostgreSQL Toolkit 的顶层命令分发。

.DESCRIPTION
    当前最小实现只负责帮助命令与空命令路径，后续再接入具体子命令。

.PARAMETER CommandName
    顶层命令名。

.PARAMETER RawArguments
    透传的剩余参数。

.OUTPUTS
    PSCustomObject
    返回包含 `ExitCode` 与 `Output` 的标准执行结果。
#>
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
        default {
            return [PSCustomObject]@{
                ExitCode = 0
                Output   = Get-PostgresToolkitHelpText
            }
        }
    }
}

if ($env:PWSH_TEST_SKIP_POSTGRES_TOOLKIT_MAIN -ne '1') {
    $result = Invoke-PostgresToolkitCommand -CommandName $CommandName -RawArguments $RawArguments
    if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
        Write-Output $result.Output
    }

    exit $result.ExitCode
}
