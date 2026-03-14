Set-StrictMode -Version Latest

BeforeAll {
    $script:InvokeBenchmarkScriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'pwsh' 'devops' 'Invoke-Benchmark.ps1'
    $script:PwshPath = (Get-Process -Id $PID).Path
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
}

Describe 'Invoke-Benchmark.ps1' {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
        $script:BenchmarksRoot = Join-Path $script:TestRoot 'benchmarks'
        $script:MarkerPath = Join-Path $script:TestRoot 'marker.txt'
        $script:ToolsPath = Join-Path $script:TestRoot 'tools'
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

        & $script:PwshPath -NoProfile -File $script:InvokeBenchmarkScriptPath `
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

        '2' | & $script:PwshPath -NoProfile -File $script:InvokeBenchmarkScriptPath `
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

        Set-Content -Path (Join-Path $script:ToolsPath 'fzf.cmd') -Value @'
@echo off
if defined FAKE_FZF_MARKER (
  > "%FAKE_FZF_MARKER%" echo used
)
set "FIRST_LINE="
set /p FIRST_LINE=
if defined FIRST_LINE echo %FIRST_LINE%
exit /b 0
'@

        $env:PATH = $script:ToolsPath
        $env:FAKE_FZF_MARKER = $fzfMarkerPath

        & $script:PwshPath -NoProfile -File $script:InvokeBenchmarkScriptPath `
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

        '' | & $script:PwshPath -NoProfile -File $script:InvokeBenchmarkScriptPath `
            -BenchmarksRoot $script:BenchmarksRoot `
            -MarkerPath $script:MarkerPath

        $LASTEXITCODE | Should -Be 0
        (Test-Path $script:MarkerPath) | Should -BeFalse
    }
}
