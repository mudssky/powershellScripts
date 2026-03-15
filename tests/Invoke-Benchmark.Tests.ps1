Set-StrictMode -Version Latest

BeforeAll {
    $script:InvokeBenchmarkScriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'pwsh' 'devops' 'Invoke-Benchmark.ps1'
    $script:PwshPath = (Get-Process -Id $PID).Path
    $script:SelectionModulePath = Join-Path $PSScriptRoot '..' 'psutils' 'modules' 'selection.psm1'
    $script:OriginalInProcessBenchmarkFlag = [Environment]::GetEnvironmentVariable('PWSH_TEST_IN_PROCESS_BENCHMARK', 'Process')
    # Unix 测试会把 PATH 临时切到工具目录，因此先解析 chmod 的绝对路径，避免后续补执行权限时再依赖 PATH。
    $script:ChmodPath = if ($IsWindows) { $null } else { (Get-Command chmod -ErrorAction Stop).Source }
    $script:NewTestBenchmarkScript = {
        param(
            [Parameter(Mandatory)]
            [string]$BenchmarksRoot,
            [Parameter(Mandatory)]
            [string]$FileName,
            [Parameter(Mandatory)]
            [string]$Body
        )

        $path = Join-Path $BenchmarksRoot $FileName
        Set-Content -Path $path -Value $Body
        return $path
    }
    $script:NewTestFzfExecutable = {
        param(
            [Parameter(Mandatory)]
            [string]$ToolsPath
        )

        if ($IsWindows) {
            $fzfPath = Join-Path $ToolsPath 'fzf.cmd'
            Set-Content -Path $fzfPath -Encoding ascii -Value @'
@echo off
if defined FAKE_FZF_MARKER (
  > "%FAKE_FZF_MARKER%" echo used
)
set "FIRST_LINE="
set /p FIRST_LINE=
if defined FIRST_LINE echo %FIRST_LINE%
exit /b 0
'@
            return $fzfPath
        }

        $fzfPath = Join-Path $ToolsPath 'fzf'
        # Unix 测试会把 PATH 缩到临时工具目录，因此这里直接使用 /bin/sh，避免再依赖 env 从 PATH 查找解释器。
        # 同时显式使用 LF shebang，防止 `\r` 被内核当成解释器路径的一部分。
        $unixFzfScript = @(
            '#!/bin/sh'
            'if [ -n "$FAKE_FZF_MARKER" ]; then'
            '  printf ''used\n'' > "$FAKE_FZF_MARKER"'
            'fi'
            'IFS= read -r first_line || exit 0'
            'if [ -n "$first_line" ]; then'
            '  printf ''%s\n'' "$first_line"'
            'fi'
            'exit 0'
        ) -join "`n"
        Set-Content -Path $fzfPath -Encoding ascii -Value $unixFzfScript
        & $script:ChmodPath +x $fzfPath
        return $fzfPath
    }
}

