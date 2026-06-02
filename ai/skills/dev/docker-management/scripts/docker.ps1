#requires -Version 5.1
<#
.SYNOPSIS
    WSL Docker wrapper 的透明 docker shim。

.DESCRIPTION
    该脚本用于放入 PATH 后接管 `docker ...` 命令形态，并把所有参数转发给同目录的
    Invoke-WslDocker.ps1。适合 Docker Desktop 迁移到纯 WSL Docker Engine 后，
    让 Windows PowerShell 中原来的 `docker run`、`docker compose` 等命令继续可用。

.PARAMETER DockerArgs
    传给 docker 的全部参数。

.OUTPUTS
    None。直接透传 WSL 内 docker 的 stdout/stderr，并使用 docker 退出码结束。

.EXAMPLE
    docker run --rm alpine:3.20 echo ok

.EXAMPLE
    docker compose -f .\docker-compose.yml config
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$DockerArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$invokeScript = Join-Path $PSScriptRoot 'Invoke-WslDocker.ps1'
& $invokeScript @DockerArgs
exit $LASTEXITCODE
