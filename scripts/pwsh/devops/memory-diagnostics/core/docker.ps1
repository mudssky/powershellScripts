<#
.SYNOPSIS
    将 Docker 内存字符串转换为 MB。

.DESCRIPTION
    支持 Docker stats 常见的 B、KiB、MiB、GiB、TiB、KB、MB、GB、TB 单位。

.PARAMETER Value
    Docker 输出的内存字符串。

.OUTPUTS
    double
    返回 MB；无法解析时返回 `$null`。
#>
function ConvertFrom-DockerMemorySize {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $match = [regex]::Match($Value.Trim(), '^(?<number>[\d\.,]+)\s*(?<unit>[kmgtKMGT]?i?[bB]|[bB])?$')
    if (-not $match.Success) {
        return $null
    }

    $number = [double]($match.Groups['number'].Value -replace ',', '.')
    $unit = $match.Groups['unit'].Value.ToLowerInvariant()

    switch ($unit) {
        'b' { return [math]::Round($number / 1MB, 2) }
        { $_ -in @('kb', 'kib') } { return [math]::Round($number / 1024, 2) }
        { $_ -in @('mb', 'mib', '') } { return [math]::Round($number, 2) }
        { $_ -in @('gb', 'gib') } { return [math]::Round($number * 1024, 2) }
        { $_ -in @('tb', 'tib') } { return [math]::Round($number * 1024 * 1024, 2) }
        default { return $null }
    }
}

<#
.SYNOPSIS
    解析 Docker memory usage 字段。

.DESCRIPTION
    Docker stats 的 `MemUsage` 通常是 `usage / limit`，该函数拆分为使用量和限制。

.PARAMETER Value
    Docker `MemUsage` 字符串。

.OUTPUTS
    PSCustomObject
    返回 `UsageMB`、`LimitMB` 与原始字符串。
#>
function ConvertFrom-DockerMemoryUsage {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    $parts = @([string]$Value -split '/', 2)
    $usage = if ($parts.Count -ge 1) { ConvertFrom-DockerMemorySize -Value $parts[0].Trim() } else { $null }
    $limit = if ($parts.Count -ge 2) { ConvertFrom-DockerMemorySize -Value $parts[1].Trim() } else { $null }

    return [pscustomobject]@{
        UsageMB = $usage
        LimitMB = $limit
        Raw     = $Value
    }
}

<#
.SYNOPSIS
    解析 Docker stats JSON 行。

.DESCRIPTION
    将 `docker stats --format '{{json .}}'` 的单行输出转换为标准容器内存对象。

.PARAMETER Line
    Docker stats JSON 行。

.OUTPUTS
    PSCustomObject
    返回标准容器内存对象。
#>
function ConvertFrom-DockerStatsJsonLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Line
    )

    $item = $Line | ConvertFrom-Json
    $memoryUsage = ConvertFrom-DockerMemoryUsage -Value ([string](Get-MemoryDiagnosticsPropertyValue -InputObject $item -Name 'MemUsage' -DefaultValue ''))
    $memoryPercentText = [string](Get-MemoryDiagnosticsPropertyValue -InputObject $item -Name 'MemPerc' -DefaultValue '')
    $memoryPercent = if ([string]::IsNullOrWhiteSpace($memoryPercentText)) {
        $null
    }
    else {
        [math]::Round([double]($memoryPercentText -replace '%', '' -replace ',', '.'), 2)
    }

    return [pscustomobject]@{
        containerId     = Get-MemoryDiagnosticsPropertyValue -InputObject $item -Name 'Container' -DefaultValue (Get-MemoryDiagnosticsPropertyValue -InputObject $item -Name 'ID' -DefaultValue '')
        name            = Get-MemoryDiagnosticsPropertyValue -InputObject $item -Name 'Name' -DefaultValue ''
        memoryUsageMB   = $memoryUsage.UsageMB
        memoryLimitMB   = $memoryUsage.LimitMB
        memoryPercent   = $memoryPercent
        rawMemoryUsage  = $memoryUsage.Raw
        rawMemoryPerc   = $memoryPercentText
        source          = 'docker-stats'
    }
}

<#
.SYNOPSIS
    获取 Docker 容器内存快照。

.DESCRIPTION
    Docker 不存在、daemon 未启动或 stats 失败时返回结构化状态和 warning，不中断主报告。

.OUTPUTS
    PSCustomObject
    返回容器内存快照。
#>
function Get-DockerMemorySnapshot {
    [CmdletBinding()]
    param()

    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $dockerCommand) {
        $warning = New-MemoryDiagnosticsWarning `
            -Code 'docker.command_missing' `
            -Source 'docker' `
            -Message '未找到 docker 命令，跳过容器内存采集。'

        return [pscustomobject]@{
            available     = $false
            status        = 'command_missing'
            totalMemoryMB = 0
            items         = @()
            warnings      = @($warning)
        }
    }

    try {
        $output = @(& $dockerCommand.Source stats --no-stream --format '{{json .}}' 2>&1)
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            $warning = New-MemoryDiagnosticsWarning `
                -Code 'docker.stats_failed' `
                -Source 'docker' `
                -Message 'docker stats 执行失败，可能是 Docker daemon 未运行。' `
                -Details @{ exitCode = $exitCode; output = ($output -join [Environment]::NewLine) }

            return [pscustomobject]@{
                available     = $false
                status        = 'stats_failed'
                totalMemoryMB = 0
                items         = @()
                warnings      = @($warning)
            }
        }

        $warnings = @()
        $items = foreach ($line in $output) {
            if ([string]::IsNullOrWhiteSpace([string]$line)) {
                continue
            }

            try {
                ConvertFrom-DockerStatsJsonLine -Line ([string]$line)
            }
            catch {
                $warnings += New-MemoryDiagnosticsWarning `
                    -Code 'docker.stats_parse_failed' `
                    -Source 'docker' `
                    -Message 'Docker stats 单行输出解析失败。' `
                    -Details @{ line = [string]$line; error = $_.Exception.Message }
            }
        }

        $totalMemoryMB = 0.0
        foreach ($item in @($items)) {
            $memoryUsageMB = Get-MemoryDiagnosticsPropertyValue -InputObject $item -Name 'memoryUsageMB' -DefaultValue 0
            if ($null -ne $memoryUsageMB) {
                $totalMemoryMB += [double]$memoryUsageMB
            }
        }

        $totalMemoryMB = [math]::Round($totalMemoryMB, 2)
        $status = if (@($items).Count -eq 0) { 'available_no_containers' } else { 'available' }

        return [pscustomobject]@{
            available     = $true
            status        = $status
            totalMemoryMB = $totalMemoryMB
            items         = @($items)
            warnings      = @($warnings)
        }
    }
    catch {
        $warning = New-MemoryDiagnosticsWarning `
            -Code 'docker.snapshot_failed' `
            -Source 'docker' `
            -Message 'Docker 容器内存采集异常。' `
            -Details @{ error = $_.Exception.Message }

        return [pscustomobject]@{
            available     = $false
            status        = 'snapshot_failed'
            totalMemoryMB = 0
            items         = @()
            warnings      = @($warning)
        }
    }
}
