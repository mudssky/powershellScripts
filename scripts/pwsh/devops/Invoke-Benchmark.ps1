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

.PARAMETER BenchmarkArgs
    透传给目标 benchmark 脚本的剩余参数。
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Name,
    [switch]$List,
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

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
$benchmarksRoot = Join-Path $repoRoot 'tests' 'benchmarks'
if (-not (Test-Path $benchmarksRoot)) {
    throw "benchmark 目录不存在: $benchmarksRoot"
}

$catalog = Get-BenchmarkCatalog -BenchmarksRoot $benchmarksRoot
if ($catalog.Count -eq 0) {
    throw "未找到可用 benchmark: $benchmarksRoot"
}

if ($List) {
    Write-Host 'Available benchmarks:' -ForegroundColor Cyan
    foreach ($entry in $catalog) {
        Write-Host ("  - {0} ({1})" -f $entry.Name, $entry.File)
    }
    return
}

if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-Error "缺少 benchmark 名称。先运行: pnpm benchmark -- --list"
    exit 1
}

$selected = $catalog | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
if (-not $selected) {
    $availableNames = ($catalog | Select-Object -ExpandProperty Name) -join ', '
    Write-Error "未知 benchmark: $Name。可用值: $availableNames"
    exit 1
}

Write-Host ("Running benchmark: {0}" -f $selected.Name) -ForegroundColor Cyan
Write-Host ("Script: {0}" -f $selected.File) -ForegroundColor DarkGray

$pwshPath = (Get-Process -Id $PID).Path
if ([string]::IsNullOrWhiteSpace($pwshPath)) {
    $pwshPath = 'pwsh'
}

& $pwshPath -NoProfile -File $selected.Path @BenchmarkArgs
exit $LASTEXITCODE
