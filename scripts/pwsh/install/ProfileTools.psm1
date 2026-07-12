Set-StrictMode -Version Latest

function New-ProfileToolResult {
    <#
    .SYNOPSIS
        创建共享 Profile Tools 组件结果。

    .PARAMETER Name
        组件名称。

    .PARAMETER Status
        Succeeded、AlreadyPresent、Preview、Failed 或 Blocked。

    .PARAMETER Message
        结果摘要。

    .OUTPUTS
        PSCustomObject。包含 Name、Status 和 Message。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Succeeded', 'AlreadyPresent', 'Preview', 'Failed', 'Blocked')]
        [string]$Status,

        [string]$Message = ''
    )

    return [pscustomobject]@{
        Name    = $Name
        Status  = $Status
        Message = $Message
    }
}

function Invoke-ProfileToolNativeCommand {
    <#
    .SYNOPSIS
        以参数数组执行 Profile Tools 必需的原生命令。

    .PARAMETER Name
        汇总组件名称。

    .PARAMETER FilePath
        可执行文件路径或命令名。

    .PARAMETER ArgumentList
        原生命令参数数组。

    .PARAMETER Preview
        只返回 Preview，不执行命令。

    .OUTPUTS
        PSCustomObject。命令组件结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList,

        [switch]$Preview
    )

    if ($Preview) {
        return New-ProfileToolResult `
            -Name $Name `
            -Status Preview `
            -Message (("{0} {1}" -f $FilePath, ($ArgumentList -join ' ')).Trim())
    }

    try {
        $output = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        $message = ($output | Select-Object -Last 20 | Out-String).Trim()
        if ($exitCode -ne 0) {
            throw "命令退出码为 $exitCode$(if ($message) { ": $message" } else { '' })"
        }
        return New-ProfileToolResult -Name $Name -Status Succeeded -Message $message
    }
    catch {
        return New-ProfileToolResult -Name $Name -Status Failed -Message $_.Exception.Message
    }
}

function Invoke-ProfileToolsInstall {
    <#
    .SYNOPSIS
        安装并配置跨平台 PowerShell Profile 与仓库工具链。

    .PARAMETER RepoRoot
        仓库根目录。

    .PARAMETER Platform
        Windows、macOS 或 Linux，用于选择 PowerShell 模块平台策略。

    .OUTPUTS
        PSCustomObject[]。逐组件结果，不在模块内终止调用进程。
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [ValidateSet('Windows', 'macOS', 'Linux')]
        [string]$Platform
    )

    $resolvedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
    $results = [System.Collections.Generic.List[object]]::new()
    if (-not (Get-Command Resolve-ConfigSources -ErrorAction SilentlyContinue) -or
        -not (Get-Command Install-RequiredModule -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $resolvedRepoRoot 'psutils') -Force
    }

    try {
        $moduleResults = @(& (Join-Path $resolvedRepoRoot 'profile/installer/installModules.ps1') `
                -Platform $Platform `
                -WhatIf:$WhatIfPreference)
        $moduleFailures = @($moduleResults | Where-Object Status -eq 'Failed')
        $results.Add((New-ProfileToolResult `
                    -Name modules `
                    -Status $(if ($moduleFailures.Count -gt 0) { 'Failed' } elseif ($WhatIfPreference) { 'Preview' } else { 'Succeeded' }) `
                    -Message $(if ($moduleFailures.Count -gt 0) { ($moduleFailures.Message -join '; ') } else { '' })))
    }
    catch {
        $results.Add((New-ProfileToolResult -Name modules -Status Failed -Message $_.Exception.Message))
    }

    try {
        $null = & (Join-Path $resolvedRepoRoot 'profile/profile.ps1') -LoadProfile -WhatIf:$WhatIfPreference
        $results.Add((New-ProfileToolResult -Name profile -Status $(if ($WhatIfPreference) { 'Preview' } else { 'Succeeded' })))
    }
    catch {
        $results.Add((New-ProfileToolResult -Name profile -Status Failed -Message $_.Exception.Message))
    }

    if ($WhatIfPreference) {
        $results.Add((New-ProfileToolResult -Name node-runtime -Status Preview -Message 'fnm install --lts; fnm use lts-latest'))
    }
    elseif (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
        $results.Add((New-ProfileToolResult -Name node-runtime -Status Blocked -Message '缺少 fnm，请先完成 05 core-cli'))
    }
    else {
        $nodeInstall = Invoke-ProfileToolNativeCommand -Name node-install -FilePath fnm -ArgumentList @('install', '--lts')
        $results.Add($nodeInstall)
        if ($nodeInstall.Status -ne 'Failed') {
            $results.Add((Invoke-ProfileToolNativeCommand -Name node-use -FilePath fnm -ArgumentList @('use', 'lts-latest')))
        }
    }

    try {
        $packageConfig = (Resolve-ConfigSources -Sources @(
                @{ Type = 'JsonFile'; Name = 'RootPackage'; Path = (Join-Path $resolvedRepoRoot 'package.json') }
            ) -BasePath $resolvedRepoRoot -ErrorOnMissing).Values
        $packageManagerSpec = [string]$packageConfig.packageManager
        if ([string]::IsNullOrWhiteSpace($packageManagerSpec)) {
            $results.Add((New-ProfileToolResult -Name pnpm -Status Failed -Message '根 package.json 缺少 packageManager'))
        }
        elseif ($WhatIfPreference) {
            $results.Add((New-ProfileToolResult -Name pnpm -Status Preview -Message "准备 $packageManagerSpec"))
        }
        elseif (Get-Command corepack -ErrorAction SilentlyContinue) {
            $results.Add((Invoke-ProfileToolNativeCommand -Name corepack-enable -FilePath corepack -ArgumentList @('enable')))
            $results.Add((Invoke-ProfileToolNativeCommand -Name pnpm -FilePath corepack -ArgumentList @('prepare', $packageManagerSpec, '--activate')))
        }
        elseif (Get-Command npm -ErrorAction SilentlyContinue) {
            $results.Add((Invoke-ProfileToolNativeCommand -Name pnpm -FilePath npm -ArgumentList @('install', '--global', $packageManagerSpec)))
        }
        else {
            $results.Add((New-ProfileToolResult -Name pnpm -Status Blocked -Message '缺少 corepack 和 npm'))
        }
    }
    catch {
        $results.Add((New-ProfileToolResult -Name pnpm -Status Failed -Message $_.Exception.Message))
    }

    $manageBinArguments = @('-NoLogo', '-NoProfile', '-File', (Join-Path $resolvedRepoRoot 'Manage-BinScripts.ps1'), '-Action', 'sync', '-Force')
    if ($WhatIfPreference) {
        $manageBinArguments += '-WhatIf'
    }
    $results.Add((Invoke-ProfileToolNativeCommand -Name bin-shims -FilePath pwsh -ArgumentList $manageBinArguments -Preview:$WhatIfPreference))
    if ($Platform -ne 'Windows') {
        $results.Add((Invoke-ProfileToolNativeCommand -Name bash-build -FilePath bash -ArgumentList @((Join-Path $resolvedRepoRoot 'scripts/bash/build.sh')) -Preview:$WhatIfPreference))
    }
    $results.Add((Invoke-ProfileToolNativeCommand -Name node-dependencies -FilePath pnpm -ArgumentList @('--dir', (Join-Path $resolvedRepoRoot 'scripts/node'), 'install', '--ignore-scripts') -Preview:$WhatIfPreference))
    $results.Add((Invoke-ProfileToolNativeCommand -Name node-build -FilePath pnpm -ArgumentList @('--dir', (Join-Path $resolvedRepoRoot 'scripts/node'), 'run', 'build') -Preview:$WhatIfPreference))

    if ($WhatIfPreference) {
        $results.Add((New-ProfileToolResult -Name nbstripout -Status Preview -Message 'uv tool install nbstripout'))
    }
    elseif (Get-Command nbstripout -ErrorAction SilentlyContinue) {
        $results.Add((New-ProfileToolResult -Name nbstripout -Status AlreadyPresent))
    }
    elseif (Get-Command uv -ErrorAction SilentlyContinue) {
        $results.Add((Invoke-ProfileToolNativeCommand -Name nbstripout -FilePath uv -ArgumentList @('tool', 'install', 'nbstripout')))
    }
    else {
        $results.Add((New-ProfileToolResult -Name nbstripout -Status Blocked -Message '缺少 uv，请先完成 05 core-cli'))
    }

    return $results.ToArray()
}

function Get-ProfileToolsExitCode {
    <#
    .SYNOPSIS
        汇总 Profile Tools 组件退出码。

    .PARAMETER Result
        Invoke-ProfileToolsInstall 返回的结果数组。

    .OUTPUTS
        System.Int32。Failed 返回 1，Blocked 返回 10，其余返回 0。
    #>
    [CmdletBinding()]
    param(
        [object[]]$Result
    )

    if (@($Result | Where-Object Status -eq 'Failed').Count -gt 0) {
        return 1
    }
    if (@($Result | Where-Object Status -eq 'Blocked').Count -gt 0) {
        return 10
    }
    return 0
}

Export-ModuleMember -Function @(
    'Invoke-ProfileToolsInstall',
    'Get-ProfileToolsExitCode'
)
