<#
.SYNOPSIS
    创建结构化诊断建议。

.DESCRIPTION
    recommendations 只提供下一步排查方向，不执行任何清理或系统修改。

.PARAMETER Code
    稳定建议代码。

.PARAMETER Severity
    建议级别，例如 info、warning、critical。

.PARAMETER Category
    建议类别。

.PARAMETER Message
    面向用户的中文建议。

.PARAMETER Evidence
    触发建议的关键证据。

.PARAMETER NextActions
    下一步动作建议。

.OUTPUTS
    PSCustomObject
    返回标准 recommendations 对象。
#>
function New-MemoryDiagnosticsRecommendation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Code,

        [ValidateSet('info', 'warning', 'critical')]
        [string]$Severity = 'info',

        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$Message,

        [hashtable]$Evidence = @{},

        [string[]]$NextActions = @()
    )

    return [pscustomobject]@{
        code        = $Code
        severity    = $Severity
        category    = $Category
        message     = $Message
        evidence    = $Evidence
        nextActions = @($NextActions)
    }
}

<#
.SYNOPSIS
    把可选值转换为 double。

.DESCRIPTION
    阈值判断需要安全处理 `$null`、空字符串和不可转数字段。

.PARAMETER Value
    要转换的值。

.PARAMETER DefaultValue
    转换失败时返回的默认值。

.OUTPUTS
    double
    返回转换后的数值或默认值。
#>
function ConvertTo-MemoryDiagnosticsNumber {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [double]$DefaultValue = 0
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $DefaultValue
    }

    try {
        return [double]$Value
    }
    catch {
        return $DefaultValue
    }
}

<#
.SYNOPSIS
    生成内存诊断建议。

.DESCRIPTION
    根据统一报告中的进程、系统层、Windows 内核池和 Docker 状态生成第一版结论字段。

.PARAMETER Report
    统一内存诊断报告。

.OUTPUTS
    PSCustomObject[]
    返回 recommendations 数组。
