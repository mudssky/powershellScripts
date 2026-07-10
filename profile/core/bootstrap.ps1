function Add-ProfileRepositoryBinPath {
    <#
    .SYNOPSIS
        将仓库 bin 目录加入当前 PowerShell 进程 PATH。

    .DESCRIPTION
        根据仓库根目录计算 bin 目录，并按平台路径比较规则去重追加。
        即使 bin 目录尚未生成也会保留该路径，确保本会话后续生成 shim 后可以直接发现命令。

    .PARAMETER RepositoryRoot
        powershellScripts 仓库根目录。

    .PARAMETER PlatformContext
        由 Get-ProfilePlatformContext 返回的平台能力上下文。

    .OUTPUTS
        System.Boolean
        成功新增路径时返回 $true；路径已存在或仓库根目录为空时返回 $false。
    #>
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot,
        [PSCustomObject]$PlatformContext = $script:ProfilePlatformContext
    )

    process {
        if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
            return $false
        }
        if ($null -eq $PlatformContext) {
            $PlatformContext = Get-ProfilePlatformContext
        }

        $repositoryBinPath = Join-Path $RepositoryRoot 'bin'
        $pathSeparator = [System.IO.Path]::PathSeparator
        $currentPath = [Environment]::GetEnvironmentVariable($PlatformContext.PathVariableName, 'Process')
        $targetPath = [System.IO.Path]::GetFullPath($repositoryBinPath)
        $normalizedTargetPath = $targetPath.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $currentPaths = @($currentPath -split [regex]::Escape([string]$pathSeparator) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        foreach ($path in $currentPaths) {
            $normalizedPath = [string]$path
            try {
                $normalizedPath = [System.IO.Path]::GetFullPath($normalizedPath)
            }
            catch {
                Write-Verbose "跳过无法规范化的 PATH 条目: $path"
            }

            $normalizedPath = $normalizedPath.TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            )
            if ($PlatformContext.PathComparer.Equals($normalizedPath, $normalizedTargetPath)) {
                Write-Verbose "仓库 bin 目录已在 PATH 中: $targetPath"
                return $false
            }
        }

        $updatedPaths = @($currentPaths + $targetPath)
        [Environment]::SetEnvironmentVariable(
            $PlatformContext.PathVariableName,
            ($updatedPaths -join $pathSeparator),
            'Process'
        )
        Write-Verbose "已将仓库 bin 目录加入 PATH: $targetPath"
        return $true
    }
}

function Initialize-ProfileBootstrap {
    <#
    .SYNOPSIS
        初始化所有 Profile 模式都需要的最小环境。

    .PARAMETER ProfileRoot
        Profile 脚本目录。

    .PARAMETER PlatformContext
        当前平台能力上下文。

    .OUTPUTS
        System.Void
        仅修改当前进程环境变量、PATH 与控制台编码。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileRoot,
        [PSCustomObject]$PlatformContext = $script:ProfilePlatformContext
    )

    $repositoryRoot = Split-Path -Parent $ProfileRoot
    $env:POWERSHELL_SCRIPTS_ROOT = $repositoryRoot
    Add-ProfileRepositoryBinPath -RepositoryRoot $repositoryRoot -PlatformContext $PlatformContext | Out-Null
    Set-ProfileUtf8Encoding
}

function Initialize-Environment {
    <#
    .SYNOPSIS
        提供 UltraMinimal 模式下的轻量环境初始化兼容入口。

    .DESCRIPTION
        Full 与 Minimal 会在加载 features/environment.ps1 后覆盖此函数。
        UltraMinimal 保留该公共命令，但调用时只重复执行幂等 bootstrap，不加载模块或工具。

    .PARAMETER ScriptRoot
        Profile 脚本目录。

    .PARAMETER ProxyUrl
        为完整实现保留的兼容参数；UltraMinimal 不使用代理。

    .PARAMETER SkipTools
        为完整实现保留的兼容参数。

    .PARAMETER SkipProxy
        为完整实现保留的兼容参数。

    .PARAMETER SkipStarship
        为完整实现保留的兼容参数。

    .PARAMETER SkipZoxide
        为完整实现保留的兼容参数。

    .PARAMETER SkipAliases
        为完整实现保留的兼容参数。

    .PARAMETER Minimal
        为完整实现保留的兼容参数。

    .PARAMETER ProfileMode
        当前 Profile 模式。

    .PARAMETER PlatformContext
        当前平台能力上下文。

    .OUTPUTS
        System.Void
        仅执行最小环境初始化。
    #>
    [CmdletBinding()]
    param(
        [string]$ScriptRoot = $script:ProfileRoot,
        [ValidatePattern('^https?://')]
        [string]$ProxyUrl = 'http://127.0.0.1:7890',
        [switch]$SkipTools,
        [switch]$SkipProxy,
        [switch]$SkipStarship,
        [switch]$SkipZoxide,
        [switch]$SkipAliases,
        [switch]$Minimal,
        [ValidateSet('Full', 'Minimal', 'UltraMinimal')]
        [string]$ProfileMode = 'UltraMinimal',
        [PSCustomObject]$PlatformContext = $script:ProfilePlatformContext
    )

    Initialize-ProfileBootstrap -ProfileRoot $ScriptRoot -PlatformContext $PlatformContext
    Write-ProfileModeDecisionSummary
    Write-ProfileModeFallbackGuide -VerboseOnly
    Write-Debug "PowerShell 环境初始化完成（$ProfileMode 轻量兼容入口）"
}
