<#
.SYNOPSIS
    流水线步骤 10（login-items）：幂等配置 Windows 开机自启的 WSL SSH 管理链路。

.DESCRIPTION
    薄封装 windows/wsl/Initialize-WslSshAccess.ps1：推断参数默认值、执行前置检查后，
    以 -Apply 委托既有机制层注册 AtStartup+S4U 计划任务、firewall rule 和长驻 TCP relay
    （Windows 2222 -> WSL sshd 2223）。本脚本不实现任何新机制；只读验证与回滚仍由
    Initialize-WslSshAccess.ps1 的 -Verify/-Rollback 提供（见 windows/INSTALL.md）。

    前置不足（非 Windows 宿主、wsl.exe 缺失或无已注册发行版、build < 22621、无法定位
    控制器公钥）返回 Blocked/10，不静默回退。-WhatIf 只输出解析后的执行计划；探测均为
    只读，缺失项以预览注意项呈现，零落盘退出 0。

.PARAMETER Distribution
    WSL 发行版名称；缺省取 `wsl -l -q` 的首个发行版。

.PARAMETER WindowsUser
    运行 AtStartup S4U task 的 Windows 用户；缺省取当前用户。

.PARAMETER LinuxUser
    WSL SSH 用户；缺省取当前用户。

.PARAMETER ListenAddress
    Windows relay 监听地址，默认 0.0.0.0。

.PARAMETER ListenPort
    Windows 监听端口，默认 2222。

.PARAMETER GuestPort
    WSL sshd 端口，默认 2223，以避开 Windows OpenSSH 22。

.PARAMETER AuthorizedKeyPath
    控制器公钥文件；缺省按 id_ed25519.pub、id_rsa.pub、id_ecdsa.pub 的顺序在 ~\.ssh 中发现。

.PARAMETER OutputFormat
    转发给机制层的输出格式，Text 或 Json。

.OUTPUTS
    文本计划或机制层单文档输出；成功/已满足/预览 0、执行失败 1、参数错误 2、Blocked 10。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Distribution = '',

    [string]$WindowsUser = $(if ($env:USERNAME) { $env:USERNAME } elseif ($env:USER) { $env:USER } else { '' }),

    [string]$LinuxUser = $(if ($env:USERNAME) { $env:USERNAME } elseif ($env:USER) { $env:USER } else { '' }),

    [string]$ListenAddress = '0.0.0.0',

    [int]$ListenPort = 2222,

    [int]$GuestPort = 2223,

    [string]$AuthorizedKeyPath = '',

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# .wslconfig mirrored + hostAddressLoopback 底座要求的最低 Windows build。
$script:MinimumWslBuild = 22621

function Get-WslAutostartDistributionNames {
    <#
    .SYNOPSIS
        只读枚举已注册 WSL 发行版名称。
    .OUTPUTS
        System.String[]。wsl.exe 缺失或失败时为空数组。
    #>
    [CmdletBinding()]
    param()

    $wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($null -eq $wslCommand) {
        return @()
    }
    $listing = @(& wsl.exe --list --quiet 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return @()
    }
    # wsl.exe 在部分宿主输出 UTF-16/NUL 文本，与机制层 ConvertFrom-WslSshText 保持一致清理。
    return @($listing | ForEach-Object { ([string]$_) -replace [char]0, '' } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Resolve-WslAutostartPublicKeyPath {
    <#
    .SYNOPSIS
        解析控制器公钥路径；显式路径必须存在，缺省按固定顺序在 ~\.ssh 发现。
    .OUTPUTS
        PSCustomObject。Path 为命中路径（未命中为空），Note 为未命中原因。
    #>
    [CmdletBinding()]
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
            return [pscustomobject]@{ Path = $ExplicitPath; Note = '' }
        }
        return [pscustomobject]@{ Path = ''; Note = "指定的 AuthorizedKeyPath 不存在: $ExplicitPath" }
    }
    $userProfile = if ($env:USERPROFILE) { $env:USERPROFILE } else { '' }
    if ([string]::IsNullOrWhiteSpace($userProfile)) {
        return [pscustomobject]@{ Path = ''; Note = '无法定位用户目录，无法自动发现控制器公钥' }
    }
    foreach ($keyName in @('id_ed25519.pub', 'id_rsa.pub', 'id_ecdsa.pub')) {
        $candidate = Join-Path $userProfile (Join-Path '.ssh' $keyName)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [pscustomobject]@{ Path = $candidate; Note = '' }
        }
    }
    return [pscustomobject]@{
        Path = ''
        Note = '~\.ssh 下未发现控制器公钥（id_ed25519.pub/id_rsa.pub/id_ecdsa.pub），请用 -AuthorizedKeyPath 指定'
    }
}

$initializeScriptPath = Join-Path $PSScriptRoot 'wsl/Initialize-WslSshAccess.ps1'
if (-not (Test-Path -LiteralPath $initializeScriptPath -PathType Leaf)) {
    [Console]::Error.WriteLine("缺少机制层入口: $initializeScriptPath")
    exit 1
}

