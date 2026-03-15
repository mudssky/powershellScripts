Set-StrictMode -Version Latest

BeforeAll {
    $script:InvokeBenchmarkScriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'pwsh' 'devops' 'Invoke-Benchmark.ps1'
    $script:PwshPath = (Get-Process -Id $PID).Path
    $script:SelectionModulePath = Join-Path $PSScriptRoot '..' 'psutils' 'modules' 'selection.psm1'
    $script:OriginalInProcessBenchmarkFlag = [Environment]::GetEnvironmentVariable('PWSH_TEST_IN_PROCESS_BENCHMARK', 'Process')
    $script:OriginalSkipBenchmarkMainFlag = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_BENCHMARK_MAIN', 'Process')
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

}

Describe 'Invoke-Benchmark helper functions' {
    BeforeAll {
        $env:PWSH_TEST_IN_PROCESS_BENCHMARK = '1'
        $env:PWSH_TEST_SKIP_BENCHMARK_MAIN = '1'
        . $script:InvokeBenchmarkScriptPath
    }

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

        Remove-Module selection -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $script:ToolsPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    AfterAll {
        if ($null -eq $script:OriginalSkipBenchmarkMainFlag) {
            Remove-Item Env:\PWSH_TEST_SKIP_BENCHMARK_MAIN -ErrorAction SilentlyContinue
        }
        else {
            $env:PWSH_TEST_SKIP_BENCHMARK_MAIN = $script:OriginalSkipBenchmarkMainFlag
        }

        if ($null -eq $script:OriginalInProcessBenchmarkFlag) {
            Remove-Item Env:\PWSH_TEST_IN_PROCESS_BENCHMARK -ErrorAction SilentlyContinue
        }
        else {
            $env:PWSH_TEST_IN_PROCESS_BENCHMARK = $script:OriginalInProcessBenchmarkFlag
        }

        foreach ($functionName in @(
                'ConvertTo-BenchmarkName'
                'Get-BenchmarkCatalog'
                'Import-BenchmarkSelectionModule'
                'Select-BenchmarkCatalogItem'
                'Resolve-BenchmarkCatalogItem'
                'Complete-BenchmarkScript'
                'Test-BenchmarkQuietMode'
                'Write-BenchmarkHostMessage'
                'Write-BenchmarkHostWarning'
                'Invoke-BenchmarkCatalogItem'
                'Invoke-BenchmarkCommand'
            )) {
            Remove-Item -Path ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
    }

    It '显式名称解析时不会走交互选择' {
        $null = & $script:NewTestBenchmarkScript `
            -BenchmarksRoot $script:BenchmarksRoot `
            -FileName 'SampleOne.Benchmark.ps1' `
            -Body "param([string]`$MarkerPath) Set-Content -Path `"$script:MarkerPath`" -Value 'sample'"

        $catalog = Get-BenchmarkCatalog -BenchmarksRoot $script:BenchmarksRoot
        Mock Select-BenchmarkCatalogItem { throw '不应调用交互选择' }

        $selected = Resolve-BenchmarkCatalogItem -Catalog $catalog -Name 'sample-one' -RepoRoot $PWD.Path

        $selected.Name | Should -Be 'sample-one'
    }

    It '未知名称时会抛出包含可用值的错误' {
        $null = & $script:NewTestBenchmarkScript `
            -BenchmarksRoot $script:BenchmarksRoot `
            -FileName 'OnlyChoice.Benchmark.ps1' `
            -Body "param([string]`$MarkerPath) Set-Content -Path `"$script:MarkerPath`" -Value 'only'"

        $catalog = Get-BenchmarkCatalog -BenchmarksRoot $script:BenchmarksRoot

        {
            Resolve-BenchmarkCatalogItem -Catalog $catalog -Name 'missing-benchmark' -RepoRoot $PWD.Path
        } | Should -Throw '未知 benchmark: missing-benchmark。可用值: only-choice'
    }

    It '交互取消时返回零退出码且不执行 benchmark' {
        $null = & $script:NewTestBenchmarkScript `
            -BenchmarksRoot $script:BenchmarksRoot `
            -FileName 'OnlyChoice.Benchmark.ps1' `
            -Body "param([string]`$MarkerPath) Set-Content -Path `"$script:MarkerPath`" -Value 'only'"

        Mock Select-BenchmarkCatalogItem { return $null }
        Mock Invoke-BenchmarkCatalogItem { throw '取消路径不应执行 benchmark' }

        $result = Invoke-BenchmarkCommand -BenchmarksRoot $script:BenchmarksRoot

        $result.ExitCode | Should -Be 0
        $result.Selected | Should -BeNullOrEmpty
        Should -Invoke Invoke-BenchmarkCatalogItem -Times 0
        (Test-Path $script:MarkerPath) | Should -BeFalse
    }

    It '交互选择路径会将选中的 benchmark 和参数透传给执行器' {
        $expectedPath = & $script:NewTestBenchmarkScript `
            -BenchmarksRoot $script:BenchmarksRoot `
            -FileName 'OnlyChoice.Benchmark.ps1' `
            -Body "param([string]`$MarkerPath) Set-Content -Path `"$script:MarkerPath`" -Value 'only'"

        $selectedItem = [PSCustomObject]@{
            Name = 'only-choice'
            Path = $expectedPath
            File = 'OnlyChoice.Benchmark.ps1'
        }

        Mock Select-BenchmarkCatalogItem { return $selectedItem }
        Mock Invoke-BenchmarkCatalogItem {
            return [PSCustomObject]@{
                ExitCode = 0
                Output   = @('mock-output')
            }
        } -ParameterFilter {
            $BenchmarkPath -eq $expectedPath -and
            $BenchmarkArgs.Count -eq 2 -and
            $BenchmarkArgs[0] -eq '-MarkerPath' -and
            $BenchmarkArgs[1] -eq $script:MarkerPath
        }

        $result = Invoke-BenchmarkCommand `
            -BenchmarksRoot $script:BenchmarksRoot `
            -BenchmarkArgs @('-MarkerPath', $script:MarkerPath)

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Be @('mock-output')
        $result.Selected.Name | Should -Be 'only-choice'
        Should -Invoke Invoke-BenchmarkCatalogItem -Times 1
    }

    It '仓库 catalog 中仍可发现 help-search benchmark' {
        $repoBenchmarksRoot = Join-Path $PSScriptRoot 'benchmarks'
        $catalog = Get-BenchmarkCatalog -BenchmarksRoot $repoBenchmarksRoot

        $selected = Resolve-BenchmarkCatalogItem -Catalog $catalog -Name 'help-search' -RepoRoot $PWD.Path

        $selected.File | Should -Be 'HelpSearch.Benchmark.ps1'
    }
}
