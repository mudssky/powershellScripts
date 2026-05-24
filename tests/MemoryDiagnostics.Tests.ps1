Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:ToolRoot = Join-Path $script:RepoRoot 'scripts/pwsh/devops/memory-diagnostics'
    $script:OriginalSkipMemoryDiagnosticsMain = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_MEMORY_DIAGNOSTICS_MAIN', 'Process')
    $env:PWSH_TEST_SKIP_MEMORY_DIAGNOSTICS_MAIN = '1'

    . (Join-Path $script:ToolRoot 'main.ps1')
}

AfterAll {
    if ($null -eq $script:OriginalSkipMemoryDiagnosticsMain) {
        Remove-Item Env:\PWSH_TEST_SKIP_MEMORY_DIAGNOSTICS_MAIN -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('PWSH_TEST_SKIP_MEMORY_DIAGNOSTICS_MAIN', $script:OriginalSkipMemoryDiagnosticsMain, 'Process')
    }
}

Describe 'Memory diagnostics tool manifest' {
    It '通过目录型工具清单暴露单一入口' {
        $manifestPath = Join-Path $script:ToolRoot 'tool.psd1'
        $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath

        $manifest.BinName | Should -Be 'Invoke-MemoryDiagnostics.ps1'
        $manifest.Entry | Should -Be 'main.ps1'
        Test-Path -LiteralPath (Join-Path $script:ToolRoot $manifest.Entry) | Should -BeTrue
    }
}

Describe 'Memory diagnostics command routing' {
    It '未传命令时默认执行 snapshot' {
        Mock New-MemoryDiagnosticsReport {
            [pscustomobject]@{
                metadata        = [pscustomobject]@{ mode = 'snapshot' }
                system          = [pscustomobject]@{}
                topProcesses    = @()
                containers      = [pscustomobject]@{}
                windowsOnly     = $null
                samples         = @()
                warnings        = @()
                recommendations = @()
            }
        }

        $result = Invoke-MemoryDiagnosticsCommand -CommandName '' -Top 1 -Depth basic -IntervalSeconds 0 -Count 1

        $result.ExitCode | Should -Be 0
        $result.OutputObject.metadata.mode | Should -Be 'snapshot'
        Should -Invoke New-MemoryDiagnosticsReport -Times 1 -Exactly
    }

    It '未知命令返回错误码和帮助文本' {
        $result = Invoke-MemoryDiagnosticsCommand -CommandName 'bad-command'

        $result.ExitCode | Should -Be 2
        $result.Output | Should -Match '未知命令'
        $result.Output | Should -Match 'snapshot'
    }
}

Describe 'Memory diagnostics parsers' {
    It '解析 Linux meminfo 为统一系统指标' {
        $system = ConvertFrom-LinuxMemInfo -Lines @(
            'MemTotal:       32768000 kB'
            'MemAvailable:   8192000 kB'
            'SwapTotal:      4194304 kB'
            'SwapFree:       1048576 kB'
            'CommitLimit:    37748736 kB'
            'Committed_AS:   18874368 kB'
        )

        $system.platform | Should -Be 'Linux'
        $system.totalPhysicalGB | Should -Be 31.25
        $system.availableGB | Should -Be 7.81
        $system.swapUsedGB | Should -Be 3
        $system.commitPercent | Should -Be 50
    }

    It '解析 ps 行为统一进程对象' {
        $process = ConvertFrom-MemoryDiagnosticsPsLine -Line ' 123 1 code 204800 409600 12.5' -Source 'linux-ps'

        $process.processName | Should -Be 'code'
        $process.id | Should -Be 123
        $process.parentId | Should -Be 1
        $process.workingSetMB | Should -Be 200
        $process.virtualMemoryMB | Should -Be 400
        $process.percentMemory | Should -Be 12.5
    }

    It '解析 Docker stats JSON 行' {
        $container = ConvertFrom-DockerStatsJsonLine -Line '{"Container":"abc123","Name":"postgres","MemUsage":"512MiB / 2GiB","MemPerc":"25.00%"}'

        $container.containerId | Should -Be 'abc123'
        $container.name | Should -Be 'postgres'
        $container.memoryUsageMB | Should -Be 512
        $container.memoryLimitMB | Should -Be 2048
        $container.memoryPercent | Should -Be 25
    }
}

