[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(HelpMessage = '是否将配置加载到 PowerShell 配置文件中')]
    [switch]$LoadProfile,
    [string]$AliasDescPrefix = '[mudssky]',
    [switch]$SkipTools,
    [switch]$SkipProxy,
    [switch]$SkipStarship,
    [switch]$SkipZoxide,
    [switch]$SkipAliases,
    [string]$TimingOutputPath
)

# 运行时基线：仅支持 PowerShell 7+（pwsh）
$script:ProfileRoot = $PSScriptRoot
$script:ProfileEntryScriptPath = $PSCommandPath
$script:ProfileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$script:ProfileTimings = [ordered]@{}
$script:ProfileTimingConsoleEnabled = (
    $env:POWERSHELL_PROFILE_TIMING -eq '1' -or
    $env:POWERSHELL_PROFILE_TIMING -eq 'true'
)
$script:ProfileTimingEnabled = $script:ProfileTimingConsoleEnabled -or -not [string]::IsNullOrWhiteSpace($TimingOutputPath)
$script:ProfileExtendedFeaturesLoaded = $false
$script:ProfileFallback = $null
$profileLoadStartTime = [DateTime]::UtcNow

function script:Complete-ProfileTiming {
    <#
    .SYNOPSIS
        完成 Profile 计时并按需输出结构化报告。

    .PARAMETER OutputPath
        可选 JSON 报告路径。

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        返回当前 Profile 运行的结构化计时报告。
    #>
    [CmdletBinding()]
    param(
        [string]$OutputPath
    )

    $totalMs = 0
    foreach ($value in $script:ProfileTimings.Values) {
        $totalMs += [long]$value
    }
    $script:ProfileTimings['total'] = $totalMs

    $report = [PSCustomObject]@{
        GeneratedAt       = (Get-Date).ToString('o')
        Platform          = [string]$script:ProfilePlatformContext.Id
        PowerShellVersion = [string]$PSVersionTable.PSVersion
        RequestedMode     = [string]$script:RequestedProfileMode
        FinalMode         = [string]$script:ProfileMode
        ModeSource        = [string]$script:ProfileModeDecision.Source
        ModeReason        = [string]$script:ProfileModeDecision.Reason
        Fallback          = $script:ProfileFallback
        ProcessId         = $PID
        Timings           = [PSCustomObject]$script:ProfileTimings
        ProfileInternalMs = $totalMs
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        $outputDirectory = Split-Path -Parent $resolvedOutputPath
        if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
            New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
        }
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutputPath -Encoding utf8NoBOM
    }

    if ($script:ProfileTimingConsoleEnabled) {
        Write-Host '=== Profile 加载计时 ===' -ForegroundColor Cyan
        foreach ($entry in $script:ProfileTimings.GetEnumerator()) {
            $color = if ($entry.Value -gt 500) { 'Red' } elseif ($entry.Value -gt 200) { 'Yellow' } else { 'Green' }
            Write-Host ("  {0,-30} {1,6}ms" -f $entry.Key, $entry.Value) -ForegroundColor $color
        }
    }
    elseif ($totalMs -gt 1000 -and $script:ProfileMode -eq 'Full') {
        Write-Host "Profile 加载耗时: $totalMs 毫秒" -ForegroundColor Green
    }

    return $report
}

function script:Invoke-ProfileFallback {
    <#
    .SYNOPSIS
        将 Full 或 Minimal 的必需组件失败降级为 UltraMinimal。

    .PARAMETER Component
        失败组件标识。

    .PARAMETER ErrorRecord
        原始 PowerShell 错误记录。

    .OUTPUTS
        System.Void
        更新最终模式并执行最小 bootstrap。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component,
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $fallbackReason = 'fallback_' + ($Component -replace '[^A-Za-z0-9]+', '_').Trim('_').ToLowerInvariant()
    Write-Warning ("[ProfileFallback] component={0} error={1} final_mode=UltraMinimal" -f $Component, $ErrorRecord.Exception.Message)

    $script:ProfileFallback = [PSCustomObject]@{
        Component = $Component
        Error     = $ErrorRecord.Exception.Message
        FinalMode = 'UltraMinimal'
    }
    $script:ProfileMode = 'UltraMinimal'
    $script:UseMinimalProfile = $false
    $script:UseUltraMinimalProfile = $true
    $script:ProfileExtendedFeaturesLoaded = $false
    $script:ProfileModeDecision.Mode = 'UltraMinimal'
    $script:ProfileModeDecision.Source = 'fallback'
    $script:ProfileModeDecision.Reason = $fallbackReason
    $script:ProfileModeDecision.Markers = @($script:ProfileModeDecision.Markers + "fallback:$Component")

    Initialize-ProfileBootstrap -ProfileRoot $script:ProfileRoot -PlatformContext $script:ProfilePlatformContext
    Write-ProfileModeDecisionSummary
    Write-ProfileModeFallbackGuide -VerboseOnly
}

# bootstrap 定义失败意味着无法保证最小 Profile 行为，必须显式终止本次初始化。
$requiredBootstrapScripts = @(
    (Join-Path $script:ProfileRoot 'core/encoding.ps1'),
    (Join-Path $script:ProfileRoot 'core/bootstrap.ps1'),
    (Join-Path $script:ProfileRoot 'core/mode.ps1'),
    (Join-Path $script:ProfileRoot 'core/platform.ps1')
)
foreach ($scriptPath in $requiredBootstrapScripts) {
    try {
        . $scriptPath
    }
    catch {
        Write-Error "[profile/profile.ps1] bootstrap 定义加载失败: $scriptPath :: $($_.Exception.Message)"
        throw
    }
}
$script:ProfileTimings['bootstrap-definitions'] = $script:ProfileStopwatch.ElapsedMilliseconds
$script:ProfileStopwatch.Restart()

