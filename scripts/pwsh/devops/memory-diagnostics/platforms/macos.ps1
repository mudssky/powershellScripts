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
    将 macOS 虚拟内存页数转换为 GB。

.DESCRIPTION
    macOS `vm_stat` 使用页数表达内存状态，该函数按 page size 统一换算为 GB。

.PARAMETER Pages
    页面数量。

.PARAMETER PageSize
    单页字节数。

.OUTPUTS
    double
    返回 GB；输入为空时返回 `$null`。
#>
function ConvertFrom-MacOSPageCountToGB {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Pages,

        [Parameter(Mandatory)]
        [int]$PageSize
    )

    if ($null -eq $Pages) {
        return $null
    }

    return ConvertTo-MemoryDiagnosticsGB -Bytes ([double]$Pages * $PageSize)
}

<#
.SYNOPSIS
    解析 macOS `vm_stat`。

.DESCRIPTION
    读取 page size、free、inactive、speculative、active、wired、compressed、pageout 与 swap I/O 等页面计数。

.PARAMETER Lines
    `vm_stat` 输出行。

.PARAMETER TotalBytes
    系统总内存字节数。

.OUTPUTS
    PSCustomObject
    返回 macOS 物理内存估算字段和压力线索。
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

        $statMatch = [regex]::Match($line, '^\s*"?(?<name>[^":]+)"?:\s+(?<value>\d+)\.?')
        if ($statMatch.Success) {
            $name = $statMatch.Groups['name'].Value -replace '^Pages\s+', ''
            $key = ($name -replace '\s+', '_').ToLowerInvariant()
            $pages[$key] = [double]$statMatch.Groups['value'].Value
        }
    }

    $freePages = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'free' -DefaultValue 0)
    $activePages = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'active' -DefaultValue 0)
    $inactivePages = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'inactive' -DefaultValue 0)
    $speculativePages = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'speculative' -DefaultValue 0)
    $wiredPages = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'wired_down' -DefaultValue 0)
    $purgeablePages = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'purgeable' -DefaultValue 0)
    $compressedPages = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'stored_in_compressor' -DefaultValue 0)
    $compressorPages = [double](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'occupied_by_compressor' -DefaultValue 0)
    $availablePages =
        $freePages +
        $inactivePages +
        $speculativePages
    $availableBytes = $availablePages * $pageSize

    return [pscustomobject]@{
        totalPhysicalGB  = ConvertTo-MemoryDiagnosticsGB -Bytes $TotalBytes
        availableGB      = ConvertTo-MemoryDiagnosticsGB -Bytes $availableBytes
        usedPhysicalGB   = ConvertTo-MemoryDiagnosticsGB -Bytes ($TotalBytes - $availableBytes)
        availablePercent = ConvertTo-MemoryDiagnosticsPercent -Numerator $availableBytes -Denominator $TotalBytes
        pageSizeBytes    = $pageSize
        freeGB           = ConvertFrom-MacOSPageCountToGB -Pages $freePages -PageSize $pageSize
        activeGB         = ConvertFrom-MacOSPageCountToGB -Pages $activePages -PageSize $pageSize
        inactiveGB       = ConvertFrom-MacOSPageCountToGB -Pages $inactivePages -PageSize $pageSize
        speculativeGB    = ConvertFrom-MacOSPageCountToGB -Pages $speculativePages -PageSize $pageSize
        wiredGB          = ConvertFrom-MacOSPageCountToGB -Pages $wiredPages -PageSize $pageSize
        purgeableGB      = ConvertFrom-MacOSPageCountToGB -Pages $purgeablePages -PageSize $pageSize
        compressedGB     = ConvertFrom-MacOSPageCountToGB -Pages $compressedPages -PageSize $pageSize
        compressorGB     = ConvertFrom-MacOSPageCountToGB -Pages $compressorPages -PageSize $pageSize
        swapins          = [int64](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'swapins' -DefaultValue 0)
        swapouts         = [int64](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'swapouts' -DefaultValue 0)
        pageins          = [int64](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'pageins' -DefaultValue 0)
        pageouts         = [int64](Get-MemoryDiagnosticsPropertyValue -InputObject $pages -Name 'pageouts' -DefaultValue 0)
    }
}

<#
.SYNOPSIS
    解析 macOS `memory_pressure` 输出。

.DESCRIPTION
    提取 `System-wide memory free percentage`，用于辅助判断当前内存压力是否真实偏高。

.PARAMETER Lines
    `memory_pressure` 输出行。

.OUTPUTS
    PSCustomObject
    返回内存压力摘要。
#>
function ConvertFrom-MacOSMemoryPressure {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $freePercent = $null
    foreach ($line in $Lines) {
        $match = [regex]::Match($line, 'System-wide memory free percentage:\s+(?<percent>[\d\.]+)%')
        if ($match.Success) {
            $freePercent = [math]::Round([double]$match.Groups['percent'].Value, 2)
            break
        }
    }

    return [pscustomobject]@{
        memoryPressureFreePercent = $freePercent
    }
}

<#
.SYNOPSIS
    解析 macOS 宽格式 `ps` 进程行。

.DESCRIPTION
    macOS 进程路径常含空格，`comm` 放在最后一列后用该函数解析，避免 `comm` 位于中间列时被截断。

.PARAMETER Line
    `ps -ww -axo pid=,ppid=,rss=,vsz=,%mem=,comm=` 输出的一行文本。

.OUTPUTS
    PSCustomObject
    返回标准进程对象；无法解析时返回 `$null`。
