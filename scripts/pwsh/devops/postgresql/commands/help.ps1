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
