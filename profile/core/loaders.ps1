function Invoke-ProfileCoreLoaders {
    <#
    .SYNOPSIS
        按 Profile 模式加载同步核心模块与用户别名配置。

    .PARAMETER ProfileRoot
        Profile 脚本目录。

    .PARAMETER Mode
        当前 Profile 模式。Full 与 Minimal 加载核心模块，只有 Full 读取别名配置。

    .PARAMETER PlatformContext
        当前平台能力上下文。

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        返回已加载模块、别名数量与 OnIdle 注册状态。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileRoot,
        [Parameter(Mandatory)]
        [ValidateSet('Full', 'Minimal')]
        [string]$Mode,
        [Parameter(Mandatory)]
        [PSCustomObject]$PlatformContext
    )

    $script:ProfileExtendedFeaturesLoaded = $false
    $script:userAlias = @()

    $moduleResult = Import-ProfileCoreModules -ProfileRoot $ProfileRoot -PlatformContext $PlatformContext
    $idleState = Register-ProfileOnIdle -ProfileRoot $ProfileRoot -ModuleManifest $moduleResult.ModuleManifest

    if ($Mode -eq 'Full') {
        $userAliasScript = Join-Path $ProfileRoot 'config/aliases/user_aliases.ps1'
        try {
            $script:userAlias = @(. $userAliasScript)
        }
        catch {
            Write-Warning "[profile/core/loaders.ps1] 用户别名配置加载失败，已使用空配置继续: $($_.Exception.Message)"
            $script:userAlias = @()
        }
    }

    $script:ProfileExtendedFeaturesLoaded = $true
    return [PSCustomObject]@{
        CoreModules       = @($moduleResult.CoreModules)
        UserAliasCount    = $script:userAlias.Count
        OnIdleStatus      = $idleState.Status
        OnIdleSubscriptionId = $idleState.SubscriptionId
    }
}
