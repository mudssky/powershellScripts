[CmdletBinding()]
param(
    # 默认执行 up，对齐“直接运行脚本即可启动”的现有使用习惯。
    [string]$Action = 'up',

    # 透传少量 compose 原生命令参数，避免为日志条数等小需求再扩脚本分支。
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$composeFile = Join-Path $scriptDir 'compose.yaml'
$envFile = '.env.local'

function Show-Usage {
    <#
    .SYNOPSIS
    输出 LiteLLM compose 包装脚本的用法说明。
    #>
    @'
用法:
  ./start.ps1 [up|down|restart|logs|ps|pull] [额外 compose 参数]

默认行为:
  ./start.ps1         -> docker compose up -d
  ./start.ps1 logs    -> docker compose logs -f litellm

示例:
  ./start.ps1
  ./start.ps1 restart
  ./start.ps1 logs --tail 100
  ./start.ps1 pull
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
        Write-Warning "未找到环境变量文件: $envFile。脚本会继续执行，但 NEWAPI_* 与 LITELLM_MASTER_KEY 可能为空。"
    }
}

function Get-ComposeBaseArgs {
    <#
    .SYNOPSIS
    生成统一的 compose 基础参数。
    .OUTPUTS
    System.String[]
    返回 `docker` 后续应接收的 compose 参数数组。
    #>
    $args = @(
        'compose'
        '-f'
        $composeFile
        '--project-directory'
        $scriptDir
    )

    # `--env-file` 既用于 compose 插值，也用于让文档中的原生命令与脚本行为保持一致。
    if (Test-Path -LiteralPath $envFile) {
        $args += @('--env-file', $envFile)
    }

    return $args
}

function Invoke-DockerCompose {
    <#
    .SYNOPSIS
    以统一参数调用 docker compose，并把底层退出码透传给调用方。
    .PARAMETER ComposeArgs
    compose 子命令参数，不包含最前面的 `docker`。
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
        $composeArgs += @('restart', 'litellm')
        $composeArgs += $ExtraArgs
    }
    'logs' {
        # 默认跟随单个 LiteLLM 服务日志，符合最常见的排查场景。
        $composeArgs += @('logs', '-f', 'litellm')
        $composeArgs += $ExtraArgs
    }
    'ps' {
        $composeArgs += @('ps')
        $composeArgs += $ExtraArgs
    }
    'pull' {
        $composeArgs += @('pull', 'litellm')
        $composeArgs += $ExtraArgs
    }
    default {
        Write-Host "不支持的操作: $Action" -ForegroundColor Red
        Show-Usage
        exit 1
    }
}

Invoke-DockerCompose -ComposeArgs $composeArgs