Describe 'Memory diagnostics recommendations' {
    It '提示 Windows kernel pool 异常不要只看进程列表' {
        $report = [pscustomobject]@{
            system       = [pscustomobject]@{
                totalPhysicalGB  = 32
                availablePercent = 30
                commitPercent    = 50
                kernelPoolGB     = 13
                nonPagedPoolGB   = 7
            }
            topProcesses = @()
            containers   = [pscustomobject]@{ available = $true; status = 'available'; totalMemoryMB = 100 }
        }

        $recommendations = Get-MemoryDiagnosticsRecommendations -Report $report

        $recommendations.code | Should -Contain 'windows.kernel_pool_suspect'
        ($recommendations | Where-Object code -eq 'windows.kernel_pool_suspect').nextActions -join ' ' | Should -Match 'RAMMap'
    }

    It '提示高内存 Top 进程' {
        $report = [pscustomobject]@{
            system       = [pscustomobject]@{
                totalPhysicalGB  = 16
                availablePercent = 40
                commitPercent    = 40
                kernelPoolGB     = 1
                nonPagedPoolGB   = 0.5
            }
            topProcesses = @(
                [pscustomobject]@{
                    processName  = 'Code'
                    id           = 42
                    workingSetMB = 4096
                }
            )
            containers   = [pscustomobject]@{ available = $true; status = 'available'; totalMemoryMB = 200 }
        }

        $recommendations = Get-MemoryDiagnosticsRecommendations -Report $report

        $recommendations.code | Should -Contain 'process.high_top_process'
    }

    It 'Docker 不可用时返回可审计建议' {
        $report = [pscustomobject]@{
            system       = [pscustomobject]@{
                totalPhysicalGB  = 32
                availablePercent = 50
                commitPercent    = 50
                kernelPoolGB     = 1
                nonPagedPoolGB   = 0.5
            }
            topProcesses = @()
            containers   = [pscustomobject]@{ available = $false; status = 'command_missing'; totalMemoryMB = 0 }
        }

        $recommendations = Get-MemoryDiagnosticsRecommendations -Report $report

        $recommendations.code | Should -Contain 'docker.unavailable'
    }
}

Describe 'Memory diagnostics sampling' {
    It '按指定次数采样并保留样本数组' {
        Mock New-MemoryDiagnosticsReport {
            [pscustomobject]@{
                metadata        = [pscustomobject]@{ mode = 'snapshot' }
                system          = [pscustomobject]@{}
                topProcesses    = @()
                containers      = [pscustomobject]@{}
                windowsOnly     = $null
                samples         = @()
                warnings        = @()
                recommendations = @(
                    [pscustomobject]@{ code = 'demo'; severity = 'info' }
                )
            }
        }

        $result = Invoke-MemoryDiagnosticsSampling -Count 2 -IntervalSeconds 0 -Top 1 -Depth basic

        @($result.samples).Count | Should -Be 2
        $result.metadata.mode | Should -Be 'sample'
        $result.recommendations.code | Should -Contain 'demo'
    }
}

Describe 'Memory diagnostics public script' {
    It '输出 snapshot JSON' {
        $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
        Remove-Item Env:\PWSH_TEST_SKIP_MEMORY_DIAGNOSTICS_MAIN -ErrorAction SilentlyContinue
        try {
            $output = & $pwshPath -NoProfile -File (Join-Path $script:ToolRoot 'main.ps1') snapshot -Top 1 -Depth basic 2>&1
        }
        finally {
            $env:PWSH_TEST_SKIP_MEMORY_DIAGNOSTICS_MAIN = '1'
        }

        $LASTEXITCODE | Should -Be 0
        $jsonText = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
        $jsonText.TrimStart() | Should -Match '^\{'
        $json = $jsonText | ConvertFrom-Json
        $json.metadata.mode | Should -Be 'snapshot'
        $json.system.platform | Should -Not -BeNullOrEmpty
        @($json.topProcesses).Count | Should -BeLessOrEqual 1
        $json.PSObject.Properties.Name | Should -Contain 'recommendations'
    }
}
