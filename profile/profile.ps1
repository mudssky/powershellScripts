# PSScriptAnalyzer 抑制：PS 5.1 兼容性赋值，仅在 $IsWindows 未定义时执行
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', '')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
[CmdletBinding()]
param(
    [Parameter(HelpMessage = "是否将配置加载到 PowerShell 配置文件中")]
    [switch]$LoadProfile,
    [string]$AliasDescPrefix = '[mudssky]'
)

# PowerShell 5.1 兼容性：$IsWindows 等变量未定义时回退
if ($null -eq $IsWindows) { $IsWindows = $true; $IsLinux = $false; $IsMacOS = $false }

$profileLoadStartTime = Get-Date
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

$script:ProfileModeDecision = Get-ProfileModeDecision
$script:ProfileMode = [string]$script:ProfileModeDecision.Mode
$script:UseMinimalProfile = $script:ProfileMode -eq 'Minimal'
$script:UseUltraMinimalProfile = $script:ProfileMode -eq 'UltraMinimal'

. $script:InvokeProfileCoreLoaders

# === 主执行逻辑 ===
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

# 加载耗时统计
$profileLoadEndTime = Get-Date
$profileLoadTime = ($profileLoadEndTime - $profileLoadStartTime).TotalMilliseconds
if ($profileLoadTime -gt 1000) {
    if (-not $script:UseMinimalProfile) {
        Write-Host "Profile 加载耗时: $($profileLoadTime) 毫秒" -ForegroundColor Green
    }
}
