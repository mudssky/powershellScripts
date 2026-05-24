<#
.SYNOPSIS
    解析 Linux `/proc/meminfo`。

.DESCRIPTION
    将 kB 单位的 meminfo 字段转换为系统层内存报告。

.PARAMETER Lines
    `/proc/meminfo` 的文本行。

.OUTPUTS
    PSCustomObject
    返回 Linux 系统层内存指标。
#>
function ConvertFrom-LinuxMemInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines
    )

    $values = @{}
    foreach ($line in $Lines) {
        $match = [regex]::Match($line, '^([^:]+):\s+(\d+)\s+kB')
        if ($match.Success) {
            $values[$match.Groups[1].Value] = [double]$match.Groups[2].Value
        }
    }

    $totalKB = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $values -Name 'MemTotal' -DefaultValue 0)
    $availableKB = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $values -Name 'MemAvailable' -DefaultValue 0)
    if ($availableKB -le 0) {
        $availableKB =
            [double](Get-MemoryDiagnosticsPropertyValue -InputObject $values -Name 'MemFree' -DefaultValue 0) +
            [double](Get-MemoryDiagnosticsPropertyValue -InputObject $values -Name 'Buffers' -DefaultValue 0) +
            [double](Get-MemoryDiagnosticsPropertyValue -InputObject $values -Name 'Cached' -DefaultValue 0)
    }

    $swapTotalKB = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $values -Name 'SwapTotal' -DefaultValue 0)
    $swapFreeKB = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $values -Name 'SwapFree' -DefaultValue 0)
    $committedKB = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $values -Name 'Committed_AS' -DefaultValue 0)
    $commitLimitKB = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $values -Name 'CommitLimit' -DefaultValue 0)

    return [pscustomobject]@{
        platform          = 'Linux'
        source            = '/proc/meminfo'
        totalPhysicalGB   = [math]::Round($totalKB / 1MB, 2)
        availableGB       = [math]::Round($availableKB / 1MB, 2)
        usedPhysicalGB    = [math]::Round(($totalKB - $availableKB) / 1MB, 2)
        availablePercent  = ConvertTo-MemoryDiagnosticsPercent -Numerator $availableKB -Denominator $totalKB
        swapTotalGB       = [math]::Round($swapTotalKB / 1MB, 2)
        swapFreeGB        = [math]::Round($swapFreeKB / 1MB, 2)
        swapUsedGB        = [math]::Round(($swapTotalKB - $swapFreeKB) / 1MB, 2)
        commitCommittedGB = [math]::Round($committedKB / 1MB, 2)
        commitLimitGB     = [math]::Round($commitLimitKB / 1MB, 2)
        commitPercent     = ConvertTo-MemoryDiagnosticsPercent -Numerator $committedKB -Denominator $commitLimitKB
    }
}

<#
.SYNOPSIS
    获取 Linux 系统层内存快照。

.DESCRIPTION
    优先读取 `/proc/meminfo`，失败时返回 warning 和最小对象。

.OUTPUTS
    PSCustomObject
    返回 `System` 与 `Warnings`。
#>
function Get-LinuxMemorySystemSnapshot {
    [CmdletBinding()]
    param()

    try {
        return [pscustomobject]@{
            System   = ConvertFrom-LinuxMemInfo -Lines (Get-Content -LiteralPath '/proc/meminfo' -ErrorAction Stop)
            Warnings = @()
        }
    }
    catch {
        return [pscustomobject]@{
            System   = [pscustomobject]@{
                platform = 'Linux'
                source   = '/proc/meminfo-failed'
            }
            Warnings = @(
                New-MemoryDiagnosticsWarning `
                    -Code 'linux.meminfo_failed' `
                    -Source 'linux' `
                    -Message 'Linux /proc/meminfo 读取失败。' `
                    -Details @{ error = $_.Exception.Message }
            )
        }
    }
}

<#
.SYNOPSIS
    获取 Linux Top 内存进程。

.DESCRIPTION
    使用 `ps -eo pid,ppid,comm,rss,vsz,pmem --sort=-rss` 采集 RSS/VSZ。

.PARAMETER Top
    返回的进程数量。

.OUTPUTS
    PSCustomObject
    返回 `Processes` 与 `Warnings`。
#>
function Get-LinuxTopMemoryProcesses {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 500)]
        [int]$Top = 30
    )

    try {
        $lines = @(ps -eo pid,ppid,comm,rss,vsz,pmem --sort=-rss 2>$null | Select-Object -Skip 1 -First $Top)
        $processes = foreach ($line in $lines) {
            ConvertFrom-MemoryDiagnosticsPsLine -Line ([string]$line) -Source 'linux-ps'
        }

        return [pscustomobject]@{
            Processes = @($processes | Where-Object { $null -ne $_ })
            Warnings  = @()
        }
    }
    catch {
        $fallback = Get-GenericTopMemoryProcesses -Top $Top -Source 'linux-get-process-fallback'
        $fallback.Warnings += New-MemoryDiagnosticsWarning `
            -Code 'linux.ps_failed' `
            -Source 'linux' `
            -Message 'Linux ps 采集失败，已回退到 Get-Process。' `
            -Details @{ error = $_.Exception.Message }
        return $fallback
    }
}

<#
.SYNOPSIS
    获取 Linux 平台快照。

.DESCRIPTION
    汇总 Linux 系统层内存，Windows 专属字段固定为空。

.PARAMETER Depth
    采集深度；Linux 第一版暂不区分。

.OUTPUTS
    PSCustomObject
    返回 `System`、`WindowsOnly` 与 `Warnings`。
#>
function Get-LinuxPlatformSnapshot {
    [CmdletBinding()]
    param(
        [ValidateSet('basic', 'full')]
        [string]$Depth = 'full'
    )

    $null = $Depth
    $systemSnapshot = Get-LinuxMemorySystemSnapshot
    return [pscustomobject]@{
        System      = $systemSnapshot.System
        WindowsOnly = $null
        Warnings    = @($systemSnapshot.Warnings)
    }
}
