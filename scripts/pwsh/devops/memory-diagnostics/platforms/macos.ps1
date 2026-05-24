<#
.SYNOPSIS
    将 macOS 内存字符串转换为 MB。

.DESCRIPTION
    解析 `vm.swapusage` 中的 M/G/T 单位，供 swap 字段使用。

.PARAMETER Value
    内存字符串。

.OUTPUTS
    double
    返回 MB；无法解析时返回 `$null`。
#>
function ConvertFrom-MacOSMemorySize {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $match = [regex]::Match($Value.Trim(), '^(?<number>[\d\.]+)(?<unit>[MGT])$')
    if (-not $match.Success) {
        return $null
    }

    $number = [double]$match.Groups['number'].Value
    switch ($match.Groups['unit'].Value) {
        'M' { return [math]::Round($number, 2) }
        'G' { return [math]::Round($number * 1024, 2) }
        'T' { return [math]::Round($number * 1024 * 1024, 2) }
        default { return $null }
    }
}

<#
.SYNOPSIS
    解析 macOS `vm_stat`。

.DESCRIPTION
    读取 page size、free、inactive、speculative、active、wired、compressed 等页面计数。

.PARAMETER Lines
    `vm_stat` 输出行。

.PARAMETER TotalBytes
    系统总内存字节数。

.OUTPUTS
    PSCustomObject
    返回 macOS 物理内存估算字段。
#>
function ConvertFrom-MacOSVmStat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [double]$TotalBytes
    )

    $pageSize = 4096
    $pages = @{}
    foreach ($line in $Lines) {
        $pageSizeMatch = [regex]::Match($line, 'page size of (\d+) bytes')
        if ($pageSizeMatch.Success) {
            $pageSize = [int]$pageSizeMatch.Groups[1].Value
            continue
        }

        $pageMatch = [regex]::Match($line, '^Pages\s+(.+?):\s+(\d+)\.')
        if ($pageMatch.Success) {
            $key = ($pageMatch.Groups[1].Value -replace '\s+', '_').ToLowerInvariant()
            $pages[$key] = [double]$pageMatch.Groups[2].Value
        }
    }

    $availablePages =
        [double](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'free' -DefaultValue 0) +
        [double](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'inactive' -DefaultValue 0) +
        [double](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'speculative' -DefaultValue 0)
    $availableBytes = $availablePages * $pageSize

    return [pscustomobject]@{
        totalPhysicalGB  = ConvertTo-MemoryDiagnosticsGB -Bytes $TotalBytes
        availableGB      = ConvertTo-MemoryDiagnosticsGB -Bytes $availableBytes
        usedPhysicalGB   = ConvertTo-MemoryDiagnosticsGB -Bytes ($TotalBytes - $availableBytes)
        availablePercent = ConvertTo-MemoryDiagnosticsPercent -Numerator $availableBytes -Denominator $TotalBytes
        pageSizeBytes    = $pageSize
    }
}

<#
.SYNOPSIS
    获取 macOS 系统层内存快照。

.DESCRIPTION
    使用 `sysctl`、`vm_stat` 和 `vm.swapusage` 采集 macOS 内存与 swap 状态。

.OUTPUTS
    PSCustomObject
    返回 `System` 与 `Warnings`。
