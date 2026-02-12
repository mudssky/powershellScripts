#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Profile 完整性能诊断脚本 — 分步测量全部 4 个阶段及其子步骤的耗时。
.DESCRIPTION
    此脚本使用 -NoProfile 冷启动并手动重放 profile 完整加载流程，对每个阶段
    及其内部子步骤进行独立计时。用于定位性能回归或排查启动变慢的具体原因。

    4 个阶段：
    Phase 1: dot-source-definitions — 函数定义加载（6 个脚本文件）
    Phase 2: mode-decision — 模式判定（Full/Minimal/UltraMinimal）
    Phase 3: core-loaders — 核心模块加载 + 别名配置
    Phase 4: initialize-environment — 工具初始化（代理、编码、starship 等）

    常见使用场景:
    - 新增工具/别名后检查对启动速度的影响
    - 跨平台缓存问题排查（Linux/Windows 缓存交叉污染）
    - starship/zoxide 更新后的性能回归检测

    注意: 必须使用 -NoProfile 启动以避免 profile 被自动加载：
      pwsh -NoProfile -NoLogo -File <此脚本路径>
.EXAMPLE
    pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1
.EXAMPLE
    pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -SkipStarship
.EXAMPLE
    pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Phase 4
.NOTES
    不依赖 profile 已加载的任何状态，完全自包含。
