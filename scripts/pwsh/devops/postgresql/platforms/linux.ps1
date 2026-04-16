Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    生成 Linux 下的 PostgreSQL CLI 安装方案。

.DESCRIPTION
    当前支持 `apt`、`dnf`、`yum`、`apk`，`auto` 默认选择 `apt`。

.PARAMETER PackageManager
    指定包管理器名称；`auto` 会自动选择默认策略。

.OUTPUTS
    PSCustomObject
    返回包管理器名称和待执行命令列表。
#>
function Get-PgLinuxInstallPlan {
    [CmdletBinding()]
    param(
        [string]$PackageManager = 'auto'
    )

    $manager = if ($PackageManager -eq 'auto') { 'apt' } else { $PackageManager }
    $command = switch ($manager) {
        'apt' { 'sudo apt-get update && sudo apt-get install -y postgresql-client' }
        'dnf' { 'sudo dnf install -y postgresql' }
        'yum' { 'sudo yum install -y postgresql' }
        'apk' { 'sudo apk add postgresql-client' }
        default { throw "Linux 不支持的包管理器: $manager" }
    }

    return [PSCustomObject]@{
        PackageManager = $manager
        Commands       = @($command)
    }
}