#>
function Get-MemoryDiagnosticsRecommendations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Report
    )

    $recommendations = @()
    $system = Get-MemoryDiagnosticsPropertyValue -InputObject $Report -Name 'system'
    $totalPhysicalGB = ConvertTo-MemoryDiagnosticsNumber -Value (Get-MemoryDiagnosticsPropertyValue -InputObject $system -Name 'totalPhysicalGB') -DefaultValue 0
    $availablePercent = ConvertTo-MemoryDiagnosticsNumber -Value (Get-MemoryDiagnosticsPropertyValue -InputObject $system -Name 'availablePercent') -DefaultValue 100
    $commitPercent = ConvertTo-MemoryDiagnosticsNumber -Value (Get-MemoryDiagnosticsPropertyValue -InputObject $system -Name 'commitPercent') -DefaultValue 0
    $kernelPoolGB = ConvertTo-MemoryDiagnosticsNumber -Value (Get-MemoryDiagnosticsPropertyValue -InputObject $system -Name 'kernelPoolGB') -DefaultValue 0
    $nonPagedPoolGB = ConvertTo-MemoryDiagnosticsNumber -Value (Get-MemoryDiagnosticsPropertyValue -InputObject $system -Name 'nonPagedPoolGB') -DefaultValue 0

    if ($availablePercent -gt 0 -and $availablePercent -lt 10) {
        $recommendations += New-MemoryDiagnosticsRecommendation `
            -Code 'system.low_available_memory' `
            -Severity 'warning' `
            -Category 'system' `
            -Message '可用物理内存低于 10%，先结合 Top 进程和系统提交量判断压力来源。' `
            -Evidence @{ availablePercent = $availablePercent } `
            -NextActions @('查看 topProcesses 前几名', '检查是否存在高 commit 或 kernel pool 异常')
    }

    if ($commitPercent -ge 85) {
        $recommendations += New-MemoryDiagnosticsRecommendation `
            -Code 'windows.high_commit' `
            -Severity 'warning' `
            -Category 'windows' `
            -Message '系统提交量接近提交上限，建议检查 pagefile、长期运行进程和虚拟化负载。' `
            -Evidence @{ commitPercent = $commitPercent } `
            -NextActions @('查看 commitCommittedGB 与 commitLimitGB', '检查长期运行的 IDE、浏览器、WSL、Docker')
    }

    if ($kernelPoolGB -ge 4 -or ($totalPhysicalGB -gt 0 -and ($kernelPoolGB / $totalPhysicalGB) -ge 0.15) -or $nonPagedPoolGB -ge 2) {
        $recommendations += New-MemoryDiagnosticsRecommendation `
            -Code 'windows.kernel_pool_suspect' `
            -Severity 'critical' `
            -Category 'windows' `
            -Message 'Windows 内核池占用异常时，单看进程列表会漏掉主因。' `
            -Evidence @{ kernelPoolGB = $kernelPoolGB; nonPagedPoolGB = $nonPagedPoolGB; totalPhysicalGB = $totalPhysicalGB } `
            -NextActions @('使用 RAMMap 查看 Use Counts', '使用 Process Explorer 查看 System Information', '用 Autoruns 检查可疑驱动或服务', '必要时再用 PoolMon 做 pool tag 归因')
    }

    $topProcesses = @((Get-MemoryDiagnosticsPropertyValue -InputObject $Report -Name 'topProcesses' -DefaultValue @()))
    $topProcess = $topProcesses | Select-Object -First 1
    if ($null -ne $topProcess) {
        $topWorkingSetMB = ConvertTo-MemoryDiagnosticsNumber -Value (Get-MemoryDiagnosticsPropertyValue -InputObject $topProcess -Name 'workingSetMB') -DefaultValue 0
        $topPercentOfPhysical = if ($totalPhysicalGB -gt 0) {
            [math]::Round(($topWorkingSetMB / 1024 / $totalPhysicalGB) * 100, 2)
        }
        else {
            0
        }

        if ($topWorkingSetMB -ge 2048 -or $topPercentOfPhysical -ge 20) {
            $recommendations += New-MemoryDiagnosticsRecommendation `
                -Code 'process.high_top_process' `
                -Severity 'warning' `
                -Category 'process' `
                -Message 'Top 进程占用较高，优先确认它是否符合当前工作负载。' `
                -Evidence @{
                    processName          = Get-MemoryDiagnosticsPropertyValue -InputObject $topProcess -Name 'processName'
                    id                   = Get-MemoryDiagnosticsPropertyValue -InputObject $topProcess -Name 'id'
                    workingSetMB         = $topWorkingSetMB
                    percentOfPhysicalRam = $topPercentOfPhysical
                } `
                -NextActions @('检查该进程是否为 IDE、浏览器、WSL、Docker 或长时间运行任务', '必要时重启低频使用应用')
        }
    }

    $containers = Get-MemoryDiagnosticsPropertyValue -InputObject $Report -Name 'containers'
    $dockerAvailable = [bool](Get-MemoryDiagnosticsPropertyValue -InputObject $containers -Name 'available' -DefaultValue $false)
    $dockerStatus = [string](Get-MemoryDiagnosticsPropertyValue -InputObject $containers -Name 'status' -DefaultValue 'unknown')
    $dockerTotalMB = ConvertTo-MemoryDiagnosticsNumber -Value (Get-MemoryDiagnosticsPropertyValue -InputObject $containers -Name 'totalMemoryMB') -DefaultValue 0

    if (-not $dockerAvailable) {
        $recommendations += New-MemoryDiagnosticsRecommendation `
            -Code 'docker.unavailable' `
            -Severity 'info' `
            -Category 'docker' `
            -Message 'Docker 容器内存未能采集，报告仍可用于判断进程和系统层压力。' `
            -Evidence @{ status = $dockerStatus } `
            -NextActions @('如需容器视角，确认 Docker Desktop 或 Docker daemon 是否运行')
    }
    elseif ($totalPhysicalGB -gt 0 -and (($dockerTotalMB / 1024) / $totalPhysicalGB) -lt 0.1) {
        $recommendations += New-MemoryDiagnosticsRecommendation `
            -Code 'docker.not_primary_signal' `
            -Severity 'info' `
            -Category 'docker' `
            -Message '当前 Docker 容器内存占比不高，不应把容器当作唯一主因。' `
            -Evidence @{ totalMemoryMB = $dockerTotalMB; totalPhysicalGB = $totalPhysicalGB } `
            -NextActions @('继续检查 Top 进程、commit 和 kernel pool')
    }

    return @($recommendations)
}