try {
    $script:ProfileModeDecision = Get-ProfileModeDecision
    $script:ProfileMode = [string]$script:ProfileModeDecision.Mode
    $script:RequestedProfileMode = $script:ProfileMode
    $script:UseMinimalProfile = $script:ProfileMode -eq 'Minimal'
    $script:UseUltraMinimalProfile = $script:ProfileMode -eq 'UltraMinimal'
    $script:ProfilePlatformContext = Get-ProfilePlatformContext
}
catch {
    Write-Error "[profile/profile.ps1] 模式或平台判定失败: $($_.Exception.Message)"
    throw
}
$script:ProfileTimings['mode-and-platform-decision'] = $script:ProfileStopwatch.ElapsedMilliseconds
$script:ProfileStopwatch.Restart()

# Help 与 Install 是轻量公共 API；加载失败只降低对应能力，不阻塞基础 Profile。
foreach ($optionalScriptPath in @(
        (Join-Path $script:ProfileRoot 'features/help.ps1'),
        (Join-Path $script:ProfileRoot 'features/install.ps1')
    )) {
    try {
        . $optionalScriptPath
    }
    catch {
        Write-Warning "[profile/profile.ps1] 可选定义加载失败，已跳过: $optionalScriptPath :: $($_.Exception.Message)"
    }
}
$script:ProfileTimings['public-api-definitions'] = $script:ProfileStopwatch.ElapsedMilliseconds
$script:ProfileStopwatch.Restart()

if ($script:UseUltraMinimalProfile) {
    Initialize-ProfileBootstrap -ProfileRoot $script:ProfileRoot -PlatformContext $script:ProfilePlatformContext
    Write-ProfileModeDecisionSummary
    Write-ProfileModeFallbackGuide -VerboseOnly
    $script:ProfileTimings['initialize-bootstrap'] = $script:ProfileStopwatch.ElapsedMilliseconds
    $script:ProfileStopwatch.Restart()
    $script:ProfileTimingReport = Complete-ProfileTiming -OutputPath $TimingOutputPath
    return
}

$requiredRuntimeScripts = @(
    (Join-Path $script:ProfileRoot 'core/loadModule.ps1'),
    (Join-Path $script:ProfileRoot 'core/loaders.ps1'),
    (Join-Path $script:ProfileRoot 'features/environment.ps1')
)
try {
    foreach ($scriptPath in $requiredRuntimeScripts) {
        . $scriptPath
    }
}
catch {
    Invoke-ProfileFallback -Component 'runtime-definitions' -ErrorRecord $_
    $script:ProfileTimings['runtime-definitions-fallback'] = $script:ProfileStopwatch.ElapsedMilliseconds
    $script:ProfileStopwatch.Restart()
    $script:ProfileTimingReport = Complete-ProfileTiming -OutputPath $TimingOutputPath
    return
}
$script:ProfileTimings['runtime-definitions'] = $script:ProfileStopwatch.ElapsedMilliseconds
$script:ProfileStopwatch.Restart()

try {
    $script:ProfileLoaderResult = Invoke-ProfileCoreLoaders `
        -ProfileRoot $script:ProfileRoot `
        -Mode $script:ProfileMode `
        -PlatformContext $script:ProfilePlatformContext
}
catch {
    Invoke-ProfileFallback -Component 'core-loaders' -ErrorRecord $_
    $script:ProfileTimings['core-loaders-fallback'] = $script:ProfileStopwatch.ElapsedMilliseconds
    $script:ProfileStopwatch.Restart()
    $script:ProfileTimingReport = Complete-ProfileTiming -OutputPath $TimingOutputPath
    return
}
$script:ProfileTimings['core-loaders'] = $script:ProfileStopwatch.ElapsedMilliseconds
$script:ProfileStopwatch.Restart()

# 延迟加载防护栏只在诊断模式启用，避免正常启动增加额外模块查询。
if ($script:ProfileTimingEnabled) {
    $__preInitPsutilsLoaded = [bool](Get-Module -Name 'psutils')
}

try {
    Initialize-Environment `
        -ScriptRoot $script:ProfileRoot `
        -ProfileMode $script:ProfileMode `
        -PlatformContext $script:ProfilePlatformContext `
        -SkipTools:$SkipTools `
        -SkipProxy:$SkipProxy `
        -SkipStarship:$SkipStarship `
        -SkipZoxide:$SkipZoxide `
        -SkipAliases:$SkipAliases

    if ($LoadProfile) {
        if (Get-Command -Name Set-PowerShellProfile -CommandType Function -ErrorAction SilentlyContinue) {
            $null = Set-PowerShellProfile
        }
        else {
            Write-Warning 'Set-PowerShellProfile 不可用，已跳过 -LoadProfile 请求'
        }
    }
}
catch {
    Invoke-ProfileFallback -Component 'initialize-environment' -ErrorRecord $_
    $script:ProfileTimings['initialize-environment-fallback'] = $script:ProfileStopwatch.ElapsedMilliseconds
    $script:ProfileStopwatch.Restart()
    $script:ProfileTimingReport = Complete-ProfileTiming -OutputPath $TimingOutputPath
    return
}

if ($script:ProfileTimingEnabled -and -not $__preInitPsutilsLoaded -and (Get-Module -Name 'psutils')) {
    Write-Warning '[性能守卫] psutils 在 Initialize-Environment 中被意外全量加载！延迟加载优化失效。请检查同步路径中是否引用了非核心模块函数。'
}

$script:ProfileTimings['initialize-environment'] = $script:ProfileStopwatch.ElapsedMilliseconds
$script:ProfileStopwatch.Restart()
$script:ProfileTimingReport = Complete-ProfileTiming -OutputPath $TimingOutputPath