Describe 'Invoke-Benchmark.ps1' {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
        $script:BenchmarksRoot = Join-Path $script:TestRoot 'benchmarks'
        $script:MarkerPath = Join-Path $script:TestRoot 'marker.txt'
        $env:PWSH_TEST_IN_PROCESS_BENCHMARK = '1'
        # Linux/macOS 的 TestDrive 通常位于 /tmp；某些容器挂载会让这里的文件不适合作为外部可执行程序。
        # 因此 Unix 下把 fake fzf 放到仓库内的临时目录，保证 PowerShell 能正常拉起它。
        $script:ToolsPath = if ($IsWindows) {
            Join-Path $script:TestRoot 'tools'
        }
        else {
            Join-Path $PSScriptRoot '.tmp-executables' ([Guid]::NewGuid().ToString())
        }
        $script:OriginalPath = $env:PATH
        $script:OriginalFakeFzfMarker = [Environment]::GetEnvironmentVariable('FAKE_FZF_MARKER', 'Process')

        New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $script:BenchmarksRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $script:ToolsPath -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        $env:PATH = $script:OriginalPath

        if ($null -eq $script:OriginalFakeFzfMarker) {
            Remove-Item Env:\FAKE_FZF_MARKER -ErrorAction SilentlyContinue
        }
        else {
            $env:FAKE_FZF_MARKER = $script:OriginalFakeFzfMarker
        }

        Remove-Module selection -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $script:ToolsPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    AfterAll {
        if ($null -eq $script:OriginalInProcessBenchmarkFlag) {
            Remove-Item Env:\PWSH_TEST_IN_PROCESS_BENCHMARK -ErrorAction SilentlyContinue
        }
        else {
            $env:PWSH_TEST_IN_PROCESS_BENCHMARK = $script:OriginalInProcessBenchmarkFlag
        }
    }

    It '显式传入 benchmark 名称时保持原有非交互执行路径' {
        $null = & $script:NewTestBenchmarkScript `
            -BenchmarksRoot $script:BenchmarksRoot `
            -FileName 'SampleOne.Benchmark.ps1' `
            -Body @'
param(
    [string]$MarkerPath,
    [string]$Message,
    [int]$Iterations
)

Set-Content -Path $MarkerPath -Value ("{0}|{1}" -f $Message, $Iterations)
'@

        $null = & $script:InvokeBenchmarkScriptPath `
            'sample-one' `
            -BenchmarksRoot $script:BenchmarksRoot `
            -MarkerPath $script:MarkerPath `
            -Message 'hello' `
            -Iterations 7

        $LASTEXITCODE | Should -Be 0
        (Get-Content -Path $script:MarkerPath -Raw).Trim() | Should -Be 'hello|7'
    }

    It '缺少 fzf 时自动降级到文本编号选择' {
        $null = & $script:NewTestBenchmarkScript `
            -BenchmarksRoot $script:BenchmarksRoot `
            -FileName 'FirstChoice.Benchmark.ps1' `
            -Body @'
param([string]$MarkerPath)

Set-Content -Path $MarkerPath -Value 'first'
'@
        $null = & $script:NewTestBenchmarkScript `
            -BenchmarksRoot $script:BenchmarksRoot `
            -FileName 'SecondChoice.Benchmark.ps1' `
            -Body @'
param([string]$MarkerPath)

Set-Content -Path $MarkerPath -Value 'second'
'@

        $env:PATH = $script:ToolsPath
        Import-Module $script:SelectionModulePath -Force
        Mock -ModuleName selection Test-InteractiveSelectionFzfAvailable { return $false }
        Mock -ModuleName selection Read-Host { return '2' }
        Mock -ModuleName selection Write-Host {}

        $null = & $script:InvokeBenchmarkScriptPath `
            -BenchmarksRoot $script:BenchmarksRoot `
            -MarkerPath $script:MarkerPath

        $LASTEXITCODE | Should -Be 0
        (Get-Content -Path $script:MarkerPath -Raw).Trim() | Should -Be 'second'
    }

    It '检测到 fzf 时优先走 fzf 选择路径' {
        $fzfMarkerPath = Join-Path $TestDrive 'fzf-used.txt'
        $null = & $script:NewTestBenchmarkScript `
            -BenchmarksRoot $script:BenchmarksRoot `
            -FileName 'OnlyChoice.Benchmark.ps1' `
            -Body @'
param([string]$MarkerPath)

Set-Content -Path $MarkerPath -Value 'fzf-selected'
'@
        $null = & $script:NewTestFzfExecutable -ToolsPath $script:ToolsPath

        $env:PATH = $script:ToolsPath
        $env:FAKE_FZF_MARKER = $fzfMarkerPath

        $null = & $script:InvokeBenchmarkScriptPath `
            -BenchmarksRoot $script:BenchmarksRoot `
            -MarkerPath $script:MarkerPath

        $LASTEXITCODE | Should -Be 0
        (Test-Path $fzfMarkerPath) | Should -BeTrue
        (Get-Content -Path $script:MarkerPath -Raw).Trim() | Should -Be 'fzf-selected'
    }

    It '取消选择时安全返回且不执行任何 benchmark' {
        $null = & $script:NewTestBenchmarkScript `
            -BenchmarksRoot $script:BenchmarksRoot `
            -FileName 'OnlyChoice.Benchmark.ps1' `
            -Body @'
param([string]$MarkerPath)

Set-Content -Path $MarkerPath -Value 'should-not-run'
'@

        $env:PATH = $script:ToolsPath
        Import-Module $script:SelectionModulePath -Force
        Mock -ModuleName selection Test-InteractiveSelectionFzfAvailable { return $false }
        Mock -ModuleName selection Read-Host { return '' }
        Mock -ModuleName selection Write-Host {}

        $null = & $script:InvokeBenchmarkScriptPath `
            -BenchmarksRoot $script:BenchmarksRoot `
            -MarkerPath $script:MarkerPath

        $LASTEXITCODE | Should -Be 0
        (Test-Path $script:MarkerPath) | Should -BeFalse
    }

    It '仓库内的 help-search benchmark 可通过显式名称执行' {
        $helpSearchInputRoot = Join-Path $script:TestRoot 'help-search-input'
        $helpSearchOutputPath = Join-Path $script:TestRoot 'help-search-report.json'
        New-Item -Path $helpSearchInputRoot -ItemType Directory -Force | Out-Null

        # 使用最小输入目录做 smoke，验证 benchmark 路由与报告输出，
        # 避免把真实仓库全量扫描成本重新带进这个 CLI 测试文件。
        Set-Content -Path (Join-Path $helpSearchInputRoot 'SampleModule.psm1') -Encoding utf8NoBOM -Value @'
<#
.SYNOPSIS
    测试搜索模块
#>
function Get-BenchmarkThing {
    <#
    .SYNOPSIS
        帮助搜索 smoke
    #>
    param()
    return 'ok'
}
'@

        $benchmarkOutput = & $script:InvokeBenchmarkScriptPath `
            'help-search' `
            -SearchTerm 'Benchmark' `
            -ModulePath $helpSearchInputRoot `
            -OutputPath $helpSearchOutputPath `
            -AsJson

        $LASTEXITCODE | Should -Be 0
        $benchmarkOutput | Should -Not -BeNullOrEmpty
        (Test-Path $helpSearchOutputPath) | Should -BeTrue

        $report = Get-Content -Path $helpSearchOutputPath -Raw | ConvertFrom-Json
        $report.SearchTerm | Should -Be 'Benchmark'
        $report.ModulePath | Should -Be $helpSearchInputRoot
        [double]$report.CustomTimeMs | Should -BeGreaterOrEqual 0
        [double]$report.GetHelpTimeMs | Should -BeGreaterOrEqual 0
    }
}
