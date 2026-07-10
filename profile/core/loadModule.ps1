function Import-ProfileCoreModules {
    <#
    .SYNOPSIS
        按平台依赖顺序同步导入 Profile 核心 psutils 子模块。

    .PARAMETER ProfileRoot
        Profile 脚本目录。

    .PARAMETER PlatformContext
        当前平台能力上下文，包含核心模块列表和路径比较规则。

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        返回完整模块清单路径和已导入核心模块名称。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileRoot,
        [Parameter(Mandatory)]
        [PSCustomObject]$PlatformContext
    )

    $repositoryRoot = Split-Path -Parent $ProfileRoot
    $psutilsRoot = Join-Path $repositoryRoot 'psutils'
    $moduleManifest = Join-Path $psutilsRoot 'psutils.psd1'
    $modulesDir = Join-Path $psutilsRoot 'modules'

    foreach ($moduleName in $PlatformContext.CoreModules) {
        $modulePath = Join-Path $modulesDir "$moduleName.psm1"
        try {
            Import-Module $modulePath -Global -ErrorAction Stop
        }
        catch {
            throw "核心模块 '$moduleName' 导入失败: $($_.Exception.Message)"
        }
    }

    $psutilsParent = Split-Path -Parent $psutilsRoot
    $separator = [System.IO.Path]::PathSeparator
    $currentPaths = @($env:PSModulePath -split [string]$separator | Where-Object { $_ })
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new($PlatformContext.PathComparer)
    $uniquePaths = [System.Collections.Generic.List[string]]::new()

    foreach ($path in @($currentPaths + $psutilsParent)) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ($seenPaths.Add($path)) {
            $uniquePaths.Add($path) | Out-Null
        }
    }
    $env:PSModulePath = ($uniquePaths.ToArray()) -join $separator

    return [PSCustomObject]@{
        ModuleManifest = $moduleManifest
        CoreModules    = @($PlatformContext.CoreModules)
    }
}

function Register-ProfileOnIdle {
    <#
    .SYNOPSIS
        幂等注册 Profile 的一次性 OnIdle 延迟初始化任务。

    .DESCRIPTION
        使用会话级状态避免重复加载 Profile 时注册多个相同任务。
        延迟任务分别完成 psutils 全量导入、包装函数与快捷键初始化。

    .PARAMETER ProfileRoot
        Profile 脚本目录。

    .PARAMETER ModuleManifest
        psutils 完整模块清单路径。

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        返回当前 OnIdle 注册状态与订阅 ID。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileRoot,
        [Parameter(Mandatory)]
        [string]$ModuleManifest
    )

    if ($null -ne $Global:__PowerShellProfileOnIdleState) {
        return $Global:__PowerShellProfileOnIdleState
    }

    $wrapperPath = Join-Path $ProfileRoot 'wrapper.ps1'
    $manifestPathLiteral = ([string]$ModuleManifest).Replace("'", "''")
    $wrapperPathLiteral = ([string]$wrapperPath).Replace("'", "''")
    $idleAction = [scriptblock]::Create(@"
`$idleManifestPath = '$manifestPathLiteral'
`$idleWrapperPath = '$wrapperPathLiteral'
try {
    if ([string]::IsNullOrWhiteSpace(`$idleManifestPath)) {
        throw 'psutils 模块清单路径为空'
    }
    Import-Module `$idleManifestPath -Force -Global -ErrorAction Stop
}
catch {
    Write-Warning "[profile/core/loadModule.ps1] OnIdle psutils 全量加载失败: `$(`$_.Exception.Message)"
}
try {
    if (-not [string]::IsNullOrWhiteSpace(`$idleWrapperPath) -and (Test-Path `$idleWrapperPath)) {
        . `$idleWrapperPath
    }
}
catch {
    Write-Warning "[profile/core/loadModule.ps1] OnIdle wrapper.ps1 加载失败: `$(`$_.Exception.Message)"
}
try {
    if (Get-Command -Name Register-FzfHistorySmartKeyBinding -CommandType Function -ErrorAction SilentlyContinue) {
        Register-FzfHistorySmartKeyBinding | Out-Null
    }
}
catch {
    Write-Warning "[profile/core/loadModule.ps1] OnIdle fzf 键绑定注册失败: `$(`$_.Exception.Message)"
}
try {
    Set-PSReadLineKeyHandler -Key Tab -Function Complete
}
catch {
    Write-Warning "[profile/core/loadModule.ps1] OnIdle PSReadLine Tab 键绑定注册失败: `$(`$_.Exception.Message)"
}
"@)

    $subscriber = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action $idleAction
    $Global:__PowerShellProfileOnIdleState = [PSCustomObject]@{
        Status         = 'Registered'
        SubscriptionId = $subscriber.SubscriptionId
    }
    return $Global:__PowerShellProfileOnIdleState
}
