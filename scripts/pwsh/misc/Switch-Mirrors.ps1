#!/usr/bin/env pwsh

<#
.SYNOPSIS
    通用换源脚本（首期支持 Docker），在写入前对镜像源进行连通性与基本可用性测试。

.DESCRIPTION
    为多个软件提供换源能力的统一入口，当前实现 Docker 镜像仓库加速：
    - 在写入 `daemon.json` 前，对候选镜像源执行 HTTP 探活（`/v2/`）
    - 接受 `200/401` 的返回码（401 表示需要认证，视为仓库在线）
    - 选择最快可用镜像写入并备份原配置，支持 Dry-Run 与快速禁用
    - Linux 自动重启 Docker；其他平台给出重启指引

.PARAMETER Target
    目标软件，目前支持 `docker`

.PARAMETER MirrorUrls
    候选镜像源列表（如：`https://docker.xuanyuan.me`）。若未提供并启用 `-UseChinaMirror`，将使用内置默认值。

.PARAMETER UseChinaMirror
    快捷启用中国区域默认镜像源（当未显式提供 `MirrorUrls` 时生效）。

.PARAMETER Disable
    移除已配置的镜像源（写入后需要重启 Docker 生效）。

.PARAMETER TimeoutSec
    单个镜像探活的超时时间（秒），默认 `5`。

.PARAMETER Retry
    探活失败时的重试次数，默认 `1`。

.PARAMETER DryRun
    仅输出计划与将写入的内容，不进行实际写入与重启。

.EXAMPLE
    # 自动选择最快可用的中国镜像源并写入（DryRun）
    ./Switch-Mirrors.ps1 -Target docker -UseChinaMirror -DryRun

.EXAMPLE
    # 指定镜像列表，测试后择优写入
    ./Switch-Mirrors.ps1 -Target docker -MirrorUrls "https://docker.xuanyuan.me","https://registry-1.docker.io" 

.EXAMPLE
    # 移除镜像源（Linux 会自动重启 Docker）
    ./Switch-Mirrors.ps1 -Target docker -Disable

.NOTES
    - 需要 PowerShell 7+（跨平台）
    - 写入前会备份 `daemon.json` 为 `daemon.json.bak.<timestamp>`
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('docker')]
    [string]$Target,

    [string[]]$MirrorUrls,
    [switch]$UseChinaMirror,
    [switch]$Disable,
    [int]$TimeoutSec = 5,
    [int]$Retry = 1,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DockerDaemonPath {
    if ($IsLinux) { return '/etc/docker/daemon.json' }
    if ($IsWindows) {
        $paths = @(
            (Join-Path $env:ProgramData 'Docker\config\daemon.json'),
            (Join-Path $env:USERPROFILE '.docker\daemon.json')
        )
        foreach ($p in $paths) { if ($p) { return $p } }
    }
    if ($IsMacOS) { return (Join-Path $HOME '.docker/daemon.json') }
    return '/etc/docker/daemon.json'
}

function Invoke-DockerRestart {
    param([switch]$DryRun)
    if ($IsLinux) {
        if ($DryRun) { Write-Output '将执行: systemctl daemon-reload && systemctl restart docker'; return }
        try { & systemctl daemon-reload *> $null } catch {}
        try { & systemctl restart docker } catch { try { & service docker restart } catch {} }
        return
    }
    Write-Output '请通过 Docker Desktop 重启 Docker 引擎以应用配置'
}

function Test-MirrorUrl {
    <#
    .SYNOPSIS
        测试 Docker 仓库镜像源的可达性与基本可用性。
    .DESCRIPTION
        以 `/v2/` 端点进行探活，接受 `200/401` 状态码作为有效。
    .PARAMETER Url
        镜像源基础地址。
    .PARAMETER TimeoutSec
        超时时间（秒）。
    .PARAMETER Retry
        重试次数。
    .OUTPUTS
        PSCustomObject: { Url, Success, StatusCode, ElapsedMs, Error }
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutSec = 5,
        [int]$Retry = 1
    )
    $probe = ($Url.TrimEnd('/') + '/v2/')
    $attempt = 0
    $lastErr = $null
    while ($attempt -le $Retry) {
        $attempt++
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $resp = Invoke-WebRequest -Uri $probe -Method Head -TimeoutSec $TimeoutSec -ErrorAction Stop
            $sw.Stop()
            $code = $resp.StatusCode
            $ok = ($code -eq 200 -or $code -eq 401)
            if ($ok) { return [PSCustomObject]@{ Url = $Url; Success = $true; StatusCode = $code; ElapsedMs = [int]$sw.ElapsedMilliseconds; Error = '' } }
        }
        catch {
            $sw.Stop()
            $lastErr = $_.Exception.Message
            try {
                $resp2 = Invoke-WebRequest -Uri $probe -Method Get -TimeoutSec $TimeoutSec -ErrorAction Stop
                $code2 = $resp2.StatusCode
                $ok2 = ($code2 -eq 200 -or $code2 -eq 401)
                if ($ok2) { return [PSCustomObject]@{ Url = $Url; Success = $true; StatusCode = $code2; ElapsedMs = [int]$sw.ElapsedMilliseconds; Error = '' } }
            }
            catch { $lastErr = $_.Exception.Message }
        }
        Start-Sleep -Milliseconds 200
    }
    return [PSCustomObject]@{ Url = $Url; Success = $false; StatusCode = 0; ElapsedMs = 0; Error = ($lastErr ?? '') }
}

