Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AdapterSupport.psm1') -Force

function Get-DockerPackageSourcePath {
    <#
    .SYNOPSIS
        返回当前平台的 Docker daemon 配置路径。

    .OUTPUTS
        string。daemon.json 路径。
    #>
    [CmdletBinding()]
    param()

    $overridePath = [Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_DOCKER_DAEMON_PATH', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($overridePath)) {
        return [System.IO.Path]::GetFullPath($overridePath)
    }
    if ($IsLinux) {
        return '/etc/docker/daemon.json'
    }
    if ($IsWindows) {
        $programData = [Environment]::GetEnvironmentVariable('ProgramData', 'Process')
        if (-not [string]::IsNullOrWhiteSpace($programData)) {
            return Join-Path $programData 'Docker/config/daemon.json'
        }
    }
    return Join-Path $HOME '.docker/daemon.json'
}

function Test-DockerPackageSourceUrl {
    <#
    .SYNOPSIS
        通过 Docker Registry V2 端点测试镜像。

    .DESCRIPTION
        接受 200 与 401；HEAD 失败后尝试 GET，并返回耗时与错误摘要。

    .PARAMETER Url
        HTTPS 镜像基础 URL。

    .PARAMETER TimeoutSeconds
        单次请求超时秒数。

    .PARAMETER Retry
        首次失败后的重试次数。

    .OUTPUTS
        PSCustomObject。包含 Url、Success、StatusCode、ElapsedMs 与 Error。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [ValidateRange(1, 60)]
        [int]$TimeoutSeconds = 5,

        [ValidateRange(0, 5)]
        [int]$Retry = 1
    )

    $safeUrl = ConvertTo-SafePackageSourceUrl -Value $Url
    $probeUrl = $safeUrl.TrimEnd('/') + '/v2/'
    $lastError = ''
    for ($attempt = 0; $attempt -le $Retry; $attempt++) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($method in @('Head', 'Get')) {
            try {
                $response = Invoke-WebRequest -Uri $probeUrl -Method $method -TimeoutSec $TimeoutSeconds -ErrorAction Stop
                $stopwatch.Stop()
                $statusCode = [int]$response.StatusCode
                if ($statusCode -in @(200, 401)) {
                    return [PSCustomObject]@{
                        Url        = $safeUrl.TrimEnd('/')
                        Success    = $true
                        StatusCode = $statusCode
                        ElapsedMs  = [int]$stopwatch.ElapsedMilliseconds
                        Error      = ''
                    }
                }
            }
            catch {
                $lastError = $_.Exception.Message
                $responseStatus = if (
                    $_.Exception.PSObject.Properties.Name -contains 'Response' -and
                    $null -ne $_.Exception.Response -and
                    $_.Exception.Response.PSObject.Properties.Name -contains 'StatusCode'
                ) {
                    $_.Exception.Response.StatusCode
                }
                else {
                    $null
                }
                if ($null -ne $responseStatus -and [int]$responseStatus -eq 401) {
                    $stopwatch.Stop()
                    return [PSCustomObject]@{
                        Url        = $safeUrl.TrimEnd('/')
                        Success    = $true
                        StatusCode = 401
                        ElapsedMs  = [int]$stopwatch.ElapsedMilliseconds
                        Error      = ''
                    }
                }
            }
        }
        $stopwatch.Stop()
    }

    return [PSCustomObject]@{
        Url        = $safeUrl.TrimEnd('/')
        Success    = $false
        StatusCode = 0
        ElapsedMs  = 0
        Error      = $lastError
    }
}

function Select-DockerPackageSourceMirror {
    <#
    .SYNOPSIS
        选择可用 Docker 镜像并按响应时间排序。

    .PARAMETER MirrorUrl
        候选 HTTPS 镜像。

    .PARAMETER TimeoutSeconds
        单次请求超时秒数。

    .PARAMETER Retry
        首次失败后的重试次数。

    .OUTPUTS
        PSCustomObject。包含 Urls 与 Results。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$MirrorUrl,

        [int]$TimeoutSeconds = 5,

        [int]$Retry = 1
    )

    $results = @($MirrorUrl | ForEach-Object {
            Test-DockerPackageSourceUrl -Url $_ -TimeoutSeconds $TimeoutSeconds -Retry $Retry
        })
    $available = @($results | Where-Object Success | Sort-Object ElapsedMs, Url)
    return [PSCustomObject]@{
        Urls    = @($available | Select-Object -ExpandProperty Url)
        Results = $results
    }
}

