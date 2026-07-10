function Get-ProfilePlatformContext {
    <#
    .SYNOPSIS
        构造 Profile 当前平台的能力上下文。

    .DESCRIPTION
        将平台判断集中为一个无副作用对象，供模块加载、PATH 处理、工具探测和缓存命名复用。
        测试可通过 Platform 参数显式模拟 Windows、macOS 或 Linux。

    .PARAMETER Platform
        目标平台。Auto 表示根据 PowerShell 7 内置平台变量自动识别。

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        返回平台标识、核心模块、包管理器、PATH 策略、缓存标识与路径比较器。
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Auto', 'Windows', 'MacOS', 'Linux')]
        [string]$Platform = 'Auto'
    )

    $resolvedPlatform = $Platform
    if ($resolvedPlatform -eq 'Auto') {
        $resolvedPlatform = if ($IsWindows) {
            'Windows'
        }
        elseif ($IsMacOS) {
            'MacOS'
        }
        elseif ($IsLinux) {
            'Linux'
        }
        else {
            throw '无法识别当前 PowerShell 运行平台'
        }
    }

    switch ($resolvedPlatform) {
        'Windows' {
            return [PSCustomObject]@{
                Id                = 'windows'
                IsWindows         = $true
                IsUnix            = $false
                CoreModules       = @('os', 'cache', 'commandDiscovery', 'proxy', 'wrapper')
                PackageManagers   = @('scoop', 'winget', 'choco')
                SyncBashPath      = $false
                CacheId           = 'win'
                PathVariableName  = 'Path'
                PathComparer      = [System.StringComparer]::OrdinalIgnoreCase
            }
        }
        'MacOS' {
            return [PSCustomObject]@{
                Id                = 'macos'
                IsWindows         = $false
                IsUnix            = $true
                CoreModules       = @('os', 'cache', 'commandDiscovery', 'env', 'proxy', 'wrapper')
                PackageManagers   = @('brew')
                SyncBashPath      = $false
                CacheId           = 'macos'
                PathVariableName  = 'PATH'
                PathComparer      = [System.StringComparer]::Ordinal
            }
        }
        'Linux' {
            return [PSCustomObject]@{
                Id                = 'linux'
                IsWindows         = $false
                IsUnix            = $true
                CoreModules       = @('os', 'cache', 'commandDiscovery', 'env', 'proxy', 'wrapper')
                PackageManagers   = @('brew', 'apt')
                SyncBashPath      = $true
                CacheId           = 'linux'
                PathVariableName  = 'PATH'
                PathComparer      = [System.StringComparer]::Ordinal
            }
        }
    }
}
