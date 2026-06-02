<#
.SYNOPSIS
    返回当前运行平台名称。

.DESCRIPTION
    将 PowerShell 内置平台变量归一化为报告中的稳定字符串。

.OUTPUTS
    string
    返回 Windows、Linux、macOS 或 Unknown。
#>
function Get-MemoryDiagnosticsPlatformName {
    [CmdletBinding()]
    param()

    if ($IsWindows) { return 'Windows' }
    if ($IsLinux) { return 'Linux' }
    if ($IsMacOS) { return 'macOS' }
    return 'Unknown'
}

<#
.SYNOPSIS
    把字节数转换为 GB。

.DESCRIPTION
    统一所有平台采集到的字节值，避免报告里混用 byte、KB、MB。

.PARAMETER Bytes
    要转换的字节数。

.OUTPUTS
    double
    返回保留两位小数的 GB 值；输入为空时返回 `$null`。
#>
function ConvertTo-MemoryDiagnosticsGB {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Bytes
    )

    if ($null -eq $Bytes) {
        return $null
    }

    return [math]::Round(([double]$Bytes / 1GB), 2)
}

<#
.SYNOPSIS
    计算百分比并处理除零。

.DESCRIPTION
    用于 available、commit、容器占比等阈值判断，统一空值和零值的降级行为。

.PARAMETER Numerator
    分子数值。

.PARAMETER Denominator
    分母数值。

.OUTPUTS
    double
    返回保留两位小数的百分比；分母为空或小于等于 0 时返回 `$null`。
#>
function ConvertTo-MemoryDiagnosticsPercent {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Numerator,

        [AllowNull()]
        [object]$Denominator
    )

    if ($null -eq $Numerator -or $null -eq $Denominator -or [double]$Denominator -le 0) {
        return $null
    }

    return [math]::Round(([double]$Numerator / [double]$Denominator) * 100, 2)
}

<#
.SYNOPSIS
    创建结构化 warning。

.DESCRIPTION
    采集失败、命令缺失、权限不足等情况都写入 warning，确保主报告不中断。

.PARAMETER Code
    稳定的 warning 代码。

.PARAMETER Message
    面向用户的中文说明。

.PARAMETER Source
    warning 来源模块或平台。

.PARAMETER Details
    附加诊断信息。

.OUTPUTS
    PSCustomObject
    返回标准 warning 对象。
#>
function New-MemoryDiagnosticsWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Code,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Source = 'memory-diagnostics',

        [hashtable]$Details = @{}
    )

    return [pscustomobject]@{
        code    = $Code
        source  = $Source
        message = $Message
        details = $Details
    }
}

<#
.SYNOPSIS
    从对象或哈希表中安全读取字段。

.DESCRIPTION
    阈值规则会读取不同平台返回的可选字段；该函数避免 StrictMode 下访问缺失属性抛错。

.PARAMETER InputObject
    要读取的对象或哈希表。

.PARAMETER Name
    字段名称。

.PARAMETER DefaultValue
    字段不存在或对象为空时返回的默认值。

.OUTPUTS
    object
    返回字段值或默认值。
#>
function Get-MemoryDiagnosticsPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }

    if ($InputObject -is [hashtable]) {
        if ($InputObject.ContainsKey($Name)) {
            return $InputObject[$Name]
        }

        return $DefaultValue
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

<#
.SYNOPSIS
    返回内存诊断工具帮助文本。

.DESCRIPTION
    生成静态帮助文本，供 `help` 命令和错误提示复用。

.OUTPUTS
    string
    返回命令用法说明。
#>
function Get-MemoryDiagnosticsHelpText {
    [CmdletBinding()]
    param()

    return @'
Usage:
  Invoke-MemoryDiagnostics.ps1 snapshot [-Top 30] [-Depth basic|full]
  Invoke-MemoryDiagnostics.ps1 sample [-IntervalSeconds 300] [-Count 3] [-Top 30]
  Invoke-MemoryDiagnostics.ps1 help

Commands:
  snapshot   输出一次性内存诊断 JSON，默认命令
  sample     按间隔采样多次，用于观察疑似泄漏趋势
  help       显示帮助
'@
}

<#
.SYNOPSIS
    构建一次性内存诊断报告。

.DESCRIPTION
    汇总平台系统指标、Top 进程、Docker 容器状态和 recommendations，输出统一对象供 JSON 序列化。

.PARAMETER Top
    Top 进程数量。

.PARAMETER Depth
    采集深度。`basic` 会限制昂贵的 Windows 驱动/服务明细，`full` 输出更多线索。

.OUTPUTS
    PSCustomObject
    返回统一内存诊断报告对象。
#>
function New-MemoryDiagnosticsReport {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 500)]
        [int]$Top = 30,

        [ValidateSet('basic', 'full')]
        [string]$Depth = 'full'
    )

    $platform = Get-MemoryDiagnosticsPlatformName
    $warnings = @()

    try {
        $platformSnapshot = switch ($platform) {
            'Windows' { Get-WindowsPlatformSnapshot -Depth $Depth }
            'Linux' { Get-LinuxPlatformSnapshot -Depth $Depth }
            'macOS' { Get-MacOSPlatformSnapshot -Depth $Depth }
            default {
                [pscustomobject]@{
                    System      = [pscustomobject]@{ platform = $platform; source = 'unknown' }
                    WindowsOnly = $null
                    Warnings    = @(
                        New-MemoryDiagnosticsWarning `
                            -Code 'platform.unknown' `
                            -Source 'platform' `
                            -Message '当前平台无法识别，只能返回通用进程与 Docker 信息。'
                    )
                }
            }
        }
    }
    catch {
        $platformSnapshot = [pscustomobject]@{
            System      = [pscustomobject]@{ platform = $platform; source = 'failed' }
            WindowsOnly = $null
            Warnings    = @(
                New-MemoryDiagnosticsWarning `
                    -Code 'platform.snapshot_failed' `
                    -Source 'platform' `
                    -Message '系统层内存采集失败。' `
                    -Details @{ error = $_.Exception.Message }
            )
        }
    }

    $warnings += @($platformSnapshot.Warnings)

    $processSnapshot = Get-TopMemoryProcesses -Top $Top
    $warnings += @($processSnapshot.Warnings)

    $containerSnapshot = Get-DockerMemorySnapshot
    $warnings += @($containerSnapshot.warnings)

    $report = [pscustomobject]@{
        metadata        = [pscustomobject]@{
            generatedAt  = (Get-Date).ToUniversalTime().ToString('o')
            mode         = 'snapshot'
            platform     = $platform
            pwshVersion  = $PSVersionTable.PSVersion.ToString()
            computerName = [System.Environment]::MachineName
            top          = $Top
            depth        = $Depth
        }
        system          = $platformSnapshot.System
        topProcesses    = @($processSnapshot.Processes)
        containers      = $containerSnapshot
        windowsOnly     = $platformSnapshot.WindowsOnly
        samples         = @()
        warnings        = @($warnings)
        recommendations = @()
    }

    $report.recommendations = @(Get-MemoryDiagnosticsRecommendations -Report $report)
    return $report
}
