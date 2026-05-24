<#
.SYNOPSIS
    执行多次内存诊断采样。

.DESCRIPTION
    前台按固定间隔采集 snapshot，用于观察疑似泄漏趋势；单次失败会写入 sample warning，不中断后续采样。

.PARAMETER Count
    采样次数。

.PARAMETER IntervalSeconds
    采样间隔秒数。为 0 时连续采样，主要用于测试和快速验证。

.PARAMETER Top
    每次采样的 Top 进程数量。

.PARAMETER Depth
    每次采样的采集深度。

.OUTPUTS
    PSCustomObject
    返回包含 samples 的统一采样报告。
#>
function Invoke-MemoryDiagnosticsSampling {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 10000)]
        [int]$Count = 3,

        [ValidateRange(0, 86400)]
        [int]$IntervalSeconds = 300,

        [ValidateRange(1, 500)]
        [int]$Top = 30,

        [ValidateSet('basic', 'full')]
        [string]$Depth = 'full'
    )

    $samples = @()
    $warnings = @()

    for ($index = 0; $index -lt $Count; $index++) {
        try {
            $samples += New-MemoryDiagnosticsReport -Top $Top -Depth $Depth
        }
        catch {
            $warning = New-MemoryDiagnosticsWarning `
                -Code 'sample.snapshot_failed' `
                -Source 'sampling' `
                -Message '单次内存采样失败。' `
                -Details @{ index = $index; error = $_.Exception.Message }
            $warnings += $warning
            $samples += [pscustomobject]@{
                metadata = [pscustomobject]@{
                    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
                    mode        = 'sample-error'
                    index       = $index
                }
                warnings = @($warning)
            }
        }

        if ($IntervalSeconds -gt 0 -and $index -lt ($Count - 1)) {
            Start-Sleep -Seconds $IntervalSeconds
        }
    }

    $lastSample = $samples | Select-Object -Last 1
    return [pscustomobject]@{
        metadata        = [pscustomobject]@{
            generatedAt      = (Get-Date).ToUniversalTime().ToString('o')
            mode             = 'sample'
            platform         = Get-MemoryDiagnosticsPlatformName
            count            = $Count
            intervalSeconds  = $IntervalSeconds
            top              = $Top
            depth            = $Depth
        }
        system          = $null
        topProcesses    = @()
        containers      = $null
        windowsOnly     = $null
        samples         = @($samples)
        warnings        = @($warnings)
        recommendations = @((Get-MemoryDiagnosticsPropertyValue -InputObject $lastSample -Name 'recommendations' -DefaultValue @()))
    }
}
