<#
.SYNOPSIS
    显式安装/验证 WSL 宿主并部署当前用户 .wslconfig。

.PARAMETER Distribution
    要确保存在的 WSL 发行版。

.PARAMETER WslConfigTargetPath
    用户级 .wslconfig 目标路径；测试可传临时路径。

.PARAMETER Unattended
    允许独立调用出现一次 UAC。

.PARAMETER NonInteractive
    严格零提示；需要提升时返回 Blocked/10。

.OUTPUTS
    文本组件结果；失败退出 1，Blocked/重启要求退出 10。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Distribution = 'Ubuntu-24.04',

    [string]$WslConfigTargetPath = $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.wslconfig' } else { '' }),

    [switch]$Unattended,

    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-WslHostDistribution {
    <#
    .SYNOPSIS
        只读检查指定 WSL 发行版是否已注册。

    .PARAMETER Name
        发行版名称。

    .OUTPUTS
        System.Boolean。发行版已注册时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        return $false
    }
    $installed = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { ([string]$_).Replace([char]0, '').Trim() })
    return @($installed | Where-Object { $_ -eq $Name }).Count -gt 0
}

if ($Unattended -and $NonInteractive) {
    [Console]::Error.WriteLine('Unattended 与 NonInteractive 不能同时使用')
    exit 2
}
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Import-Module (Join-Path $repoRoot 'windows/pwsh/WindowsInstall.psm1') -Force
Import-Module (Join-Path $repoRoot 'windows/bootstrap/WindowsBootstrap.psm1') -Force
$platform = Get-WindowsInstallEnvironment
if (-not $WhatIfPreference -and ($platform.SupportLevel -ne 'Full' -or $platform.IsServer)) {
    [Console]::Error.WriteLine("当前平台不支持 WSL 宿主自动配置: $($platform.Edition)/$($platform.Architecture)")
    exit 10
}
# 管理员进程不应写真实用户配置；但 WhatIf 仅生成计划，需放行（见规范 Error Matrix）。
if (-not $WhatIfPreference -and $platform.IsAdministrator) {
    [Console]::Error.WriteLine('.wslconfig 必须由普通用户进程写入')
    exit 10
}
if ([string]::IsNullOrWhiteSpace($WslConfigTargetPath)) {
    [Console]::Error.WriteLine('无法解析当前用户 .wslconfig 路径')
    exit 2
}

$results = [System.Collections.Generic.List[object]]::new()
$wslReady = $platform.HasWsl -and (Test-WslHostDistribution -Name $Distribution)
if ($wslReady) {
    $results.Add((New-WindowsInstallResult -Name Wsl -Status AlreadyPresent -Message $Distribution))
}
elseif ($env:POWERSHELL_SCRIPTS_BOOTSTRAP_SESSION -eq '1' -and -not $WhatIfPreference) {
    $results.Add((New-WindowsInstallResult -Name Wsl -Status Blocked -Message '00 bootstrap 已消费提升边界，但 WSL 发行版仍缺失；请重启后重跑 00' -ExitCode 10))
}
elseif ($WhatIfPreference) {
    $results.Add((New-WindowsInstallResult -Name Wsl -Status Preview -Message "wsl --install --no-launch -d $Distribution"))
}
elseif ($NonInteractive) {
    $results.Add((New-WindowsInstallResult -Name Wsl -Status Blocked -Message '严格非交互模式无法请求 WSL 安装提升' -ExitCode 10))
}
else {
    $operation = New-WindowsBootstrapOperation -Type WslInstall -Name Wsl -Distribution $Distribution
    $elevated = Invoke-WindowsBootstrapElevation `
        -Operation @($operation) `
        -NetworkMode Direct `
        -ExecutorPath (Join-Path $repoRoot 'windows/bootstrap/Invoke-WindowsElevatedPlan.ps1') `
        -SourceHelperPath (Join-Path $repoRoot 'scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1') `
        -SourceConfigPath (Join-Path $repoRoot 'config/network/package-sources.bootstrap.env')
    foreach ($result in @($elevated.Results)) {
        $results.Add($result)
    }
    if ([int]$elevated.ExitCode -ne 0 -and
        @($elevated.Results | Where-Object { $_.Status -in @('Failed', 'Blocked', 'RestartRequired') }).Count -eq 0) {
        $topStatus = if ([string]$elevated.Status -eq 'Failed') { 'Failed' } else { 'Blocked' }
        $topMessage = if ($elevated.PSObject.Properties['Message']) { [string]$elevated.Message } else { 'WSL 提升安装未完成' }
        $results.Add((New-WindowsInstallResult -Name elevation -Status $topStatus -Message $topMessage -ExitCode ([int]$elevated.ExitCode)))
    }
    elseif ([int]$elevated.ExitCode -eq 0 -and -not (Test-WslHostDistribution -Name $Distribution)) {
        $results.Add((New-WindowsInstallResult -Name Wsl -Status Blocked -Message 'WSL 安装后发行版尚未就绪；请重启 Windows 后重跑' -ExitCode 10))
    }
}

if (@($results | Where-Object { $_.Status -in @('Failed', 'Blocked', 'RestartRequired') }).Count -eq 0) {
    $catalog = Import-WindowsPackageCatalog -Path (Join-Path $repoRoot 'config/install/windows-packages.psd1')
    $effectiveBuildNumber = if ($WhatIfPreference -and [int]$platform.BuildNumber -le 0) { 22621 } else { [int]$platform.BuildNumber }
    $content = ConvertTo-WindowsWslConfigContent -Catalog $catalog -BuildNumber $effectiveBuildNumber
    $results.Add((Set-WindowsManagedContent -Path $WslConfigTargetPath -Content $content -Preview:$WhatIfPreference))
}

foreach ($result in $results) {
    Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Name, $result.Message)
}
$exitCode = Get-WindowsInstallExitCode -Result $results.ToArray()
if ($exitCode -eq 10 -and @($results | Where-Object Status -eq 'RestartRequired').Count -gt 0) {
    Write-Output '配置或 WSL 功能变化后，请保存工作并手工执行 wsl --shutdown，然后使用相同参数重跑。'
}
elseif ($exitCode -eq 0) {
    Write-Output ("WSL 客体移交: wsl.exe -d {0} -- bash -lc 'cd ~/powershellScripts && bash linux/00quickstart.sh --preset Core'" -f $Distribution)
}
exit $exitCode
