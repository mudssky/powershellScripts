[CmdletBinding()]
param(
    # 默认执行 up，对齐同目录其它网关脚本的启动体验。
    [string]$Action = 'up',

    # 允许透传 compose 原生命令参数，例如 `logs --tail 100`。
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$composeFile = Join-Path $scriptDir 'compose.yaml'
$envFile = Join-Path $scriptDir '.env.local'
$defaultLogService = 'portkey'

function Show-Usage {
    <#
    .SYNOPSIS
    输出 Portkey compose 包装脚本的用法说明。
    #>
    @'
用法:
  ./start.ps1 [up|down|restart|logs|ps|pull] [额外 compose 参数]

默认行为:
  ./start.ps1         -> docker compose up -d
  ./start.ps1 logs    -> docker compose logs -f portkey
'@ | Write-Host
}

function Assert-DockerComposeReady {
    <#
    .SYNOPSIS
    检查 docker 与 docker compose 是否可用，并确认 compose 模板文件存在。
    #>
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw '未找到 docker 命令，请先安装并确认 Docker Desktop / Docker Engine 已加入 PATH。'
    }

    & docker 'compose' 'version' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw '未检测到可用的 docker compose 子命令，请确认本机 Docker 版本支持 compose v2。'
    }

    if (-not (Test-Path -LiteralPath $composeFile)) {
        throw "未找到 compose 模板: $composeFile"
    }

    if (-not (Test-Path -LiteralPath $envFile)) {
        Write-Warning "未找到环境变量文件: $envFile。脚本会继续执行，并使用 compose.yaml 中的默认值。"
    }
}

function Get-ComposeBaseArgs {
    <#
    .SYNOPSIS
    生成统一的 compose 基础参数，避免从不同工作目录运行时出现路径漂移。
    .OUTPUTS
    System.String[]
    #>
    $args = @(
        'compose'
        '-f'
        $composeFile
        '--project-directory'
        $scriptDir
    )

    if (Test-Path -LiteralPath $envFile) {
        $args += @('--env-file', $envFile)
    }

    return $args
}

function Invoke-DockerCompose {
    <#
    .SYNOPSIS
    调用 docker compose，并把底层退出码原样返回。
    .PARAMETER ComposeArgs
    compose 子命令参数数组。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ComposeArgs
    )

    & docker @ComposeArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Assert-DockerComposeReady

$normalizedAction = $Action.ToLowerInvariant()
$composeArgs = Get-ComposeBaseArgs

switch ($normalizedAction) {
    'help' {
        Show-Usage
        exit 0
    }
    '-h' {
        Show-Usage
        exit 0
    }
    '--help' {
        Show-Usage
        exit 0
    }
    'up' {
        $composeArgs += @('up', '-d')
        $composeArgs += $ExtraArgs
    }
    'down' {
        $composeArgs += @('down')
        $composeArgs += $ExtraArgs
    }
    'restart' {
        $composeArgs += @('restart', $defaultLogService)
        $composeArgs += $ExtraArgs
    }
    'logs' {
        $composeArgs += @('logs', '-f', $defaultLogService)
        $composeArgs += $ExtraArgs
    }
    'ps' {
        $composeArgs += @('ps')
        $composeArgs += $ExtraArgs
    }
    'pull' {
        $composeArgs += @('pull', $defaultLogService)
        $composeArgs += $ExtraArgs
    }
    default {
        Write-Host "不支持的操作: $Action" -ForegroundColor Red
        Show-Usage
        exit 1
    }
}

Invoke-DockerCompose -ComposeArgs $composeArgs
