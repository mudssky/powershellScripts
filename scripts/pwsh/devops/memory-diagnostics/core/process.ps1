<#
.SYNOPSIS
    创建标准化进程内存对象。

.DESCRIPTION
    将 Windows `Get-Process` 与 POSIX `ps` 输出归一化为同一 JSON 结构。

.PARAMETER ProcessName
    进程名称。

.PARAMETER Id
    进程 ID。

.PARAMETER ParentId
    父进程 ID；平台无法提供时可为空。

.PARAMETER WorkingSetMB
    工作集或 RSS，单位 MB。

.PARAMETER PrivateMemoryMB
    私有内存，单位 MB；平台无法提供时可为空。

.PARAMETER VirtualMemoryMB
    虚拟内存或 VSZ，单位 MB。

.PARAMETER PercentMemory
    进程内存占比；平台无法提供时可为空。

.PARAMETER Source
    采集来源。

.OUTPUTS
    PSCustomObject
    返回标准进程内存对象。
#>
function New-MemoryDiagnosticsProcessInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProcessName,

        [Parameter(Mandatory)]
        [int]$Id,

        [AllowNull()]
        [Nullable[int]]$ParentId,

        [AllowNull()]
        [Nullable[double]]$WorkingSetMB,

        [AllowNull()]
        [Nullable[double]]$PrivateMemoryMB,

        [AllowNull()]
        [Nullable[double]]$VirtualMemoryMB,

        [AllowNull()]
        [Nullable[double]]$PercentMemory,

        [string]$Source = 'unknown'
    )

    return [pscustomobject]@{
        processName     = $ProcessName
        id              = $Id
        parentId        = $ParentId
        workingSetMB    = $WorkingSetMB
        privateMemoryMB = $PrivateMemoryMB
        virtualMemoryMB = $VirtualMemoryMB
        percentMemory   = $PercentMemory
        source          = $Source
    }
}

<#
.SYNOPSIS
    解析 POSIX `ps` 进程行。

.DESCRIPTION
    Linux/macOS 的进程明细来自 `ps`，该函数把 pid、ppid、comm、rss、vsz、%mem 解析为统一结构。

.PARAMETER Line
    `ps` 输出的一行文本。

.PARAMETER Source
    采集来源标签。

.OUTPUTS
    PSCustomObject
    返回标准进程对象；无法解析时返回 `$null`。
#>
function ConvertFrom-MemoryDiagnosticsPsLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Line,

        [string]$Source = 'ps'
    )

    if ($Line -match '^\s*PID\s+') {
        return $null
    }

    $match = [regex]::Match($Line, '^\s*(\d+)\s+(\d+)\s+(.+?)\s+(\d+)\s+(\d+)\s+([\d\.,]+)\s*$')
    if (-not $match.Success) {
        return $null
    }

    $percentText = $match.Groups[6].Value -replace ',', '.'
    return New-MemoryDiagnosticsProcessInfo `
        -ProcessName $match.Groups[3].Value.Trim() `
        -Id ([int]$match.Groups[1].Value) `
        -ParentId ([int]$match.Groups[2].Value) `
        -WorkingSetMB ([math]::Round(([double]$match.Groups[4].Value / 1024), 1)) `
        -PrivateMemoryMB $null `
        -VirtualMemoryMB ([math]::Round(([double]$match.Groups[5].Value / 1024), 1)) `
        -PercentMemory ([math]::Round([double]$percentText, 2)) `
        -Source $Source
}

<#
.SYNOPSIS
    使用 `Get-Process` 获取 Top 进程。

.DESCRIPTION
    作为 Windows 主路径和未知平台降级路径，读取工作集、私有内存和虚拟内存。

.PARAMETER Top
    返回的进程数量。

.PARAMETER Source
    采集来源标签。

.OUTPUTS
    PSCustomObject
    返回 `Processes` 与 `Warnings`。
#>
function Get-GenericTopMemoryProcesses {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 500)]
        [int]$Top = 30,

        [string]$Source = 'get-process'
    )

    try {
        $processes = Get-Process -ErrorAction Stop |
            Sort-Object -Property WorkingSet64 -Descending |
            Select-Object -First $Top |
            ForEach-Object {
                $privateBytes = Get-MemoryDiagnosticsPropertyValue -InputObject $_ -Name 'PrivateMemorySize64' -DefaultValue $null
                $virtualBytes = Get-MemoryDiagnosticsPropertyValue -InputObject $_ -Name 'VirtualMemorySize64' -DefaultValue $null
                New-MemoryDiagnosticsProcessInfo `
                    -ProcessName $_.ProcessName `
                    -Id $_.Id `
                    -ParentId $null `
                    -WorkingSetMB ([math]::Round($_.WorkingSet64 / 1MB, 1)) `
                    -PrivateMemoryMB $(if ($null -eq $privateBytes) { $null } else { [math]::Round([double]$privateBytes / 1MB, 1) }) `
                    -VirtualMemoryMB $(if ($null -eq $virtualBytes) { $null } else { [math]::Round([double]$virtualBytes / 1MB, 1) }) `
                    -PercentMemory $null `
                    -Source $Source
            }

        return [pscustomobject]@{
            Processes = @($processes)
            Warnings  = @()
        }
    }
    catch {
        return [pscustomobject]@{
            Processes = @()
            Warnings  = @(
                New-MemoryDiagnosticsWarning `
                    -Code 'process.get_process_failed' `
                    -Source 'process' `
                    -Message 'Top 进程采集失败。' `
                    -Details @{ error = $_.Exception.Message }
            )
        }
    }
}

<#
.SYNOPSIS
    获取当前平台 Top 内存进程。

.DESCRIPTION
    Windows 使用 `Get-Process`，Linux/macOS 使用平台 `ps`，未知平台回落到通用路径。

.PARAMETER Top
    返回的进程数量。

.OUTPUTS
    PSCustomObject
    返回 `Processes` 与 `Warnings`。
#>
function Get-TopMemoryProcesses {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 500)]
        [int]$Top = 30
    )

    if ($IsWindows) {
        return Get-WindowsTopMemoryProcesses -Top $Top
    }

    if ($IsLinux) {
        return Get-LinuxTopMemoryProcesses -Top $Top
    }

    if ($IsMacOS) {
        return Get-MacOSTopMemoryProcesses -Top $Top
    }

    return Get-GenericTopMemoryProcesses -Top $Top -Source 'get-process-fallback'
}
