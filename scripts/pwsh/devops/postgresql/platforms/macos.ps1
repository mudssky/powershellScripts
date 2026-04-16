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
