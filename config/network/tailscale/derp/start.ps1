[CmdletBinding()]
param(
    # 默认直接执行 up，对齐“复制 .env.local 后直接启动”的使用习惯。
    [string]$Action = 'up',

    # 通过 DryRun 直接返回 docker compose 预览命令，便于测试与排障。
    [switch]$DryRun,

    # 透传 compose 原生命令参数，避免为日志条数等小需求额外扩脚本分支。
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ComposeFile = Join-Path $script:ScriptDir 'compose.yaml'
$script:EnvFile = Join-Path $script:ScriptDir '.env.local'

function Show-Usage {
    <#
    .SYNOPSIS
        返回 DERP compose 包装脚本的用法说明。

    .OUTPUTS
        System.String
        返回可直接输出到终端的说明文本。
    #>
    return @'
用法:
  ./start.ps1 [up|down|restart|logs|ps|pull|build|config|help] [-DryRun] [额外 compose 参数]

默认行为:
  ./start.ps1         -> BUILDKIT_PROGRESS=plain docker compose build && docker compose up -d --no-build
  ./start.ps1 logs    -> docker compose logs -f derper
  ./start.ps1 config  -> docker compose config

示例:
  ./start.ps1
  ./start.ps1 -DryRun
  ./start.ps1 build --no-cache
  ./start.ps1 logs --tail 100
  ./start.ps1 pull
'@
}

function Assert-ComposeTemplateReady {
    <#
    .SYNOPSIS
        检查 compose 模板与 docker compose 前置条件。

    .DESCRIPTION
        DryRun 模式只校验模板文件存在，避免为了查看命令预览还强依赖本机 docker 环境。

    .PARAMETER ComposeFile
        compose 模板路径。

    .PARAMETER EnvFile
        本地环境变量文件路径。

    .PARAMETER SkipDockerCheck
        为 `$true` 时跳过 docker / docker compose 可用性检查。
    #>
    [CmdletBinding()]
    param(
        [string]$ComposeFile,
        [string]$EnvFile,
        [bool]$SkipDockerCheck
    )

    if (-not (Test-Path -LiteralPath $ComposeFile)) {
        throw "未找到 compose 模板: $ComposeFile"
    }

    if (-not (Test-Path -LiteralPath $EnvFile)) {
        Write-Warning "未找到环境变量文件: $EnvFile。脚本会继续执行，但 DERP_PUBLIC_IP / TS_AUTHKEY 等变量必须通过其它方式提供。"
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

function Get-ComposeBaseArgs {
    <#
    .SYNOPSIS
        生成统一的 docker compose 基础参数。

    .PARAMETER ComposeFile
        compose 模板路径。

    .PARAMETER ProjectDirectory
        compose 项目目录。

    .PARAMETER EnvFile
        可选环境变量文件路径；文件存在时才会追加 `--env-file`。

    .OUTPUTS
        System.String[]
        返回 `docker` 后续应接收的 compose 参数数组。
    #>
    [CmdletBinding()]
    param(
        [string]$ComposeFile,
        [string]$ProjectDirectory,
        [string]$EnvFile
    )

    $args = @(
        'compose'
        '-f'
        $ComposeFile
        '--project-directory'
        $ProjectDirectory
    )

    if (Test-Path -LiteralPath $EnvFile) {
        $args += @('--env-file', $EnvFile)
    }

    return $args
}

function Invoke-DockerCompose {
    <#
    .SYNOPSIS
        执行或预览 docker compose 命令。

    .PARAMETER ComposeArgs
        完整的 compose 参数数组，不包含最前面的 `docker`。

    .PARAMETER DryRun
        为 `$true` 时只返回命令预览字符串。

    .OUTPUTS
        System.String
        DryRun 模式下返回可复制的命令文本。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
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
}

function Get-ComposeInvocationPlan {
    <#
    .SYNOPSIS
        生成当前动作对应的一组 compose 子命令计划。

    .DESCRIPTION
        `up` 会先显式执行 `build`，再执行 `up -d --no-build`。
        这样构建日志可以通过 `BUILDKIT_PROGRESS=plain` 直接展开，避免排障时只看到
        `Image ... Building` 的折叠进度条。

    .PARAMETER Action
        标准化后的动作名。

    .PARAMETER ExtraArgs
        需要透传给 compose 子命令的额外参数。

    .OUTPUTS
        System.Object[]
        返回按执行顺序排列的计划项，每项包含 `ComposeArgs` 与 `Environment`。
    #>
    [CmdletBinding()]
    param(
        [string]$Action,
        [string[]]$ExtraArgs = @()
    )

    $buildEnvironment = @{ BUILDKIT_PROGRESS = 'plain' }
    $newPlanItem = {
        param(
            [string[]]$ComposeArgs,
            [hashtable]$Environment
        )

        return [pscustomobject]@{
            ComposeArgs = $ComposeArgs
            Environment = $Environment
        }
    }

    switch ($Action) {
        'up' {
            return @(
                (& $newPlanItem -ComposeArgs (@('build') + $ExtraArgs) -Environment $buildEnvironment),
                (& $newPlanItem -ComposeArgs @('up', '-d', '--no-build') -Environment @{})
            )
        }
        'build' {
            return ,(& $newPlanItem -ComposeArgs (@('build') + $ExtraArgs) -Environment $buildEnvironment)
        }
        'down' {
            return ,(& $newPlanItem -ComposeArgs (@('down') + $ExtraArgs) -Environment @{})
        }
        'restart' {
            return ,(& $newPlanItem -ComposeArgs (@('restart') + $ExtraArgs) -Environment @{})
        }
        'logs' {
            return ,(& $newPlanItem -ComposeArgs (@('logs', '-f', 'derper') + $ExtraArgs) -Environment @{})
        }
        'ps' {
            return ,(& $newPlanItem -ComposeArgs (@('ps') + $ExtraArgs) -Environment @{})
        }
        'pull' {
            return ,(& $newPlanItem -ComposeArgs (@('pull') + $ExtraArgs) -Environment @{})
        }
        'config' {
            return ,(& $newPlanItem -ComposeArgs (@('config') + $ExtraArgs) -Environment @{})
        }
        default {
            throw "不支持的操作: $Action"
        }
    }
}

if ($env:PWSH_TEST_SKIP_TAILSCALE_DERP_START_MAIN -eq '1') {
    return
}

$normalizedAction = $Action.ToLowerInvariant()
if ($normalizedAction -in @('help', '-h', '--help')) {
    Show-Usage | Write-Host
    exit 0
}

Assert-ComposeTemplateReady -ComposeFile $script:ComposeFile -EnvFile $script:EnvFile -SkipDockerCheck:$DryRun

$composeBaseArgs = Get-ComposeBaseArgs `
    -ComposeFile $script:ComposeFile `
    -ProjectDirectory $script:ScriptDir `
    -EnvFile $script:EnvFile

try {
    $invocationPlan = Get-ComposeInvocationPlan -Action $normalizedAction -ExtraArgs $ExtraArgs
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Show-Usage | Write-Host
    exit 1
}

foreach ($planItem in $invocationPlan) {
    $composeArgs = $composeBaseArgs + $planItem.ComposeArgs
    $result = Invoke-DockerCompose -ComposeArgs $composeArgs -Environment $planItem.Environment -DryRun:$DryRun
    if ($DryRun -and -not [string]::IsNullOrWhiteSpace($result)) {
        Write-Host $result
    }
}