function Invoke-DockerPackageSourceRestart {
    <#
    .SYNOPSIS
        在支持的平台重启 Docker 引擎。

    .DESCRIPTION
        Linux 优先 systemctl，失败后尝试 service；Docker Desktop 平台只返回人工提示。

    .OUTPUTS
        string。重启结果或提示。
    #>
    [CmdletBinding()]
    param()

    if ([Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_SKIP_DOCKER_RESTART', 'Process') -eq '1') {
        return '测试环境已跳过 Docker 重启'
    }
    if ([Environment]::GetEnvironmentVariable('POWERSHELL_SCRIPTS_DOCKER_RESTART_FAIL', 'Process') -eq '1') {
        throw (New-PackageSourceAdapterException -Message '模拟 Docker 重启失败' -ExitCode 10 -Code 'Blocked')
    }
    if (-not $IsLinux) {
        return '请通过 Docker Desktop 重启 Docker 引擎以应用配置'
    }

    $systemctl = Get-Command systemctl -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $systemctl) {
        $reload = Invoke-PackageSourceProcess -FilePath $systemctl.Source -ArgumentList @('daemon-reload')
        $restart = Invoke-PackageSourceProcess -FilePath $systemctl.Source -ArgumentList @('restart', 'docker')
        if ($reload.ExitCode -eq 0 -and $restart.ExitCode -eq 0) {
            return 'Docker 已通过 systemctl 重启'
        }
    }

    $service = Get-Command service -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $service) {
        $restart = Invoke-PackageSourceProcess -FilePath $service.Source -ArgumentList @('docker', 'restart')
        if ($restart.ExitCode -eq 0) {
            return 'Docker 已通过 service 重启'
        }
    }

    throw (New-PackageSourceAdapterException -Message 'Docker 配置已写入，但自动重启失败' -ExitCode 10 -Code 'Blocked')
}

function Invoke-DockerPackageSourceApply {
    <#
    .SYNOPSIS
        写入经过探活的 Docker registry mirrors。

    .PARAMETER MirrorUrl
        候选镜像 URL；未提供时由 catalog 传入默认值。

    .PARAMETER TimeoutSeconds
        探活超时秒数。

    .PARAMETER Retry
        探活重试次数。

    .OUTPUTS
        PSCustomObject。包含 Source、Changed、ChsrcVersion 与 Message。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$MirrorUrl,

        [int]$TimeoutSeconds = 5,

        [int]$Retry = 1
    )

    $selection = Select-DockerPackageSourceMirror -MirrorUrl $MirrorUrl -TimeoutSeconds $TimeoutSeconds -Retry $Retry
    if ($selection.Urls.Count -eq 0) {
        throw (New-PackageSourceAdapterException -Message '所有 Docker 镜像均不可用，保持原配置' -ExitCode 10 -Code 'Blocked')
    }

    $path = Get-DockerPackageSourcePath
    $config = @{}
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        }
        catch {
            throw "解析 Docker daemon.json 失败: $($_.Exception.Message)"
        }
    }
    $currentUrls = @($config['registry-mirrors'])
    $changed = (ConvertTo-Json $currentUrls -Compress) -cne (ConvertTo-Json $selection.Urls -Compress)
    if ($changed) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $backupPath = '{0}.{1}.bak' -f $path, (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff')
            Copy-Item -LiteralPath $path -Destination $backupPath
            Set-PackageSourceFileMode -Path $backupPath -Mode ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
        }
        $config['registry-mirrors'] = @($selection.Urls)
        $json = $config | ConvertTo-Json -Depth 20
        $null = Write-PackageSourceTextAtomic -Path $path -Value $json
        $null = Invoke-DockerPackageSourceRestart
    }

    return [PSCustomObject]@{
        Source       = $selection.Urls[0]
        Changed      = $changed
        ChsrcVersion = ''
        Message      = if ($changed) { 'Docker registry mirrors 已更新' } else { 'Docker registry mirrors 已满足' }
    }
}

Export-ModuleMember -Function @(
    'Get-DockerPackageSourcePath'
    'Test-DockerPackageSourceUrl'
    'Select-DockerPackageSourceMirror'
    'Invoke-DockerPackageSourceApply'
    'Invoke-DockerPackageSourceRestart'
)