#>
[CmdletBinding()]
param(
    [switch]$SkipStarship,
    [switch]$SkipZoxide,
    [switch]$SkipProxy,
    [switch]$SkipAliases,
    [ValidateRange(1, 4)]
    [int]$Phase = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# === 计时工具 ===
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$timings = [ordered]@{}
$phaseTimings = [ordered]@{}

function Lap {
    param([string]$Name)
    $timings[$Name] = $sw.ElapsedMilliseconds
    $sw.Restart()
}

function LapPhase {
    param([string]$Name)
    $phaseTimings[$Name] = $sw.ElapsedMilliseconds
    $sw.Restart()
}

# === 自动检测 profile 根目录 ===
$profileRoot = if ($PSScriptRoot) {
    $PSScriptRoot
}
else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

Write-Host "=== Profile 完整性能诊断 ===" -ForegroundColor Cyan
Write-Host "Profile root: $profileRoot" -ForegroundColor DarkGray
Write-Host "Platform: $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)" -ForegroundColor DarkGray
Write-Host "PowerShell: $($PSVersionTable.PSVersion)" -ForegroundColor DarkGray
Write-Host ""

# ╔══════════════════════════════════════════════╗
# ║  Phase 1: dot-source-definitions             ║
# ╚══════════════════════════════════════════════╝

$script:ProfileRoot = $profileRoot
$script:ProfileMode = 'Full'
$script:UseMinimalProfile = $false
$script:UseUltraMinimalProfile = $false
$AliasDescPrefix = '[mudssky]'
$profileLoadStartTime = [DateTime]::UtcNow

$sw.Restart()

. (Join-Path $profileRoot 'core/encoding.ps1')
Lap '1.1-encoding.ps1'

. (Join-Path $profileRoot 'core/mode.ps1')
Lap '1.2-mode.ps1'

. (Join-Path $profileRoot 'core/loaders.ps1')
Lap '1.3-loaders.ps1'

. (Join-Path $profileRoot 'features/environment.ps1')
Lap '1.4-environment.ps1'

. (Join-Path $profileRoot 'features/help.ps1')
Lap '1.5-help.ps1'

. (Join-Path $profileRoot 'features/install.ps1')
Lap '1.6-install.ps1'

# Phase 1 小计
$phase1Total = 0
foreach ($k in @('1.1-encoding.ps1', '1.2-mode.ps1', '1.3-loaders.ps1', '1.4-environment.ps1', '1.5-help.ps1', '1.6-install.ps1')) {
    $phase1Total += $timings[$k]
}
$phaseTimings['Phase 1: dot-source-definitions'] = $phase1Total

if ($Phase -eq 1) {
    Write-Host "=== Phase 1: dot-source-definitions 分步计时 ===" -ForegroundColor Cyan
    foreach ($e in $timings.GetEnumerator()) {
        $color = if ($e.Value -gt 100) { 'Red' } elseif ($e.Value -gt 30) { 'Yellow' } else { 'Green' }
        Write-Host ("  {0,-40} {1,6}ms" -f $e.Key, $e.Value) -ForegroundColor $color
    }
    Write-Host ("  {0,-40} {1,6}ms" -f 'SUBTOTAL', $phase1Total) -ForegroundColor Cyan
    return
}

# ╔══════════════════════════════════════════════╗
# ║  Phase 2: mode-decision                      ║
# ╚══════════════════════════════════════════════╝

$sw.Restart()

$script:ProfileModeDecision = Get-ProfileModeDecision
Lap '2.1-get-profile-mode-decision'

$script:ProfileMode = [string]$script:ProfileModeDecision.Mode
$script:UseMinimalProfile = $script:ProfileMode -eq 'Minimal'
$script:UseUltraMinimalProfile = $script:ProfileMode -eq 'UltraMinimal'
Lap '2.2-apply-mode-flags'

$phase2Total = 0
foreach ($k in @('2.1-get-profile-mode-decision', '2.2-apply-mode-flags')) {
    $phase2Total += $timings[$k]
}
$phaseTimings['Phase 2: mode-decision'] = $phase2Total

if ($Phase -eq 2) {
    Write-Host "=== Phase 2: mode-decision 分步计时 ===" -ForegroundColor Cyan
    $phase2Keys = @('2.1-get-profile-mode-decision', '2.2-apply-mode-flags')
    foreach ($k in $phase2Keys) {
        $v = $timings[$k]
        $color = if ($v -gt 100) { 'Red' } elseif ($v -gt 30) { 'Yellow' } else { 'Green' }
        Write-Host ("  {0,-40} {1,6}ms" -f $k, $v) -ForegroundColor $color
    }
    Write-Host ("  {0,-40} {1,6}ms" -f 'SUBTOTAL', $phase2Total) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Mode: $($script:ProfileMode) | Source: $($script:ProfileModeDecision.Source) | Reason: $($script:ProfileModeDecision.Reason)" -ForegroundColor DarkGray
    return
}

# ╔══════════════════════════════════════════════╗
# ║  Phase 3: core-loaders                       ║
# ╚══════════════════════════════════════════════╝

$sw.Restart()

# 3.1 loadModule.ps1 — 加载核心 psutils 子模块（平台条件化） + PSModulePath + OnIdle 注册
$loadModuleScript = Join-Path $profileRoot 'core/loadModule.ps1'
. $loadModuleScript
Lap '3.1-loadModule (core psutils + OnIdle)'

# 3.2 user_aliases.ps1 — 加载别名配置对象
$userAliasScript = Join-Path $profileRoot 'config/aliases/user_aliases.ps1'
$script:userAlias = . $userAliasScript
Lap '3.2-user_aliases config'

$phase3Total = 0
foreach ($k in @('3.1-loadModule (core psutils + OnIdle)', '3.2-user_aliases config')) {
    $phase3Total += $timings[$k]
}
$phaseTimings['Phase 3: core-loaders'] = $phase3Total

if ($Phase -eq 3) {
    Write-Host "=== Phase 3: core-loaders 分步计时 ===" -ForegroundColor Cyan
    $phase3Keys = @('3.1-loadModule (core psutils + OnIdle)', '3.2-user_aliases config')
    foreach ($k in $phase3Keys) {
        $v = $timings[$k]
        $color = if ($v -gt 100) { 'Red' } elseif ($v -gt 30) { 'Yellow' } else { 'Green' }
        Write-Host ("  {0,-40} {1,6}ms" -f $k, $v) -ForegroundColor $color
    }
    Write-Host ("  {0,-40} {1,6}ms" -f 'SUBTOTAL', $phase3Total) -ForegroundColor Cyan
    return
}

# ╔══════════════════════════════════════════════╗
# ║  Phase 4: initialize-environment             ║
# ╚══════════════════════════════════════════════╝

$sw.Restart()

# 4.1 设置项目根目录
$env:POWERSHELL_SCRIPTS_ROOT = Split-Path -Parent $profileRoot
Lap '4.01-env-root'

# 4.2 Linux PATH 同步
if ($IsLinux) {
    if (Test-Path -Path "/home/linuxbrew/.linuxbrew/bin") {
        $env:PATH += ":/home/linuxbrew/.linuxbrew/bin/"
    }
    try {
        Sync-PathFromBash -CacheSeconds (4 * 3600) -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Warning "同步 PATH 失败: $($_.Exception.Message)"
    }
}
Lap '4.02-linux-path-sync'

# 4.3 代理自动检测
if (-not $SkipProxy) {
    try {
        $proxyState = Invoke-WithCache `
            -Key "proxy-auto-detect" `
            -MaxAge ([TimeSpan]::FromMinutes(30)) `
            -CacheType Text `
            -ScriptBlock {
                Set-Proxy -Command auto
                if ($env:http_proxy) { 'on' } else { 'off' }
            }
        if ($proxyState -eq 'on' -and -not $env:http_proxy) {
            Set-Proxy -Command on
        }
    }
    catch {
        Set-Proxy -Command auto
    }
}
Lap '4.03-proxy-detect'

# 4.4 env.ps1
$envScript = Join-Path $profileRoot 'env.ps1'
if (Test-Path $envScript) { . $envScript }
Lap '4.04-env-ps1'

# 4.5 UTF-8 编码
Set-ProfileUtf8Encoding
Lap '4.05-utf8-encoding'

# 4.6 Get-Command 批量检测
$toolNames = @('starship', 'zoxide', 'sccache', 'fnm')
$availableTools = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
$foundCommands = Get-Command `
    -Name $toolNames `
    -CommandType Application `
    -ErrorAction SilentlyContinue
if ($foundCommands) {
    foreach ($cmd in $foundCommands) {
        $toolName = [System.IO.Path]::GetFileNameWithoutExtension($cmd.Name)
        $availableTools.Add($toolName) | Out-Null
    }
}
Lap '4.06-get-command'

# 4.7 starship
$platformId = if ($IsWindows) { 'win' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
$cacheDir = Join-Path $profileRoot '.cache'
if (-not $SkipStarship -and $availableTools.Contains('starship')) {
    $f = Invoke-WithFileCache `
        -Key "starship-init-powershell-$platformId" `
        -MaxAge ([TimeSpan]::FromDays(7)) `
        -Generator {
            $initScript = & starship init powershell --print-full-init
            try {
                $continuationPrompt = & starship prompt --continuation
                if ($continuationPrompt) {
                    $escaped = $continuationPrompt -replace "'", "''"
                    $pattern = 'Set-PSReadLineOption -ContinuationPrompt \(\s*Invoke-Native -Executable .+? -Arguments @\(\s*"prompt",\s*"--continuation"\s*\)\s*\)'
                    $replacement = "Set-PSReadLineOption -ContinuationPrompt '$escaped'"
                    $result = [regex]::Replace($initScript, $pattern, $replacement, [System.Text.RegularExpressions.RegexOptions]::Singleline)
                    if ($result -ne $initScript) { $initScript = $result }
                }
            }
            catch {}
            $initScript
        } `
        -BaseDir $cacheDir
    . $f
}
Lap '4.07-starship'

# 4.8 zoxide
if (-not $SkipZoxide -and $availableTools.Contains('zoxide')) {
    $f = Invoke-WithFileCache `
        -Key "zoxide-init-powershell-$platformId" `
        -MaxAge ([TimeSpan]::FromDays(7)) `
        -Generator { zoxide init powershell } `
        -BaseDir $cacheDir
    . $f
}
Lap '4.08-zoxide'

# 4.9 sccache（跨平台）
if ($availableTools.Contains('sccache')) {
    $env:RUSTC_WRAPPER = 'sccache'
}
Lap '4.09-sccache'

# 4.10 fnm (仅 Unix)
if (-not $IsWindows -and $availableTools.Contains('fnm')) {
    $fnmInitFile = Join-Path ([System.IO.Path]::GetTempPath()) "fnm-init-$PID.ps1"
    try {
        fnm env --shell=power-shell --use-on-cd | Set-Content -Path $fnmInitFile -Encoding utf8NoBOM
        . $fnmInitFile
    }
    finally {
        Remove-Item -Path $fnmInitFile -Force -ErrorAction SilentlyContinue
    }
}
Lap '4.10-fnm'

# 4.11 别名注册
if (-not $SkipAliases) {
    Set-AliasProfile
}
Lap '4.11-alias-profile'

# Phase 4 小计
$phase4Total = 0
$phase4Keys = @(
    '4.01-env-root', '4.02-linux-path-sync', '4.03-proxy-detect', '4.04-env-ps1',
    '4.05-utf8-encoding', '4.06-get-command', '4.07-starship', '4.08-zoxide',
    '4.09-sccache', '4.10-fnm', '4.11-alias-profile'
)
foreach ($k in $phase4Keys) {
    $phase4Total += $timings[$k]
}
$phaseTimings['Phase 4: initialize-environment'] = $phase4Total

# ╔══════════════════════════════════════════════╗
# ║  输出报告                                     ║
# ╚══════════════════════════════════════════════╝

# === 阶段总览 ===
Write-Host "=== 阶段总览 ===" -ForegroundColor Cyan
$grandTotal = 0
foreach ($e in $phaseTimings.GetEnumerator()) {
    $grandTotal += $e.Value
    $color = if ($e.Value -gt 300) { 'Red' } elseif ($e.Value -gt 100) { 'Yellow' } else { 'Green' }
    Write-Host ("  {0,-40} {1,6}ms" -f $e.Key, $e.Value) -ForegroundColor $color
}
Write-Host ("  {0,-40} {1,6}ms" -f 'TOTAL', $grandTotal) -ForegroundColor Cyan

# === 分步明细 ===
Write-Host ""
Write-Host "=== 分步明细 ===" -ForegroundColor Cyan
foreach ($e in $timings.GetEnumerator()) {
    $color = if ($e.Value -gt 100) { 'Red' }
    elseif ($e.Value -gt 30) { 'Yellow' }
    else { 'Green' }
    $line = "  {0,-40} {1,6}ms" -f $e.Key, $e.Value
    Write-Host $line -ForegroundColor $color
}
Write-Host ("  {0,-40} {1,6}ms" -f 'TOTAL', $grandTotal) -ForegroundColor Cyan

# === 环境信息 ===
Write-Host ""
Write-Host "=== 环境信息 ===" -ForegroundColor Cyan
Write-Host "  Profile mode: $($script:ProfileMode) (source: $($script:ProfileModeDecision.Source), reason: $($script:ProfileModeDecision.Reason))" -ForegroundColor DarkGray
Write-Host "  Detected tools: $($availableTools -join ', ')" -ForegroundColor DarkGray
Write-Host "  Platform cache ID: $platformId" -ForegroundColor DarkGray

# === 缓存文件信息 ===
Write-Host ""
Write-Host "=== 缓存文件状态 ===" -ForegroundColor Cyan
$cacheFiles = Get-ChildItem -Path $cacheDir -Filter '*.ps1' -ErrorAction SilentlyContinue
if ($cacheFiles) {
    foreach ($cf in $cacheFiles) {
        $age = (Get-Date) - $cf.LastWriteTime
        $ageStr = if ($age.TotalDays -ge 1) { "{0:N1} 天" -f $age.TotalDays }
        elseif ($age.TotalHours -ge 1) { "{0:N1} 小时" -f $age.TotalHours }
        else { "{0:N0} 分钟" -f $age.TotalMinutes }
        $sizeKb = "{0:N1} KB" -f ($cf.Length / 1024)
        Write-Host ("  {0,-45} {1,8}  age: {2}" -f $cf.Name, $sizeKb, $ageStr) -ForegroundColor DarkGray
    }
}
else {
    Write-Host "  (无缓存文件)" -ForegroundColor DarkGray
}

# === 性能建议 ===
Write-Host ""
$issues = @()
foreach ($e in $timings.GetEnumerator()) {
    if ($e.Value -gt 200) {
        $issues += $e
    }
}
if ($issues.Count -gt 0) {
    Write-Host "=== 性能警告 ===" -ForegroundColor Yellow
    foreach ($issue in $issues) {
        Write-Host "  ⚠ $($issue.Key): $($issue.Value)ms — 超过 200ms 阈值" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  排查建议:" -ForegroundColor DarkGray
    Write-Host "  - 如果 starship/zoxide 偏高：删除 .cache/ 下对应文件重新生成" -ForegroundColor DarkGray
    Write-Host "  - 如果 proxy-detect 偏高：检查代理端口是否可达或延长缓存时间" -ForegroundColor DarkGray
    Write-Host "  - 如果 utf8-encoding 偏高：检查是否有 PSReadLine 操作泄漏到同步路径" -ForegroundColor DarkGray
    Write-Host "  - 如果 get-command 偏高：检查 PATH 中是否有过多条目" -ForegroundColor DarkGray
    Write-Host "  - 如果 dot-source 某文件偏高：该文件可能在定义阶段执行了逻辑，应延迟到调用时" -ForegroundColor DarkGray
    Write-Host "  - 如果 loadModule 偏高：检查核心模块数量或 PSModulePath 条目数" -ForegroundColor DarkGray
    Write-Host "  - 如果 linux-path-sync 偏高：检查 Bash PATH 同步缓存是否过期" -ForegroundColor DarkGray
}
else {
    Write-Host "✅ 所有步骤均在 200ms 阈值内" -ForegroundColor Green
}
