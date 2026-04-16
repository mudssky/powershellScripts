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
