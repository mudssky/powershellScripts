#!/usr/bin/env pwsh

<#
.SYNOPSIS
    以统一方式按模式执行仓库内的 Pester 配置。

.DESCRIPTION
    该脚本是对 `PesterConfiguration.ps1` 的轻量包装，用于把“设置测试模式环境变量”
    和“调用统一配置”收敛到一个 `pwsh -File` 入口中，避免在 `package.json` 里继续
    使用容易被 Unix shell 提前展开的 `pwsh -Command "$env:..."` 形式。

.PARAMETER Mode
    Pester 运行模式，对应 `PWSH_TEST_MODE`。常见值包括 `full`、`qa`、`serial`。

.PARAMETER Coverage
    Coverage 行为：
    - `Default`: 不显式覆盖，交给 `PesterConfiguration.ps1` 按模式决定
    - `On`: 显式启用 coverage
    - `Off`: 显式关闭 coverage

.PARAMETER VerboseOutput
    是否启用详细输出，对应 `PWSH_TEST_VERBOSE=1`。

.PARAMETER Path
    可选的单文件或子集测试路径，对应 `PWSH_TEST_PATH`。
    未显式传入时保留调用方已有环境变量，便于 QA 编排器注入 changed 测试集。

.PARAMETER CoveragePath
    可选的 JaCoCo 输出路径，对应 `PESTER_COVERAGE_PATH`。未指定时保留调用方已有覆盖值。

.PARAMETER PesterVersion
    要显式导入的 Pester 版本。未传入时依次读取 PWSH_PESTER_VERSION 和仓库
    `.pester-version`，避免自动加载机器上的任意版本。

.PARAMETER Parallel
    显式启用 Pester 6 文件级并行。目标版本不支持时明确失败。

.PARAMETER ParallelThrottle
    可选并行上限。仅在启用 Parallel 时生效；0 表示使用 Pester 自动值。

.PARAMETER IncludeSlow
    包含默认被 Slow 标签排除的测试。

.EXAMPLE
    pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode qa

    以 QA 模式运行默认的快速 Pester 子集。

.EXAMPLE
    pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode full -Coverage Off

    以 full 模式运行，但显式关闭 coverage。
#>
[CmdletBinding()]
param(
    [ValidateSet('full', 'fast', 'qa', 'serial', 'debug')]
    [string]$Mode = 'full',

    [ValidateSet('Default', 'On', 'Off')]
    [string]$Coverage = 'Default',

    [switch]$VerboseOutput,

    [string]$Path,

    [string]$CoveragePath,

    [string]$PesterVersion,

    [switch]$Parallel,

    [ValidateRange(0, 128)]
    [int]$ParallelThrottle = 0,

    [switch]$IncludeSlow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..' '..'))
$configPath = Join-Path $repoRoot 'PesterConfiguration.ps1'
$versionPath = Join-Path $repoRoot '.pester-version'

$effectivePesterVersion = if (-not [string]::IsNullOrWhiteSpace($PesterVersion)) {
    $PesterVersion.Trim()
}
elseif (-not [string]::IsNullOrWhiteSpace($env:PWSH_PESTER_VERSION)) {
    $env:PWSH_PESTER_VERSION.Trim()
}
elseif (Test-Path -LiteralPath $versionPath -PathType Leaf) {
    (Get-Content -LiteralPath $versionPath -Raw).Trim()
}
else {
    throw "缺少 Pester 版本配置: $versionPath"
}

if ($effectivePesterVersion -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw "Pester 版本格式无效: $effectivePesterVersion"
}
$originalPesterModule = Get-Module -Name Pester | Select-Object -First 1


$originalValues = @{
    PWSH_TEST_MODE            = [Environment]::GetEnvironmentVariable('PWSH_TEST_MODE', 'Process')
    PWSH_TEST_ENABLE_COVERAGE = [Environment]::GetEnvironmentVariable('PWSH_TEST_ENABLE_COVERAGE', 'Process')
    PWSH_TEST_VERBOSE         = [Environment]::GetEnvironmentVariable('PWSH_TEST_VERBOSE', 'Process')
    PWSH_TEST_PATH            = [Environment]::GetEnvironmentVariable('PWSH_TEST_PATH', 'Process')
    PWSH_TEST_PARALLEL          = [Environment]::GetEnvironmentVariable('PWSH_TEST_PARALLEL', 'Process')
    PWSH_TEST_PARALLEL_THROTTLE = [Environment]::GetEnvironmentVariable('PWSH_TEST_PARALLEL_THROTTLE', 'Process')
    PWSH_TEST_INCLUDE_SLOW      = [Environment]::GetEnvironmentVariable('PWSH_TEST_INCLUDE_SLOW', 'Process')
    PESTER_COVERAGE_PATH        = [Environment]::GetEnvironmentVariable('PESTER_COVERAGE_PATH', 'Process')
}

<#
.SYNOPSIS
    恢复单个进程级环境变量。
.PARAMETER Name
    要恢复的环境变量名称。
.PARAMETER Value
    原始环境变量值；为 null 时删除该变量。
.OUTPUTS
    None。直接修改当前进程环境。
#>
function Restore-ProcessEnvironmentValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        Remove-Item -Path ("Env:{0}" -f $Name) -ErrorAction SilentlyContinue
        return
    }

    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

