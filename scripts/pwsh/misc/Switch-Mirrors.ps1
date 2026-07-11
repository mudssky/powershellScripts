#!/usr/bin/env pwsh

<#
.SYNOPSIS
    跨平台 package source 计划、应用、状态与恢复入口。

.DESCRIPTION
    默认 Direct 不探测也不修改 source；China 创建持久事务；Auto 仅在官方端点连续失败时
    创建临时事务。旧 Docker 参数继续映射到同一事务引擎。

.PARAMETER Action
    Plan、Apply、Ensure、Status 或 Restore。

.PARAMETER Mode
    Direct、China 或 Auto，默认 Direct。

.PARAMETER Phase
    Bootstrap、Runtime、Toolchain 或 Optional。

.PARAMETER Target
    要处理的 package source target。

.PARAMETER TransactionId
    Apply 可选、Ensure/Restore 必需的事务 ID。

.PARAMETER Selection
    Auto、First 或 chsrc provider。

.PARAMETER OutputFormat
    Text 或 Json。

.PARAMETER Force
    仅人工 Restore 使用，允许先备份 drift 文件再恢复。

.PARAMETER MirrorUrls
    Docker 候选镜像覆盖；同时保留旧调用兼容。

.PARAMETER UseChinaMirror
    旧 Docker 快捷参数，未传 MirrorUrls 时使用 catalog 默认值。

.PARAMETER Disable
    旧 Docker 参数，恢复 legacy-docker 事务。

.PARAMETER TimeoutSec
    Docker 镜像探活超时秒数。

.PARAMETER Retry
    Docker 镜像探活重试次数。

.PARAMETER DryRun
    旧 Docker 参数，映射为 Plan。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Target,

    [ValidateSet('Plan', 'Apply', 'Ensure', 'Status', 'Restore')]
    [string]$Action = 'Plan',

    [ValidateSet('Direct', 'China', 'Auto')]
    [string]$Mode = 'Direct',

    [ValidateSet('Bootstrap', 'Runtime', 'Toolchain', 'Optional')]
    [string]$Phase = 'Runtime',

    [string]$TransactionId = '',

    [string]$Selection = 'Auto',

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [switch]$Force,

    [string[]]$MirrorUrls,

    [switch]$UseChinaMirror,

    [switch]$Disable,

    [int]$TimeoutSec = 5,

    [int]$Retry = 1,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:SwitchMirrorsBoundParameters = @{} + $PSBoundParameters
$script:SwitchMirrorsExitCode = 0

function Import-SwitchMirrorsPackageSourceModule {
    <#
    .SYNOPSIS
        加载统一 package source 引擎。

    .OUTPUTS
        None。
    #>
    [CmdletBinding()]
    param()

    Import-Module (Join-Path $PSScriptRoot 'package-sources/PackageSources.psm1') -Force
}

function Import-SwitchMirrorsDockerAdapter {
    <#
    .SYNOPSIS
        加载 Docker source adapter。

    .OUTPUTS
        None。
    #>
    [CmdletBinding()]
    param()

    Import-Module (Join-Path $PSScriptRoot 'package-sources/adapters/DockerAdapter.psm1') -Force
}

function Get-DockerDaemonPath {
    <#
    .SYNOPSIS
        兼容旧调用，返回统一 Docker adapter 使用的 daemon 路径。

    .OUTPUTS
        string。daemon.json 路径。
    #>
    [CmdletBinding()]
    param()

    Import-SwitchMirrorsDockerAdapter
    return Get-DockerPackageSourcePath
}

function Invoke-DockerRestart {
    <#
    .SYNOPSIS
        兼容旧调用，委托统一 Docker adapter 执行重启。

    .PARAMETER DryRun
        只输出计划，不执行重启。

    .OUTPUTS
        string。重启结果或计划。
    #>
    [CmdletBinding()]
    param(
        [switch]$DryRun
    )

    if ($DryRun) {
        return '将按平台重启 Docker 引擎或提示重启 Docker Desktop'
    }

    Import-SwitchMirrorsDockerAdapter
    return Invoke-DockerPackageSourceRestart
}

