Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    检测缺失的 PostgreSQL CLI 工具。

.DESCRIPTION
    默认检查 `psql`、`pg_dump`、`pg_restore`、`pg_dumpall`，
    为 `install-tools` 决定是否需要输出或执行安装计划。

.PARAMETER Tools
    要检查的工具名称列表。

.OUTPUTS
    string[]
    返回当前环境中缺失的工具名数组。
#>
function Get-MissingPgTools {
    [CmdletBinding()]
    param(
        [string[]]$Tools = @('psql', 'pg_dump', 'pg_restore', 'pg_dumpall')
    )

    return @(
        foreach ($tool in $Tools) {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
                $tool
            }
        }
    )
}

<#
.SYNOPSIS
    生成 PostgreSQL CLI 安装计划。

.DESCRIPTION
    根据平台与包管理器策略选择对应的安装命令列表。

.PARAMETER Platform
    目标平台，只支持 `windows`、`macos`、`linux`。

.PARAMETER PackageManager
    指定包管理器名称；`auto` 会自动选择默认策略。

.PARAMETER Tools
    需要安装或检测的 PostgreSQL CLI 工具名列表。

.OUTPUTS
    PSCustomObject
    返回包管理器名称和待执行命令列表。
#>
function Get-PgInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('windows', 'macos', 'linux')]
        [string]$Platform,

        [string]$PackageManager = 'auto',

        [string[]]$Tools = @('psql', 'pg_dump', 'pg_restore', 'pg_dumpall')
    )

    switch ($Platform) {
        'windows' { return (Get-PgWindowsInstallPlan -PackageManager $PackageManager) }
        'macos' { return (Get-PgMacOSInstallPlan -PackageManager $PackageManager) }
        'linux' { return (Get-PgLinuxInstallPlan -PackageManager $PackageManager) }
    }
}

<#
.SYNOPSIS
    输出或执行 PostgreSQL CLI 安装计划。

.DESCRIPTION
    默认仅返回安装命令文本；传入 `-Apply` 时按平台选择 shell 执行命令。

.PARAMETER Plan
    由 `Get-PgInstallPlan` 返回的安装计划对象。

.PARAMETER Apply
    是否执行安装命令。

.OUTPUTS
    PSCustomObject
    返回包含 `ExitCode` 与 `Output` 的标准结果对象。
#>
function Invoke-PgInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Plan,

        [switch]$Apply
    )

    if (-not $Apply) {
        return [PSCustomObject]@{
            ExitCode = 0
            Output   = ($Plan.Commands -join [Environment]::NewLine)
        }
    }

    $runner = if ($IsWindows) {
        @{
            FilePath     = 'pwsh'
            ArgumentList = @('-NoProfile', '-Command')
        }
    }
    else {
        @{
            FilePath     = '/bin/sh'
            ArgumentList = @('-lc')
        }
    }

    foreach ($commandText in $Plan.Commands) {
        Write-PostgresToolkitMessage -Level info -Message ("执行安装命令: {0}" -f $commandText)
        $null = & $runner.FilePath @($runner.ArgumentList + $commandText)
        if ($LASTEXITCODE -ne 0) {
            throw "安装命令执行失败: $commandText"
        }
    }

    return [PSCustomObject]@{
        ExitCode = 0
        Output   = ($Plan.Commands -join [Environment]::NewLine)
    }
}
