#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Profile 性能诊断脚本 — 分步测量 Initialize-Environment 各阶段耗时。
.DESCRIPTION
    此脚本使用 -NoProfile 冷启动并手动 dot-source profile 各层，对 Initialize-Environment
    内部的每个子步骤进行独立计时。用于定位性能回归或排查启动变慢的具体原因。

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
.NOTES
    不依赖 profile 已加载的任何状态，完全自包含。
#>
[CmdletBinding()]
param(
    [switch]$SkipStarship,
    [switch]$SkipZoxide,
    [switch]$SkipProxy,
    [switch]$SkipAliases
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# === 计时工具 ===
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$timings = [ordered]@{}

function Lap {
    param([string]$Name)
    $timings[$Name] = $sw.ElapsedMilliseconds
    $sw.Restart()
}

# === 自动检测 profile 根目录 ===
$profileRoot = if ($PSScriptRoot) {
    $PSScriptRoot
}
else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

Write-Host "=== Profile 性能诊断 ===" -ForegroundColor Cyan
Write-Host "Profile root: $profileRoot" -ForegroundColor DarkGray
Write-Host "Platform: $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)" -ForegroundColor DarkGray
Write-Host ""

# === Phase 1-3: 加载前置依赖 ===
$script:ProfileRoot = $profileRoot
$script:ProfileMode = 'Full'
$script:UseMinimalProfile = $false
$script:UseUltraMinimalProfile = $false
$AliasDescPrefix = '[mudssky]'

. (Join-Path $profileRoot 'core/encoding.ps1')
. (Join-Path $profileRoot 'core/mode.ps1')
. (Join-Path $profileRoot 'core/loaders.ps1')
. (Join-Path $profileRoot 'features/environment.ps1')
. (Join-Path $profileRoot 'features/help.ps1')
. (Join-Path $profileRoot 'features/install.ps1')
. $script:InvokeProfileCoreLoaders
Lap 'prerequisites (phases 1-3)'

# === Initialize-Environment 分步计时 ===

# 1. 设置项目根目录
$env:POWERSHELL_SCRIPTS_ROOT = Split-Path -Parent $profileRoot
Lap '1-env-root'

# 2. 代理自动检测
if (-not $SkipProxy) {
    try {
        $maxAge = [TimeSpan]::FromMinutes(5)
        $proxyBlock = {
            Set-Proxy -Command auto
            if ($env:http_proxy) { 'on' } else { 'off' }
        }
        $proxyState = Invoke-WithCache `
            -Key "proxy-auto-detect" `
            -MaxAge $maxAge `
            -CacheType Text `
            -ScriptBlock $proxyBlock
        if ($proxyState -eq 'on' -and -not $env:http_proxy) {
            Set-Proxy -Command on
        }
    }
    catch {
        Set-Proxy -Command auto
    }
}
Lap '2-proxy-detect'

# 3. env.ps1
$envScript = Join-Path $profileRoot 'env.ps1'
if (Test-Path $envScript) { . $envScript }
Lap '3-env-ps1'

# 4. UTF-8 编码
Set-ProfileUtf8Encoding
Lap '4-utf8-encoding'

# 5. Get-Command 批量检测
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
Lap '5-get-command'

# 6. starship
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
Lap '6-starship'

# 7. zoxide
if (-not $SkipZoxide -and $availableTools.Contains('zoxide')) {
    $f = Invoke-WithFileCache `
        -Key "zoxide-init-powershell-$platformId" `
        -MaxAge ([TimeSpan]::FromDays(7)) `
        -Generator { zoxide init powershell } `
        -BaseDir $cacheDir
    . $f
}
Lap '7-zoxide'

# 8. sccache
if ($availableTools.Contains('sccache') -and $IsWindows) {
    $env:RUSTC_WRAPPER = 'sccache'
}
Lap '8-sccache'

# 9. fnm (仅 Unix)
if (-not $IsWindows -and $availableTools.Contains('fnm')) {
    $fnmInitFile = Join-Path ([System.IO.Path]::GetTempPath()) "fnm-init-$PID.ps1"
    try {
        fnm env --use-on-cd | Set-Content -Path $fnmInitFile -Encoding utf8NoBOM
        . $fnmInitFile
    }
    finally {
        Remove-Item -Path $fnmInitFile -Force -ErrorAction SilentlyContinue
    }
}
Lap '9-fnm'

# 10. 别名注册
if (-not $SkipAliases) {
    Set-AliasProfile
}
Lap '10-alias-profile'

# === 输出报告 ===
Write-Host ""
Write-Host "=== Initialize-Environment 分步计时 ===" -ForegroundColor Cyan
$total = 0
foreach ($e in $timings.GetEnumerator()) {
    $total += $e.Value
    $color = if ($e.Value -gt 100) { 'Red' }
    elseif ($e.Value -gt 30) { 'Yellow' }
    else { 'Green' }
    $line = "  {0,-35} {1,6}ms" -f $e.Key, $e.Value
    Write-Host $line -ForegroundColor $color
}
Write-Host ("  {0,-35} {1,6}ms" -f 'TOTAL', $total) -ForegroundColor Cyan

Write-Host ""
Write-Host "Detected tools: $($availableTools -join ', ')" -ForegroundColor DarkGray
Write-Host "Platform cache ID: $platformId" -ForegroundColor DarkGray

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
    if ($e.Key -eq 'prerequisites (phases 1-3)') { continue }
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
}
else {
    Write-Host "✅ 所有步骤均在 200ms 阈值内" -ForegroundColor Green
}
