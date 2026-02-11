[CmdletBinding()]
param(
    [Parameter(HelpMessage = "是否将配置加载到 PowerShell 配置文件中")]
    [switch]$LoadProfile,
    [string]$AliasDescPrefix = '[mudssky]'
)

# 运行时基线：仅支持 PowerShell 7+（pwsh）

# === 分阶段计时诊断 ===
$script:ProfileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$script:ProfileTimings = [ordered]@{}
$script:ProfileTimingEnabled = (
    $env:POWERSHELL_PROFILE_TIMING -eq '1' -or
    $env:POWERSHELL_PROFILE_TIMING -eq 'true'
)
# 供 mode.ps1 Write-ProfileModeDecisionSummary 引用
$profileLoadStartTime = [DateTime]::UtcNow

function script:Record-ProfileTiming {
    param([string]$Phase)
    $elapsed = $script:ProfileStopwatch.ElapsedMilliseconds
    $script:ProfileTimings[$Phase] = $elapsed
    $script:ProfileStopwatch.Restart()
    Write-Verbose "[Profile Timing] ${Phase}: ${elapsed}ms"
}

$script:ProfileRoot = $PSScriptRoot
$script:ProfileEntryScriptPath = $PSCommandPath

# 固定 dot-source 顺序：core -> mode decision -> loaders -> features
$coreEncodingScript = Join-Path $script:ProfileRoot 'core/encoding.ps1'
$coreModeScript = Join-Path $script:ProfileRoot 'core/mode.ps1'
$coreLoadersScript = Join-Path $script:ProfileRoot 'core/loaders.ps1'
$featureEnvironmentScript = Join-Path $script:ProfileRoot 'features/environment.ps1'
$featureHelpScript = Join-Path $script:ProfileRoot 'features/help.ps1'
$featureInstallScript = Join-Path $script:ProfileRoot 'features/install.ps1'

foreach ($scriptPath in @(
        $coreEncodingScript,
        $coreModeScript,
        $coreLoadersScript,
        $featureEnvironmentScript,
        $featureHelpScript,
        $featureInstallScript
    )) {
    try {
        . $scriptPath
    }
    catch {
        Write-Error "[profile/profile.ps1] dot-source 失败: $scriptPath :: $($_.Exception.Message)"
        throw
    }
}

Record-ProfileTiming -Phase 'dot-source-definitions'

$script:ProfileModeDecision = Get-ProfileModeDecision
$script:ProfileMode = [string]$script:ProfileModeDecision.Mode
$script:UseMinimalProfile = $script:ProfileMode -eq 'Minimal'
$script:UseUltraMinimalProfile = $script:ProfileMode -eq 'UltraMinimal'

Record-ProfileTiming -Phase 'mode-decision'

. $script:InvokeProfileCoreLoaders

Record-ProfileTiming -Phase 'core-loaders'

# === 主执行逻辑 ===
# 延迟加载防护栏：记录 Initialize-Environment 前 psutils 模块状态
# 仅在诊断模式下检测，避免正常使用时的额外开销
if ($script:ProfileTimingEnabled) {
    $__preInitPsutilsLoaded = [bool](Get-Module -Name 'psutils')
}

try {
    # 调用环境初始化函数
    Initialize-Environment

    # 如果指定了 LoadProfile 参数，则设置配置文件
    if ($LoadProfile) {
        Set-PowerShellProfile
    }
}
catch {
    Write-Error "脚本执行过程中出现错误: $($_.Exception.Message)"
}

# 延迟加载防护栏：检测 psutils 是否被意外全量加载
if ($script:ProfileTimingEnabled -and -not $__preInitPsutilsLoaded -and (Get-Module -Name 'psutils')) {
    Write-Warning "[性能守卫] psutils 在 Initialize-Environment 中被意外全量加载！延迟加载优化失效。请检查同步路径中是否引用了非核心模块函数。"
}

Record-ProfileTiming -Phase 'initialize-environment'

# === 加载耗时统计 ===
$totalMs = 0
foreach ($val in $script:ProfileTimings.Values) { $totalMs += $val }
$script:ProfileTimings['total'] = $totalMs

if ($script:ProfileTimingEnabled) {
    Write-Host "=== Profile 加载计时 ===" -ForegroundColor Cyan
    foreach ($entry in $script:ProfileTimings.GetEnumerator()) {
        $color = if ($entry.Value -gt 500) { 'Red' } elseif ($entry.Value -gt 200) { 'Yellow' } else { 'Green' }
        Write-Host ("  {0,-30} {1,6}ms" -f $entry.Key, $entry.Value) -ForegroundColor $color
    }
}
elseif ($totalMs -gt 1000) {
    if (-not $script:UseMinimalProfile) {
        Write-Host "Profile 加载耗时: $totalMs 毫秒" -ForegroundColor Green
    }
}
