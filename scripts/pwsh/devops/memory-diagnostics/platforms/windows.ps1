<#
.SYNOPSIS
    获取 Windows Top 内存进程。

.DESCRIPTION
    Windows 下使用 `Get-Process` 读取工作集、私有内存和虚拟内存。

.PARAMETER Top
    返回的进程数量。

.OUTPUTS
    PSCustomObject
    返回 `Processes` 与 `Warnings`。
#>
function Get-WindowsTopMemoryProcesses {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 500)]
        [int]$Top = 30
    )

    return Get-GenericTopMemoryProcesses -Top $Top -Source 'windows-get-process'
}

<#
.SYNOPSIS
    获取 Windows 系统层内存指标。

.DESCRIPTION
    使用 CIM 读取物理内存、commit、pagefile、paged pool 和 nonpaged pool。

.OUTPUTS
    PSCustomObject
    返回 `System` 与 `Warnings`。
#>
function Get-WindowsMemorySystemSnapshot {
    [CmdletBinding()]
    param()

    $warnings = @()
    try {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $perf = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop
        $pageFiles = @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction SilentlyContinue)

        $totalBytes = [double]$computer.TotalPhysicalMemory
        $availableBytes = [double]$perf.AvailableMBytes * 1MB
        $commitBytes = [double]$perf.CommittedBytes
        $commitLimitBytes = [double]$perf.CommitLimit
        $pagedPoolBytes = [double]$perf.PoolPagedBytes
        $nonPagedPoolBytes = [double]$perf.PoolNonpagedBytes
        $pageFileAllocatedMB = (@($pageFiles) | Measure-Object -Property AllocatedBaseSize -Sum).Sum
        $pageFileCurrentMB = (@($pageFiles) | Measure-Object -Property CurrentUsage -Sum).Sum

        return [pscustomobject]@{
            System   = [pscustomobject]@{
                platform          = 'Windows'
                source            = 'cim'
                totalPhysicalGB   = ConvertTo-MemoryDiagnosticsGB -Bytes $totalBytes
                availableGB       = ConvertTo-MemoryDiagnosticsGB -Bytes $availableBytes
                usedPhysicalGB    = ConvertTo-MemoryDiagnosticsGB -Bytes ($totalBytes - $availableBytes)
                availablePercent  = ConvertTo-MemoryDiagnosticsPercent -Numerator $availableBytes -Denominator $totalBytes
                commitCommittedGB = ConvertTo-MemoryDiagnosticsGB -Bytes $commitBytes
                commitLimitGB     = ConvertTo-MemoryDiagnosticsGB -Bytes $commitLimitBytes
                commitPercent     = ConvertTo-MemoryDiagnosticsPercent -Numerator $commitBytes -Denominator $commitLimitBytes
                pageFileTotalGB   = [math]::Round(([double]$pageFileAllocatedMB / 1024), 2)
                pageFileUsedGB    = [math]::Round(([double]$pageFileCurrentMB / 1024), 2)
                pagedPoolGB       = ConvertTo-MemoryDiagnosticsGB -Bytes $pagedPoolBytes
                nonPagedPoolGB    = ConvertTo-MemoryDiagnosticsGB -Bytes $nonPagedPoolBytes
                kernelPoolGB      = ConvertTo-MemoryDiagnosticsGB -Bytes ($pagedPoolBytes + $nonPagedPoolBytes)
            }
            Warnings = @($warnings)
        }
    }
    catch {
        return [pscustomobject]@{
            System   = [pscustomobject]@{
                platform = 'Windows'
                source   = 'cim-failed'
            }
            Warnings = @(
                New-MemoryDiagnosticsWarning `
                    -Code 'windows.system_failed' `
                    -Source 'windows' `
                    -Message 'Windows 系统层内存指标采集失败。' `
                    -Details @{ error = $_.Exception.Message }
            )
        }
    }
}

<#
.SYNOPSIS
    获取 Windows 驱动和服务线索。

.DESCRIPTION
    采集运行中系统驱动和服务摘要；权限不足时返回 warning，不影响主报告。

.PARAMETER Depth
    采集深度。basic 限制明细数量，full 返回更多条目。

.OUTPUTS
    PSCustomObject
    返回 `WindowsOnly` 与 `Warnings`。
#>
function Get-WindowsDriverServiceSnapshot {
    [CmdletBinding()]
    param(
        [ValidateSet('basic', 'full')]
        [string]$Depth = 'full'
    )

    $warnings = @()
    $driverItems = @()
    $serviceItems = @()
    $driverCount = 0
    $serviceCount = 0
    $driverLimit = if ($Depth -eq 'full') { 500 } else { 30 }
    $serviceLimit = if ($Depth -eq 'full') { 500 } else { 50 }

    try {
        $drivers = @(Get-CimInstance -ClassName Win32_SystemDriver -ErrorAction Stop | Where-Object { $_.State -eq 'Running' })
        $driverCount = $drivers.Count
        $driverItems = @(
            $drivers |
                Sort-Object -Property Name |
                Select-Object -First $driverLimit -Property Name, DisplayName, StartMode, State, PathName
        )
    }
    catch {
        $warnings += New-MemoryDiagnosticsWarning `
            -Code 'windows.drivers_failed' `
            -Source 'windows' `
            -Message '运行中系统驱动采集失败，可能需要更高权限或当前系统不支持该 CIM 类。' `
            -Details @{ error = $_.Exception.Message }
    }

    try {
        $services = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop | Where-Object { $_.State -eq 'Running' })
        $serviceCount = $services.Count
        $serviceItems = @(
            $services |
                Sort-Object -Property Name |
                Select-Object -First $serviceLimit -Property Name, DisplayName, StartMode, State, PathName
        )
    }
    catch {
        $warnings += New-MemoryDiagnosticsWarning `
            -Code 'windows.services_failed' `
            -Source 'windows' `
            -Message '运行中服务采集失败。' `
            -Details @{ error = $_.Exception.Message }
    }

    return [pscustomobject]@{
        WindowsOnly = [pscustomobject]@{
            runningDriverCount  = $driverCount
            runningDrivers      = @($driverItems)
            runningServiceCount = $serviceCount
            runningServices     = @($serviceItems)
        }
        Warnings    = @($warnings)
    }
}

<#
.SYNOPSIS
    获取 Windows 平台快照。

.DESCRIPTION
    汇总 Windows 系统层内存、驱动和服务线索。

.PARAMETER Depth
    采集深度。

.OUTPUTS
    PSCustomObject
    返回 `System`、`WindowsOnly` 与 `Warnings`。
#>
function Get-WindowsPlatformSnapshot {
    [CmdletBinding()]
    param(
        [ValidateSet('basic', 'full')]
        [string]$Depth = 'full'
    )

    $systemSnapshot = Get-WindowsMemorySystemSnapshot
    $driverServiceSnapshot = Get-WindowsDriverServiceSnapshot -Depth $Depth

    return [pscustomobject]@{
        System      = $systemSnapshot.System
        WindowsOnly = $driverServiceSnapshot.WindowsOnly
        Warnings    = @($systemSnapshot.Warnings) + @($driverServiceSnapshot.Warnings)
    }
}
