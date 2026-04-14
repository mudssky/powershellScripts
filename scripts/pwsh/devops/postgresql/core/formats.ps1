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