function Test-MirrorUrl {
    <#
    .SYNOPSIS
        兼容旧函数名，测试 Docker Registry V2 镜像。

    .PARAMETER Url
        镜像源基础地址。

    .PARAMETER TimeoutSec
        超时时间秒数。

    .PARAMETER Retry
        重试次数。

    .OUTPUTS
        PSCustomObject。包含 Url、Success、StatusCode、ElapsedMs 与 Error。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [int]$TimeoutSec = 5,

        [int]$Retry = 1
    )

    Import-SwitchMirrorsDockerAdapter
    return Test-DockerPackageSourceUrl -Url $Url -TimeoutSeconds $TimeoutSec -Retry $Retry
}

function Select-BestMirror {
    <#
    .SYNOPSIS
        兼容旧函数名，选择最快可用 Docker 镜像。

    .PARAMETER MirrorUrls
        候选镜像源列表。

    .PARAMETER TimeoutSec
        探活超时秒数。

    .PARAMETER Retry
        探活重试次数。

    .OUTPUTS
        PSCustomObject。包含 BestUrl 与 Results。
    #>
    [CmdletBinding()]
    param(
        [string[]]$MirrorUrls,

        [int]$TimeoutSec = 5,

        [int]$Retry = 1
    )

    if (-not $MirrorUrls -or $MirrorUrls.Count -eq 0) {
        return [PSCustomObject]@{ BestUrl = ''; Results = @() }
    }

    Import-SwitchMirrorsDockerAdapter
    $selection = Select-DockerPackageSourceMirror -MirrorUrl $MirrorUrls -TimeoutSeconds $TimeoutSec -Retry $Retry
    return [PSCustomObject]@{
        BestUrl = if ($selection.Urls.Count -gt 0) { $selection.Urls[0] } else { '' }
        Results = $selection.Results
    }
}

function Set-DockerRegistryMirror {
    <#
    .SYNOPSIS
        兼容旧参数，通过统一事务引擎管理 Docker registry mirrors。

    .DESCRIPTION
        Apply 使用固定兼容事务 ID；Disable 恢复该事务，DryRun 映射为 Plan。

    .PARAMETER MirrorUrls
        候选镜像源列表。

    .PARAMETER UseChinaMirror
        未提供候选列表时使用 catalog 默认国内镜像。

    .PARAMETER Disable
        恢复兼容事务应用前的配置。

    .PARAMETER DryRun
        只预览，不创建事务或写文件。

    .PARAMETER TimeoutSec
        探活超时秒数。

    .PARAMETER Retry
        探活重试次数。

    .OUTPUTS
        object[]。统一引擎返回的逐 target 结果。
    #>
    [CmdletBinding()]
    param(
        [string[]]$MirrorUrls,

        [switch]$UseChinaMirror,

        [switch]$Disable,

        [switch]$DryRun,

        [int]$TimeoutSec = 5,

        [int]$Retry = 1
    )

    Import-SwitchMirrorsPackageSourceModule
    $legacyTransactionId = 'legacy-docker'
    if ($DryRun) {
        return (Invoke-PackageSourceAction -Action Plan -Mode China -Target docker -TransactionId $legacyTransactionId -MirrorUrl $MirrorUrls -TimeoutSeconds $TimeoutSec -Retry $Retry).Results
    }
    if ($Disable) {
        return (Invoke-PackageSourceAction -Action Restore -TransactionId $legacyTransactionId).Results
    }
    if ((!$MirrorUrls -or $MirrorUrls.Count -eq 0) -and -not $UseChinaMirror.IsPresent) {
        Write-Output '未提供镜像源，且未启用默认中国镜像；跳过写入'
        return
    }

    return (Invoke-PackageSourceAction -Action Apply -Mode China -Target docker -TransactionId $legacyTransactionId -MirrorUrl $MirrorUrls -TimeoutSeconds $TimeoutSec -Retry $Retry).Results
}

