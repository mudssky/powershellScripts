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
