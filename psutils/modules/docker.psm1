Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    检查 Docker Compose v2 是否可用。

.OUTPUTS
    bool。docker 命令存在且 `docker compose version` 成功时返回 true。
#>
function Test-DockerComposeAvailable {
    [CmdletBinding()]
    param()

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return $false
    }

    & docker 'compose' 'version' *> $null
    return $LASTEXITCODE -eq 0
}

<#
.SYNOPSIS
    校验 compose 模板、env 文件和 Docker Compose 前置条件。

.PARAMETER ComposeFile
    compose 模板路径。

.PARAMETER EnvFile
    可选 env 文件路径；缺失时只告警。

.PARAMETER EnvFileMissingMessage
    env 文件缺失时输出的告警文本。

.PARAMETER SkipDockerCheck
    为 true 时只校验文件，不检查 docker 命令。

.OUTPUTS
    None。校验失败时抛出异常。
#>
function Assert-DockerComposeReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComposeFile,

        [AllowEmptyString()]
        [string]$EnvFile = '',

        [AllowEmptyString()]
        [string]$EnvFileMissingMessage = '',

        [switch]$SkipDockerCheck
    )

    if (-not (Test-Path -LiteralPath $ComposeFile)) {
        throw "未找到 compose 模板: $ComposeFile"
    }

    if (-not [string]::IsNullOrWhiteSpace($EnvFile) -and -not (Test-Path -LiteralPath $EnvFile)) {
        $message = if ([string]::IsNullOrWhiteSpace($EnvFileMissingMessage)) {
            "未找到环境变量文件: $EnvFile。脚本会继续执行。"
        }
        else {
            $EnvFileMissingMessage
        }
        Write-Warning $message
    }

    if ($SkipDockerCheck) {
        return
    }

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw '未找到 docker 命令，请先安装并确认 Docker Engine / Docker Desktop 已加入 PATH。'
    }

    & docker 'compose' 'version' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw '未检测到可用的 docker compose 子命令，请确认本机 Docker 版本支持 compose v2。'
    }
}

<#
.SYNOPSIS
    生成 Docker Compose 基础参数。

.PARAMETER ComposeFile
    compose 模板路径。

.PARAMETER ProjectDirectory
    compose 项目目录。

.PARAMETER EnvFile
    可选 env 文件路径；存在时追加 `--env-file`。

.OUTPUTS
    string[]。不包含最前面 `docker` 的 compose 参数数组。
#>
function Get-DockerComposeBaseArgs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComposeFile,

        [Parameter(Mandatory)]
        [string]$ProjectDirectory,

        [AllowEmptyString()]
        [string]$EnvFile = ''
    )

    $args = @(
        'compose'
        '-f'
        $ComposeFile
        '--project-directory'
        $ProjectDirectory
    )

    if (-not [string]::IsNullOrWhiteSpace($EnvFile) -and (Test-Path -LiteralPath $EnvFile)) {
        $args += @('--env-file', $EnvFile)
    }

    return [string[]]$args
}

<#
.SYNOPSIS
    执行或预览 Docker Compose 命令。

.PARAMETER ComposeArgs
    不包含最前面 `docker` 的完整 compose 参数。

.PARAMETER Environment
    临时注入到进程环境的变量。

.PARAMETER DryRun
    为 true 时只返回预览命令，不执行 docker。

.OUTPUTS
    string。DryRun 时返回预览命令；实际执行成功时返回空字符串。
#>
function Invoke-DockerComposeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ComposeArgs,

        [hashtable]$Environment = @{},

        [switch]$DryRun
    )

    $environmentPrefix = ''
    if ($Environment.Count -gt 0) {
        $environmentPrefix = (($Environment.GetEnumerator() | Sort-Object Key | ForEach-Object {
                    '{0}={1}' -f $_.Key, $_.Value
                }) -join ' ') + ' '
    }

    $preview = $environmentPrefix + 'docker ' + ($ComposeArgs -join ' ')
    if ($DryRun) {
        return $preview
    }

    $originalValues = @{}
    foreach ($entry in $Environment.GetEnumerator()) {
        $originalValues[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
    }

    try {
        & docker @ComposeArgs
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }
    finally {
        foreach ($entry in $Environment.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $originalValues[$entry.Key], 'Process')
        }
    }

    return ''
}

Export-ModuleMember -Function @(
    'Test-DockerComposeAvailable'
    'Assert-DockerComposeReady'
    'Get-DockerComposeBaseArgs'
    'Invoke-DockerComposeCommand'
)