function Invoke-Main {
    <#
    .SYNOPSIS
        解析新合同或旧 Docker 参数并执行。

    .OUTPUTS
        None。结果写入 stdout，退出码保存到脚本状态。
    #>
    [CmdletBinding()]
    param()

    $newParameterNames = @('Action', 'Mode', 'Phase', 'TransactionId', 'Selection', 'OutputFormat', 'Force')
    $usesNewContract = @($newParameterNames | Where-Object { $script:SwitchMirrorsBoundParameters.ContainsKey($_) }).Count -gt 0
    $usesNewContract = $usesNewContract -or @($Target | Where-Object { $_ -ne 'docker' }).Count -gt 0

    if ($usesNewContract) {
        if ((-not $Target -or $Target.Count -eq 0) -and $Action -notin @('Status', 'Restore')) {
            throw (New-SwitchMirrorsException -Message 'Target 为必填参数')
        }

        Import-SwitchMirrorsPackageSourceModule
        $effectiveAction = $Action
        $effectiveMode = $Mode
        if ($WhatIfPreference) {
            switch ($Action) {
                'Apply' {
                    $effectiveAction = 'Plan'
                }
                'Ensure' {
                    if ([string]::IsNullOrWhiteSpace($TransactionId)) {
                        throw (New-SwitchMirrorsException -Message 'Ensure -WhatIf 必须提供 TransactionId')
                    }
                    $transactionStatus = Invoke-PackageSourceAction -Action Status -TransactionId $TransactionId
                    $effectiveMode = [string]$transactionStatus.Mode
                    $effectiveAction = 'Plan'
                }
                'Restore' {
                    $effectiveAction = 'Status'
                }
            }
        }

        $document = Invoke-PackageSourceAction -Action $effectiveAction -Mode $effectiveMode -Phase $Phase -Target @($Target) -TransactionId $TransactionId -Selection $Selection -Force:$Force -MirrorUrl $MirrorUrls -TimeoutSeconds $TimeoutSec -Retry $Retry
        $script:SwitchMirrorsExitCode = [int]$document.ExitCode
        if ($OutputFormat -eq 'Json') {
            Write-Output ($document | ConvertTo-Json -Depth 20)
            return
        }

        foreach ($result in $document.Results) {
            Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Target, $result.Message)
        }
        return
    }

    if (-not $Target -or $Target.Count -eq 0) {
        throw (New-SwitchMirrorsException -Message 'Target 为必填参数（当前兼容入口仅支持 Target=docker）')
    }
    if ($Target.Count -ne 1 -or $Target[0] -ne 'docker') {
        throw (New-SwitchMirrorsException -Message '兼容入口当前仅支持 Target=docker')
    }

    $results = Set-DockerRegistryMirror -MirrorUrls $MirrorUrls -UseChinaMirror:$UseChinaMirror -Disable:$Disable -DryRun:($DryRun -or $WhatIfPreference) -TimeoutSec $TimeoutSec -Retry $Retry
    foreach ($result in @($results)) {
        if ($result -is [string]) {
            Write-Output $result
        }
        elseif ($null -ne $result) {
            Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Target, $result.Message)
        }
    }
}

function New-SwitchMirrorsException {
    <#
    .SYNOPSIS
        创建公共入口使用的结构化参数异常。

    .PARAMETER Message
        面向用户的参数错误说明。

    .OUTPUTS
        System.ArgumentException。Data 中包含退出码与错误代码。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $exception = [System.ArgumentException]::new($Message)
    $exception.Data['ExitCode'] = 2
    $exception.Data['Code'] = 'InvalidArguments'
    return $exception
}

function Write-SwitchMirrorsError {
    <#
    .SYNOPSIS
        按当前输出格式写入公共入口错误。

    .PARAMETER ErrorRecord
        捕获到的 PowerShell ErrorRecord。

    .OUTPUTS
        int。应由脚本返回的退出码。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $exitCode = 1
    $errorCode = 'Failed'
    if ($ErrorRecord.Exception.Data.Contains('ExitCode')) {
        $exitCode = [int]$ErrorRecord.Exception.Data['ExitCode']
    }
    if ($ErrorRecord.Exception.Data.Contains('Code')) {
        $errorCode = [string]$ErrorRecord.Exception.Data['Code']
    }

    if ($OutputFormat -eq 'Json') {
        $document = [ordered]@{
            SchemaVersion = 1
            Action        = $Action
            Mode          = $Mode
            TransactionId = $TransactionId
            ExitCode      = $exitCode
            Results       = @()
            Error         = [ordered]@{
                Code    = $errorCode
                Message = $ErrorRecord.Exception.Message
            }
        }
        [Console]::Out.WriteLine(($document | ConvertTo-Json -Depth 10))
    }
    else {
        [Console]::Error.WriteLine($ErrorRecord.Exception.Message)
    }

    return $exitCode
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-Main
        exit $script:SwitchMirrorsExitCode
    }
    catch {
        exit (Write-SwitchMirrorsError -ErrorRecord $_)
    }
}