function Import-PinnedPester {
    <#
    .SYNOPSIS
        导入指定版本的 Pester。

    .PARAMETER Version
        必须精确匹配的 Pester 版本。

    .OUTPUTS
        System.Management.Automation.PSModuleInfo。已导入的 Pester 模块。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    $loadedPester = Get-Module -Name Pester | Select-Object -First 1
    if ($loadedPester) {
        if ($loadedPester.Version.ToString() -eq $Version) {
            return $loadedPester
        }
        throw "当前进程已加载 Pester $($loadedPester.Version)，不能切换到 $Version；请使用独立 pwsh 进程运行目标版本。"
    }

    try {
        Import-Module Pester -RequiredVersion $Version -Force -ErrorAction Stop
    }
    catch {
        $candidate = Get-Module -ListAvailable -Name Pester |
            Where-Object { $_.Version.ToString() -eq $Version } |
            Select-Object -First 1
        if (-not $candidate) {
            throw "未安装 Pester $Version。请运行 pnpm pester:install -Version $Version。"
        }
        Import-Module $candidate.Path -Force -ErrorAction Stop
    }

    return Get-Module -Name Pester
}

try {
    Import-PinnedPester -Version $effectivePesterVersion | Out-Null

    [Environment]::SetEnvironmentVariable('PWSH_TEST_MODE', $Mode, 'Process')

    switch ($Coverage) {
        'On' {
            [Environment]::SetEnvironmentVariable('PWSH_TEST_ENABLE_COVERAGE', 'true', 'Process')
        }
        'Off' {
            [Environment]::SetEnvironmentVariable('PWSH_TEST_ENABLE_COVERAGE', 'false', 'Process')
        }
        default { }
    }

    if ($VerboseOutput.IsPresent) {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_VERBOSE', '1', 'Process')
    }
    else {
        Remove-Item Env:\PWSH_TEST_VERBOSE -ErrorAction SilentlyContinue
    }

    if ($PSBoundParameters.ContainsKey('Path')) {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            Remove-Item Env:\PWSH_TEST_PATH -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable('PWSH_TEST_PATH', $Path, 'Process')
        }
    }

    if ($PSBoundParameters.ContainsKey('CoveragePath')) {
        if ([string]::IsNullOrWhiteSpace($CoveragePath)) {
            Remove-Item Env:\PESTER_COVERAGE_PATH -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable('PESTER_COVERAGE_PATH', $CoveragePath, 'Process')
        }
    }

    if ($Parallel.IsPresent) {
        $probe = New-PesterConfiguration
        if ($probe.Run.PSObject.Properties.Name -notcontains 'Parallel') {
            throw "Pester $effectivePesterVersion 不支持 Run.Parallel；请使用 Pester 6 或移除 -Parallel。"
        }

        $coverageRequested = $Coverage -eq 'On' -or ($Coverage -eq 'Default' -and $Mode -notin @('fast', 'serial', 'debug', 'qa'))
        $comparablePesterVersion = [version]($effectivePesterVersion -replace '-.*$', '')
        if ($coverageRequested -and $comparablePesterVersion -lt [version]'6.1.0') {
            throw "Pester $effectivePesterVersion 不支持并行 coverage；需要 Pester 6.1.0 或更高版本。"
        }

        [Environment]::SetEnvironmentVariable('PWSH_TEST_PARALLEL', 'true', 'Process')
        [Environment]::SetEnvironmentVariable('PWSH_TEST_PARALLEL_THROTTLE', [string]$ParallelThrottle, 'Process')
    }
    else {
        Remove-Item Env:\PWSH_TEST_PARALLEL -ErrorAction SilentlyContinue
        Remove-Item Env:\PWSH_TEST_PARALLEL_THROTTLE -ErrorAction SilentlyContinue
    }

    if ($IncludeSlow.IsPresent) {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_INCLUDE_SLOW', 'true', 'Process')
    }
    else {
        Remove-Item Env:\PWSH_TEST_INCLUDE_SLOW -ErrorAction SilentlyContinue
    }

    $configuration = & $configPath
    $configuration.Run.Exit = $true
    Invoke-Pester -Configuration $configuration
}
finally {
    foreach ($entry in $originalValues.GetEnumerator()) {
        Restore-ProcessEnvironmentValue -Name $entry.Key -Value $entry.Value
    }

    if (-not $originalPesterModule -and (Get-Module -Name Pester)) {
        Remove-Module -Name Pester -Force
    }
}