function Select-BestMirror {
    <#
    .SYNOPSIS
        从候选镜像源中选择最快的可用项。
    .DESCRIPTION
        对每个镜像执行 `Test-MirrorUrl` 并按耗时升序选择。
    .PARAMETER MirrorUrls
        候选镜像源列表。
    .PARAMETER TimeoutSec
        探活超时（秒）。
    .PARAMETER Retry
        重试次数。
    .OUTPUTS
        PSCustomObject: { BestUrl, Results }
    #>
    param(
        [string[]]$MirrorUrls,
        [int]$TimeoutSec = 5,
        [int]$Retry = 1
    )
    if (-not $MirrorUrls -or $MirrorUrls.Count -eq 0) {
        return [PSCustomObject]@{ BestUrl = ''; Results = @() }
    }
    $results = @()
    foreach ($u in $MirrorUrls) {
        $r = Test-MirrorUrl -Url $u -TimeoutSec $TimeoutSec -Retry $Retry
        $results += $r
    }
    $okList = @($results | Where-Object { $_.Success })
    if ($okList.Count -gt 0) {
        $best = ($okList | Sort-Object ElapsedMs | Select-Object -First 1)
        return [PSCustomObject]@{ BestUrl = $best.Url; Results = $results }
    }
    return [PSCustomObject]@{ BestUrl = ''; Results = $results }
}

function Set-DockerRegistryMirror {
    <#
    .SYNOPSIS
        写入 Docker 镜像源到 `daemon.json`，支持备份与 Dry-Run。
    .DESCRIPTION
        当 `-Disable` 为真时移除镜像源配置；否则根据 `MirrorUrls` 写入。
    .PARAMETER MirrorUrls
        镜像源列表（若为空且启用 `UseChinaMirror` 会填充默认）。
    .PARAMETER UseChinaMirror
        快捷使用中国镜像默认地址（空列表时生效）。
    .PARAMETER Disable
        移除镜像加速。
    .PARAMETER DryRun
        仅预览不执行。
    #>
    param(
        [string[]]$MirrorUrls,
        [switch]$UseChinaMirror,
        [switch]$Disable,
        [switch]$DryRun,
        [int]$TimeoutSec = 5,
        [int]$Retry = 1
    )
    $target = Get-DockerDaemonPath
    $dir = [System.IO.Path]::GetDirectoryName($target)
    if (-not [string]::IsNullOrWhiteSpace($dir)) { if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null } }

    $config = @{}
    if (Test-Path -LiteralPath $target) {
        try { $config = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json } catch { $config = @{} }
    }

    if ($Disable) {
        try { $config.PSObject.Properties.Remove('registry-mirrors') | Out-Null } catch {}
        $json = $config | ConvertTo-Json -Depth 10
        if ($DryRun) { Write-Output ("写入: " + $target); Write-Output $json; Invoke-DockerRestart -DryRun; return }
        $backup = ($target + '.bak.' + (Get-Date -Format 'yyyyMMddHHmmss'))
        if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination $backup -Force }
        Set-Content -LiteralPath $target -Value $json -Encoding utf8
        Invoke-DockerRestart
        return
    }

    if (-not $MirrorUrls -and $UseChinaMirror) { $MirrorUrls = @('https://docker.xuanyuan.me') }
    if (-not $MirrorUrls -or $MirrorUrls.Count -eq 0) { Write-Output '未提供镜像源，且未启用默认中国镜像；跳过写入'; return }

    $sel = Select-BestMirror -MirrorUrls $MirrorUrls -TimeoutSec $TimeoutSec -Retry $Retry
    $best = $sel.BestUrl
    $results = $sel.Results
    Write-Output ('镜像测试结果: ' + ($results | ForEach-Object { "[" + $_.Url + "] success=" + $_.Success + ", code=" + $_.StatusCode + ", ms=" + $_.ElapsedMs }) -join '; ')

    $okList = @($results | Where-Object { $_.Success })
    if ($okList.Count -eq 0) { Write-Output '所有候选镜像均不可用，保持原配置'; return }
    $ordered = @($okList | Sort-Object ElapsedMs | Select-Object -ExpandProperty Url)

    $config | Add-Member -MemberType NoteProperty -Name 'registry-mirrors' -Value $ordered -Force
    $json2 = $config | ConvertTo-Json -Depth 10
    if ($DryRun) { Write-Output ("写入: " + $target); Write-Output $json2; Invoke-DockerRestart -DryRun; return }

    $backup2 = ($target + '.bak.' + (Get-Date -Format 'yyyyMMddHHmmss'))
    if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination $backup2 -Force }
    Set-Content -LiteralPath $target -Value $json2 -Encoding utf8
    Invoke-DockerRestart
}

function Invoke-Main {
    if ($Target -ne 'docker') { throw '当前仅支持 Target=docker' }
    Set-DockerRegistryMirror -MirrorUrls $MirrorUrls -UseChinaMirror:$UseChinaMirror -Disable:$Disable -DryRun:$DryRun -TimeoutSec $TimeoutSec -Retry $Retry
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }
