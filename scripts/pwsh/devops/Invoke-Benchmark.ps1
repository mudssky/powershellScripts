<#
.SYNOPSIS
    统一调度 tests/benchmarks 下的 benchmark 脚本。

.DESCRIPTION
    自动扫描 `tests/benchmarks/*.Benchmark.ps1`，将文件名映射为可执行的 benchmark 名称。
    例如：

    - `CommandDiscovery.Benchmark.ps1` -> `command-discovery`

    典型用法：

    - `pnpm benchmark -- --list`
    - `pnpm benchmark -- command-discovery -Iterations 3`

.PARAMETER Name
    要执行的 benchmark 名称。

.PARAMETER List
    列出所有可用 benchmark。

.PARAMETER BenchmarksRoot
    可选的 benchmark 目录覆盖值。默认使用仓库中的 `tests/benchmarks`。

.PARAMETER BenchmarkArgs
    透传给目标 benchmark 脚本的剩余参数。
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Name,
    [switch]$List,
    [string]$BenchmarksRoot,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [object[]]$BenchmarkArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-BenchmarkName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Stem
    )

    $withoutSuffix = $Stem -replace '\.Benchmark$', ''
    $withHyphen = $withoutSuffix -creplace '([a-z0-9])([A-Z])', '$1-$2'
    return $withHyphen.ToLowerInvariant()
}

function Get-BenchmarkCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BenchmarksRoot
    )

    $entries = foreach ($file in Get-ChildItem -Path $BenchmarksRoot -Filter '*.Benchmark.ps1' -File | Sort-Object Name) {
        $benchmarkName = ConvertTo-BenchmarkName -Stem $file.BaseName
        [PSCustomObject]@{
            Name = $benchmarkName
            Path = $file.FullName
            File = $file.Name
        }
    }

    return @($entries)
}

<#
.SYNOPSIS
    导入 benchmark 依赖的交互选择模块。

.DESCRIPTION
    benchmark 仅在缺少 `Name` 参数时才需要交互选择能力，因此这里按需导入
    `psutils/modules/selection.psm1`，避免显式名称路径也增加额外模块开销。
#>
function Import-BenchmarkSelectionModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $selectionModulePath = Join-Path $RepoRoot 'psutils' 'modules' 'selection.psm1'
    if (-not (Test-Path $selectionModulePath)) {
        throw "交互选择模块不存在: $selectionModulePath"
    }

    if (Get-Module -Name selection) {
        return
    }

    Import-Module $selectionModulePath -Force -ErrorAction Stop
}

<#
.SYNOPSIS
    在缺少显式名称时，为 benchmark 列表执行交互选择。

.DESCRIPTION
    公共模块负责 `fzf` 与文本编号降级，脚本层只定义 benchmark 的展示文案
    与取消后的控制流，避免把交互细节重新散落回业务脚本。
#>
function Select-BenchmarkCatalogItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Catalog,
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    Import-BenchmarkSelectionModule -RepoRoot $RepoRoot

    return Select-InteractiveItem `
        -Items $Catalog `
        -DisplayScriptBlock { "{0} ({1})" -f $_.Name, $_.File } `
        -Prompt 'Benchmark > ' `
        -Header '请选择要运行的 benchmark'
}

function Complete-BenchmarkScript {
    [CmdletBinding()]
    param(
        [int]$ExitCode = 0
    )

    # 测试会在当前 Pester 进程内直接调用本脚本；
    # 这里通过专用环境变量切换为 `return`，避免脚本内的 `exit` 直接终止宿主测试进程。
    if ($env:PWSH_TEST_IN_PROCESS_BENCHMARK -eq '1') {
        $global:LASTEXITCODE = $ExitCode
        return
    }

    exit $ExitCode
}

<#
.SYNOPSIS
    判断当前 benchmark 调度是否处于测试内静音模式。

.DESCRIPTION
    `tests/Invoke-Benchmark.Tests.ps1` 会在当前 Pester 进程内直接调用本脚本。
    这类调用需要保留退出码与功能语义，但不应把 `Write-Host` / `Write-Warning`
    文案泄露到默认 full 日志中，因此这里复用现有测试环境变量统一判定。

.OUTPUTS
    `bool`
    返回当前调用是否应静音非错误级别的 benchmark 提示。
#>
function Test-BenchmarkQuietMode {
    [CmdletBinding()]
    param()

    return ($env:PWSH_TEST_IN_PROCESS_BENCHMARK -eq '1')
}

<#
.SYNOPSIS
    在允许输出时写入 benchmark 主机提示。

.DESCRIPTION
    真实 CLI 调用保留 `Write-Host` 提示，便于用户理解当前执行的 benchmark；
    测试内调用则静音这些非断言输出，避免默认门禁日志继续混入低价值文案。

.PARAMETER Message
    要输出的主机提示文本。

.PARAMETER ForegroundColor
    可选的前景色，透传给 `Write-Host`。
#>
function Write-BenchmarkHostMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [System.ConsoleColor]$ForegroundColor
    )

    if (Test-BenchmarkQuietMode) {
        return
    }

    if ($PSBoundParameters.ContainsKey('ForegroundColor')) {
        Write-Host $Message -ForegroundColor $ForegroundColor
        return
    }

    Write-Host $Message
}

<#
.SYNOPSIS
    在允许输出时写入 benchmark warning。

.DESCRIPTION
    取消选择这类用户提示在真实 CLI 路径中仍应可见；
    但在测试内调用时属于低价值噪音，因此默认静音。

.PARAMETER Message
    要输出的 warning 文本。
#>
function Write-BenchmarkHostWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (Test-BenchmarkQuietMode) {
        return
    }

    Write-Warning $Message
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
$effectiveBenchmarksRoot = $BenchmarksRoot
if ([string]::IsNullOrWhiteSpace($effectiveBenchmarksRoot)) {
    $effectiveBenchmarksRoot = Join-Path $repoRoot 'tests' 'benchmarks'
}

if (-not (Test-Path $effectiveBenchmarksRoot)) {
    throw "benchmark 目录不存在: $effectiveBenchmarksRoot"
}

$catalog = Get-BenchmarkCatalog -BenchmarksRoot $effectiveBenchmarksRoot
if ($catalog.Count -eq 0) {
    throw "未找到可用 benchmark: $effectiveBenchmarksRoot"
}

if ($List) {
    Write-BenchmarkHostMessage -Message 'Available benchmarks:' -ForegroundColor Cyan
    foreach ($entry in $catalog) {
        Write-BenchmarkHostMessage -Message ("  - {0} ({1})" -f $entry.Name, $entry.File)
    }
    Complete-BenchmarkScript -ExitCode 0
    return
}

if ([string]::IsNullOrWhiteSpace($Name)) {
    $selected = Select-BenchmarkCatalogItem -Catalog $catalog -RepoRoot $repoRoot
    if ($null -eq $selected) {
        Write-BenchmarkHostWarning -Message '已取消 benchmark 选择，本次不执行任何 benchmark。'
        Complete-BenchmarkScript -ExitCode 0
        return
    }
}
else {
    $selected = $catalog | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $selected) {
        $availableNames = ($catalog | Select-Object -ExpandProperty Name) -join ', '
        Write-Error "未知 benchmark: $Name。可用值: $availableNames"
        Complete-BenchmarkScript -ExitCode 1
        return
    }
}

Write-BenchmarkHostMessage -Message ("Running benchmark: {0}" -f $selected.Name) -ForegroundColor Cyan
Write-BenchmarkHostMessage -Message ("Script: {0}" -f $selected.File) -ForegroundColor DarkGray

$pwshPath = (Get-Process -Id $PID).Path
if ([string]::IsNullOrWhiteSpace($pwshPath)) {
    $pwshPath = 'pwsh'
}

& $pwshPath -NoProfile -File $selected.Path @BenchmarkArgs
Complete-BenchmarkScript -ExitCode $LASTEXITCODE