# -WhatIf 预览：探测只读且容忍缺失（含用户/公钥未解析），输出解析后的计划即退出，不落盘。
if ($WhatIfPreference) {
    $previewNotes = [System.Collections.Generic.List[string]]::new()
    $resolvedWindowsUser = $WindowsUser
    $resolvedLinuxUser = $LinuxUser
    if ([string]::IsNullOrWhiteSpace($resolvedWindowsUser)) {
        $resolvedWindowsUser = '(当前用户)'
        $previewNotes.Add('无法解析当前用户；真实执行时需显式传入 -WindowsUser 与 -LinuxUser')
    }
    if ([string]::IsNullOrWhiteSpace($resolvedLinuxUser)) {
        $resolvedLinuxUser = '(当前用户)'
    }
    $resolvedDistribution = $Distribution
    if ([string]::IsNullOrWhiteSpace($resolvedDistribution)) {
        $probedDistributions = @(Get-WslAutostartDistributionNames | Select-Object -First 1)
        if ($probedDistributions.Count -gt 0) {
            $resolvedDistribution = [string]$probedDistributions[0]
        }
        else {
            $resolvedDistribution = '(wsl -l -q 首个发行版)'
            $previewNotes.Add('当前环境无法枚举 WSL 发行版；真实执行时自动推断，缺失则 Blocked/10')
        }
    }
    $keyResolution = Resolve-WslAutostartPublicKeyPath -ExplicitPath $AuthorizedKeyPath
    # 计划行回显真实透传参数：显式路径按原值显示，缺省自动发现未命中时以占位符呈现。
    $resolvedKeyPath = if (-not [string]::IsNullOrWhiteSpace($AuthorizedKeyPath)) {
        $AuthorizedKeyPath
    }
    elseif ($keyResolution.Path) {
        $keyResolution.Path
    }
    else {
        '(自动发现控制器公钥)'
    }
    if (-not [string]::IsNullOrWhiteSpace($keyResolution.Note)) {
        $previewNotes.Add($keyResolution.Note)
    }
    Write-Output '[Preview] 步骤10 login-items：WSL SSH 开机自启（-WhatIf 零落盘）'
    Write-Output ('[Preview] 将调用: windows/wsl/Initialize-WslSshAccess.ps1 -Distribution {0} -WindowsUser {1} -LinuxUser {2} -ListenAddress {3} -ListenPort {4} -GuestPort {5} -AuthorizedKeyPath {6} -OutputFormat {7} -Apply' -f `
            $resolvedDistribution, $resolvedWindowsUser, $resolvedLinuxUser, $ListenAddress, $ListenPort, $GuestPort, $resolvedKeyPath, $OutputFormat)
    foreach ($previewNote in $previewNotes) {
        Write-Output "[Preview] 注意: $previewNote"
    }
    exit 0
}

# 真实执行前置检查：任何缺失项合并为一次 Blocked/10，不静默回退。
# WSL/build 前置优先于参数校验：两者同时成立时必须返回 Blocked/10（PRD 主契约）。
$blockedReasons = [System.Collections.Generic.List[string]]::new()
if ($env:OS -ne 'Windows_NT') {
    $blockedReasons.Add('WSL SSH 自启需要 Windows 宿主（当前会话不是 Windows）')
}
else {
    $registeredDistributions = @(Get-WslAutostartDistributionNames)
    if ($registeredDistributions.Count -eq 0) {
        $blockedReasons.Add('wsl.exe 不可用或没有已注册的 WSL 发行版')
    }
    $currentBuild = [Environment]::OSVersion.Version.Build
    if ($currentBuild -lt $script:MinimumWslBuild) {
        $blockedReasons.Add("需要 build $script:MinimumWslBuild+（mirrored 网络底座），当前 build $currentBuild")
    }
}
if ($blockedReasons.Count -gt 0) {
    foreach ($blockedReason in $blockedReasons) {
        [Console]::Error.WriteLine($blockedReason)
    }
    Write-Output '[Blocked] wsl-autostart: 前置条件不足，未做任何修改'
    exit 10
}

# 用户参数校验位于环境前置之后：仅当 WSL 前置已满足时才可能到达，仍属真实执行段（参数错误 2）。
if ([string]::IsNullOrWhiteSpace($WindowsUser) -or [string]::IsNullOrWhiteSpace($LinuxUser)) {
    [Console]::Error.WriteLine('无法解析当前 Windows/WSL 用户，请显式传入 -WindowsUser 与 -LinuxUser')
    exit 2
}

if ([string]::IsNullOrWhiteSpace($Distribution)) {
    $Distribution = [string]@(Get-WslAutostartDistributionNames | Select-Object -First 1)[0]
    Write-Output "[Info] 未指定 -Distribution，自动选择首个发行版: $Distribution"
}

if ([string]::IsNullOrWhiteSpace($AuthorizedKeyPath)) {
    $keyResolution = Resolve-WslAutostartPublicKeyPath -ExplicitPath ''
    if (-not $keyResolution.Path) {
        [Console]::Error.WriteLine($keyResolution.Note)
        Write-Output '[Blocked] wsl-autostart: 无法定位控制器公钥'
        exit 10
    }
    $AuthorizedKeyPath = $keyResolution.Path
    Write-Output "[Info] 自动发现控制器公钥: $AuthorizedKeyPath"
}
elseif (-not (Test-Path -LiteralPath $AuthorizedKeyPath -PathType Leaf)) {
    [Console]::Error.WriteLine("AuthorizedKeyPath 不存在: $AuthorizedKeyPath")
    exit 2
}

$hostExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
Write-Output '[Info] 委托机制层: windows/wsl/Initialize-WslSshAccess.ps1 -Apply'
if ($PSCmdlet.ShouldProcess('WSL SSH 自启链路', '通过 Initialize-WslSshAccess -Apply 幂等配置计划任务、firewall rule 与 TCP relay')) {
    & $hostExecutable -NoLogo -NoProfile -ExecutionPolicy Bypass -File $initializeScriptPath `
        -Distribution $Distribution `
        -WindowsUser $WindowsUser `
        -LinuxUser $LinuxUser `
        -ListenAddress $ListenAddress `
        -ListenPort $ListenPort `
        -GuestPort $GuestPort `
        -AuthorizedKeyPath $AuthorizedKeyPath `
        -OutputFormat $OutputFormat `
        -Apply
    exit $LASTEXITCODE
}
exit 0
