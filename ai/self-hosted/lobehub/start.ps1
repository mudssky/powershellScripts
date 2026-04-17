[CmdletBinding()]
param(
    [ValidateSet('start', 'restart', 'update', 'status', 'logs', 'stop', 'down')]
    [string]$Action = 'start',

    [string]$Service = 'lobe',

    [ValidateSet('external', 'internal')]
    [string]$Mode = 'external',

    [switch]$NoUpdate
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InternalComposeFile = 'docker-compose.with-internal-db.yml'
$InternalEnvFile = '.env.with-internal-services'

function Get-ComposeArgs {
    param(
        [string]$SelectedMode
    )

    if ($SelectedMode -eq 'internal') {
        return @('-f', $InternalComposeFile, '--env-file', $InternalEnvFile)
    }

    return @()
}

function Invoke-Compose {
    param(
        [string[]]$ComposeSubcommandArgs
    )

    $ComposeArgs = Get-ComposeArgs -SelectedMode $Mode
    & docker compose @ComposeArgs @ComposeSubcommandArgs
}

Set-Location $ScriptDir

switch ($Action) {
    'start' {
        Write-Host "正在启动服务: $Service (mode=$Mode) ..."
        Invoke-Compose -ComposeSubcommandArgs @('up', '-d', '--no-attach', $Service)
    }

    'restart' {
        Write-Host "正在重启服务: $Service (mode=$Mode) ..."
        Invoke-Compose -ComposeSubcommandArgs @('restart', $Service)
    }

    'update' {
        if ($NoUpdate) {
            Write-Host '已指定 -NoUpdate，跳过拉取镜像，仅重新部署服务。'
            if ($Service -eq 'all') {
                Invoke-Compose -ComposeSubcommandArgs @('up', '-d', '--remove-orphans')
            }
            else {
                Invoke-Compose -ComposeSubcommandArgs @('up', '-d', '--always-recreate-deps', '--no-attach', $Service)
            }
            break
        }

        if ($Service -eq 'all') {
            Write-Host "正在更新所有服务镜像 (mode=$Mode) ..."
            Invoke-Compose -ComposeSubcommandArgs @('pull')
            Write-Host "正在重新部署所有服务 (mode=$Mode) ..."
            Invoke-Compose -ComposeSubcommandArgs @('up', '-d', '--remove-orphans')
        }
        else {
            Write-Host "正在更新服务镜像及其相关依赖: $Service (mode=$Mode) ..."
            Invoke-Compose -ComposeSubcommandArgs @('pull', '--include-deps', $Service)
            Write-Host "正在重新部署服务及其相关依赖: $Service (mode=$Mode) ..."
            Invoke-Compose -ComposeSubcommandArgs @('up', '-d', '--always-recreate-deps', '--no-attach', $Service)
        }
    }

    'status' {
        Invoke-Compose -ComposeSubcommandArgs @('ps')
    }

    'logs' {
        Write-Host "正在查看日志: $Service (mode=$Mode, Ctrl+C 退出)..."
        Invoke-Compose -ComposeSubcommandArgs @('logs', '-f', '--tail=200', $Service)
    }

    'stop' {
        Write-Host "正在停止服务: $Service (mode=$Mode) ..."
        Invoke-Compose -ComposeSubcommandArgs @('stop', $Service)
    }

    'down' {
        Write-Host "正在移除当前模式下的所有服务 (mode=$Mode) ..."
        Invoke-Compose -ComposeSubcommandArgs @('down')
    }
}