#>
function ConvertFrom-MacOSTopProcessLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Line
    )

    $match = [regex]::Match($Line, '^\s*(?<pid>\d+)\s+(?<ppid>\d+)\s+(?<rss>\d+)\s+(?<vsz>\d+)\s+(?<percent>[\d\.,]+)\s+(?<command>.+?)\s*$')
    if (-not $match.Success) {
        return $null
    }

    $percentText = $match.Groups['percent'].Value -replace ',', '.'
    return New-MemoryDiagnosticsProcessInfo `
        -ProcessName $match.Groups['command'].Value.Trim() `
        -Id ([int]$match.Groups['pid'].Value) `
        -ParentId ([int]$match.Groups['ppid'].Value) `
        -WorkingSetMB ([math]::Round(([double]$match.Groups['rss'].Value / 1024), 1)) `
        -PrivateMemoryMB $null `
        -VirtualMemoryMB ([math]::Round(([double]$match.Groups['vsz'].Value / 1024), 1)) `
        -PercentMemory ([math]::Round([double]$percentText, 2)) `
        -Source 'macos-ps'
}

<#
.SYNOPSIS
    获取 macOS `memory_pressure` 快照。

.DESCRIPTION
    `memory_pressure` 是 macOS 判断即时内存压力的重要只读信号；采集失败时返回 warning，不中断主报告。

.OUTPUTS
    PSCustomObject
    返回 `Pressure` 与 `Warnings`。
#>
function Get-MacOSMemoryPressureSnapshot {
    [CmdletBinding()]
    param()

    $command = Get-Command memory_pressure -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        return [pscustomobject]@{
            Pressure = [pscustomobject]@{ memoryPressureFreePercent = $null }
            Warnings = @(
                New-MemoryDiagnosticsWarning `
                    -Code 'macos.memory_pressure_missing' `
                    -Source 'macos' `
                    -Message '未找到 memory_pressure 命令，跳过 macOS 内存压力采集。'
            )
        }
    }

    try {
        $lines = @(& $command.Source 2>&1)
        return [pscustomobject]@{
            Pressure = ConvertFrom-MacOSMemoryPressure -Lines $lines
            Warnings = @()
        }
    }
    catch {
        return [pscustomobject]@{
            Pressure = [pscustomobject]@{ memoryPressureFreePercent = $null }
            Warnings = @(
                New-MemoryDiagnosticsWarning `
                    -Code 'macos.memory_pressure_failed' `
                    -Source 'macos' `
                    -Message 'memory_pressure 采集失败。' `
                    -Details @{ error = $_.Exception.Message }
            )
        }
    }
}

<#
.SYNOPSIS
    获取 macOS memorystatus 压力等级。

.DESCRIPTION
    通过 `sysctl kern.memorystatus_vm_pressure_level` 读取系统压力等级原始值，作为 macOS 内存压力辅助证据。

.OUTPUTS
    int
    返回压力等级；无法读取时返回 `$null`。
#>
function Get-MacOSVmPressureLevel {
    [CmdletBinding()]
    param()

    try {
        $value = [string](sysctl -n kern.memorystatus_vm_pressure_level 2>$null)
        if ($value -match '^\s*(\d+)\s*$') {
            return [int]$Matches[1]
        }
    }
    catch {
        return $null
    }

    return $null
}

<#
.SYNOPSIS
    获取 macOS 系统层内存快照。

.DESCRIPTION
    使用 `sysctl`、`vm_stat`、`memory_pressure` 和 `vm.swapusage` 采集 macOS 内存与 swap 状态。

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
        $memoryPressure = Get-MacOSMemoryPressureSnapshot
        $warnings += @($memoryPressure.Warnings)
        $vmPressureLevel = Get-MacOSVmPressureLevel
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
                platform                  = 'macOS'
                source                    = 'sysctl-vm_stat-memory_pressure'
                totalPhysicalGB           = $vmStat.totalPhysicalGB
                availableGB               = $vmStat.availableGB
                usedPhysicalGB            = $vmStat.usedPhysicalGB
                availablePercent          = $vmStat.availablePercent
                memoryPressureFreePercent = $memoryPressure.Pressure.memoryPressureFreePercent
                vmPressureLevel           = $vmPressureLevel
                swapTotalGB               = if ($null -eq $swapTotalMB) { $null } else { [math]::Round($swapTotalMB / 1024, 2) }
                swapUsedGB                = if ($null -eq $swapUsedMB) { $null } else { [math]::Round($swapUsedMB / 1024, 2) }
                swapFreeGB                = if ($null -eq $swapFreeMB) { $null } else { [math]::Round($swapFreeMB / 1024, 2) }
                pageSizeBytes             = $vmStat.pageSizeBytes
                freeGB                    = $vmStat.freeGB
                activeGB                  = $vmStat.activeGB
                inactiveGB                = $vmStat.inactiveGB
                speculativeGB             = $vmStat.speculativeGB
                wiredGB                   = $vmStat.wiredGB
                purgeableGB               = $vmStat.purgeableGB
                compressedGB              = $vmStat.compressedGB
                compressorGB              = $vmStat.compressorGB
                swapins                   = $vmStat.swapins
                swapouts                  = $vmStat.swapouts
                pageins                   = $vmStat.pageins
                pageouts                  = $vmStat.pageouts
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
    使用 `ps -ww -axo pid,ppid,rss,vsz,%mem,comm` 采集 RSS/VSZ，避免 macOS 默认宽度截断进程名。

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
        $lines = @(ps -ww -axo pid=,ppid=,rss=,vsz=,%mem=,comm= 2>$null)
        $processes = foreach ($line in $lines) {
            ConvertFrom-MacOSTopProcessLine -Line ([string]$line)
        }

        return [pscustomobject]@{
            Processes = @($processes | Where-Object { $null -ne $_ } | Sort-Object -Property workingSetMB -Descending | Select-Object -First $Top)
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