#>
function Get-MacOSMemorySystemSnapshot {
    [CmdletBinding()]
    param()

    $warnings = @()
    try {
        $totalBytes = [double](sysctl -n hw.memsize)
        $vmStat = ConvertFrom-MacOSVmStat -Lines @(vm_stat) -TotalBytes $totalBytes
        $swapOutput = [string](sysctl vm.swapusage 2>$null)
        $swapTotalMB = $null
        $swapUsedMB = $null
        $swapFreeMB = $null
        $swapMatch = [regex]::Match($swapOutput, 'total\s+=\s+([^\s]+)\s+used\s+=\s+([^\s]+)\s+free\s+=\s+([^\s]+)')
        if ($swapMatch.Success) {
            $swapTotalMB = ConvertFrom-MacOSMemorySize -Value $swapMatch.Groups[1].Value
            $swapUsedMB = ConvertFrom-MacOSMemorySize -Value $swapMatch.Groups[2].Value
            $swapFreeMB = ConvertFrom-MacOSMemorySize -Value $swapMatch.Groups[3].Value
        }

        return [pscustomobject]@{
            System   = [pscustomobject]@{
                platform         = 'macOS'
                source           = 'sysctl-vm_stat'
                totalPhysicalGB  = $vmStat.totalPhysicalGB
                availableGB      = $vmStat.availableGB
                usedPhysicalGB   = $vmStat.usedPhysicalGB
                availablePercent = $vmStat.availablePercent
                swapTotalGB      = if ($null -eq $swapTotalMB) { $null } else { [math]::Round($swapTotalMB / 1024, 2) }
                swapUsedGB       = if ($null -eq $swapUsedMB) { $null } else { [math]::Round($swapUsedMB / 1024, 2) }
                swapFreeGB       = if ($null -eq $swapFreeMB) { $null } else { [math]::Round($swapFreeMB / 1024, 2) }
                pageSizeBytes    = $vmStat.pageSizeBytes
            }
            Warnings = @($warnings)
        }
    }
    catch {
        return [pscustomobject]@{
            System   = [pscustomobject]@{
                platform = 'macOS'
                source   = 'sysctl-vm_stat-failed'
            }
            Warnings = @(
                New-MemoryDiagnosticsWarning `
                    -Code 'macos.system_failed' `
                    -Source 'macos' `
                    -Message 'macOS 系统层内存指标采集失败。' `
                    -Details @{ error = $_.Exception.Message }
            )
        }
    }
}

<#
.SYNOPSIS
    获取 macOS Top 内存进程。

.DESCRIPTION
    使用 `ps -axo pid,ppid,comm,rss,vsz,%mem` 采集 RSS/VSZ。

.PARAMETER Top
    返回的进程数量。

.OUTPUTS
    PSCustomObject
    返回 `Processes` 与 `Warnings`。
#>
function Get-MacOSTopMemoryProcesses {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 500)]
        [int]$Top = 30
    )

    try {
        $lines = @(ps -axo pid,ppid,comm,rss,vsz,%mem 2>$null | Select-Object -Skip 1 | Sort-Object { [double](([regex]::Match($_, '([\d\.]+)\s*$')).Groups[1].Value) } -Descending | Select-Object -First $Top)
        $processes = foreach ($line in $lines) {
            ConvertFrom-MemoryDiagnosticsPsLine -Line ([string]$line) -Source 'macos-ps'
        }

        return [pscustomobject]@{
            Processes = @($processes | Where-Object { $null -ne $_ })
            Warnings  = @()
        }
    }
    catch {
        $fallback = Get-GenericTopMemoryProcesses -Top $Top -Source 'macos-get-process-fallback'
        $fallback.Warnings += New-MemoryDiagnosticsWarning `
            -Code 'macos.ps_failed' `
            -Source 'macos' `
            -Message 'macOS ps 采集失败，已回退到 Get-Process。' `
            -Details @{ error = $_.Exception.Message }
        return $fallback
    }
}

<#
.SYNOPSIS
    获取 macOS 平台快照。

.DESCRIPTION
    汇总 macOS 系统层内存，Windows 专属字段固定为空。

.PARAMETER Depth
    采集深度；macOS 第一版暂不区分。

.OUTPUTS
    PSCustomObject
    返回 `System`、`WindowsOnly` 与 `Warnings`。
#>
function Get-MacOSPlatformSnapshot {
    [CmdletBinding()]
    param(
        [ValidateSet('basic', 'full')]
        [string]$Depth = 'full'
    )

    $null = $Depth
    $systemSnapshot = Get-MacOSMemorySystemSnapshot
    return [pscustomobject]@{
        System      = $systemSnapshot.System
        WindowsOnly = $null
        Warnings    = @($systemSnapshot.Warnings)
    }
}
