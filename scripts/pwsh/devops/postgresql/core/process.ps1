Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    生成 native command 的预览文本。

.DESCRIPTION
    将命令名和参数数组渲染为一行字符串，供 `--dry-run` 输出使用。

.PARAMETER Spec
    由 `New-PgNativeCommandSpec` 生成的命令描述对象。

.OUTPUTS
    string
    返回可直接展示给用户的命令预览文本。
#>
function Format-PgNativeCommandPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Spec
    )

    $arguments = $Spec.ArgumentList -join ' '
    return ("{0} {1}" -f $Spec.FilePath, $arguments).Trim()
}

<#
.SYNOPSIS
    创建统一的原生命令描述对象。

.DESCRIPTION
    把命令路径、参数列表和需要注入的环境变量统一封装，方便 dry-run 与真实执行共享。

.PARAMETER FilePath
    要执行的命令名或完整路径。

.PARAMETER ArgumentList
    传递给命令的参数数组。

.PARAMETER Environment
    进程级环境变量覆盖值，例如 `PGPASSWORD`。

.OUTPUTS
    PSCustomObject
    返回包含 `FilePath`、`ArgumentList`、`Environment` 的命令描述对象。
#>
function New-PgNativeCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [AllowNull()]
        [hashtable]$Environment
    )

    return [PSCustomObject]@{
        FilePath     = $FilePath
        ArgumentList = $ArgumentList
        Environment  = if ($null -eq $Environment) { @{} } else { $Environment }
    }
}

<#
.SYNOPSIS
    以 dry-run 或真实执行方式运行 PostgreSQL 原生命令。

.DESCRIPTION
    `--dry-run` 场景只返回命令预览；真实执行场景会临时注入环境变量后调用目标命令，
    并在结束后恢复进程环境，避免把敏感变量泄露给后续步骤。

.PARAMETER Spec
    由 `New-PgNativeCommandSpec` 生成的命令描述对象。

.PARAMETER DryRun
    是否仅输出命令预览而不真正执行。

.OUTPUTS
    PSCustomObject
    返回包含 `ExitCode` 与 `Output` 的结果对象。
#>
function Invoke-PgNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Spec,

        [switch]$DryRun
    )

    if ($DryRun) {
        return [PSCustomObject]@{
            ExitCode = 0
            Output   = Format-PgNativeCommandPreview -Spec $Spec
        }
    }

    $previousValues = @{}
    foreach ($entry in $Spec.Environment.GetEnumerator()) {
        $previousValues[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }

    try {
        $argumentList = @($Spec.ArgumentList)
        $output = @(& $Spec.FilePath @argumentList)
        return [PSCustomObject]@{
            ExitCode = $LASTEXITCODE
            Output   = ($output -join [Environment]::NewLine)
        }
    }
    finally {
        foreach ($entry in $previousValues.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
        }
    }
}
