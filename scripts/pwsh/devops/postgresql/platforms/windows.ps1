Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    生成 Windows 下的 PostgreSQL CLI 安装方案。

.DESCRIPTION
    当前默认优先使用 `winget`，并支持显式切换到 `choco`。

.PARAMETER PackageManager
    指定包管理器名称；`auto` 会自动选择默认策略。

.OUTPUTS
    PSCustomObject
    返回包管理器名称和待执行命令列表。
#>
function Get-PgWindowsInstallPlan {
    [CmdletBinding()]
    param(
        [string]$PackageManager = 'auto'
    )

    $manager = if ($PackageManager -eq 'auto') { 'winget' } else { $PackageManager }
    $command = switch ($manager) {
        'winget' { 'winget install --id PostgreSQL.PostgreSQL --source winget' }
        'choco' { 'choco install postgresql --yes' }
        default { throw "Windows 不支持的包管理器: $manager" }
    }

    return [PSCustomObject]@{
        PackageManager = $manager
        Commands       = @($command)
    }
}
