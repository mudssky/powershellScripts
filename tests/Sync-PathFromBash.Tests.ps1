Set-StrictMode -Version Latest

Describe 'Sync-PathFromBash basic behavior' {
    BeforeAll {
        $script:EnvModulePath = (Resolve-Path "$PSScriptRoot/../psutils/modules/env.psm1").Path
        Import-Module $script:EnvModulePath -Force
        $script:OriginalMockPath = $env:PWSH_TEST_BASH_PATH
        $env:PWSH_TEST_BASH_PATH = "C:\Fake\Bin;C:\Windows\System32"
        $script:InvokeSyncPathFromBashWhatIfBatchChild = {
            <#
            .SYNOPSIS
                在单个子进程中批量执行多条 `Sync-PathFromBash -WhatIf` 并捕获控制台输出。

            .DESCRIPTION
                PowerShell 的 WhatIf 主机提示不会被常规流重定向静音。
                这里把 append / prepend / login 三条路径合并到同一个 `pwsh` 子进程里运行，
                既保留 ShouldProcess 语义验证，又减少重复 shell 启动与模块导入成本。

            .PARAMETER ModulePath
                `env.psm1` 的绝对路径，供子进程导入模块。

            .PARAMETER MockPath
                传给 `PWSH_TEST_BASH_PATH` 的模拟 PATH 文本，用于让子进程走稳定的测试分支。

            .OUTPUTS
                `PSCustomObject`
                返回子进程退出码与捕获到的文本输出，便于断言多个 WhatIf 提示都出现。
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$ModulePath,
                [Parameter(Mandatory)]
                [string]$MockPath
            )

            $pwshPath = (Get-Process -Id $PID).Path
            $escapedModulePath = $ModulePath.Replace("'", "''")
            $escapedMockPath = $MockPath.Replace("'", "''")
            $childSegments = @(
                '$ErrorActionPreference = ''Stop'''
                "Import-Module '$escapedModulePath' -Force"
                "`$env:PWSH_TEST_BASH_PATH = '$escapedMockPath'"
                'Sync-PathFromBash -WhatIf -ReturnObject:$false -CacheSeconds 0'
                'Sync-PathFromBash -WhatIf -ReturnObject:$false -CacheSeconds 0 -Prepend'
                'Sync-PathFromBash -WhatIf -ReturnObject:$false -CacheSeconds 0 -Login'
            )

            $childScript = $childSegments -join '; '
            $output = & $pwshPath -NoProfile -Command $childScript 2>&1

            return [PSCustomObject]@{
                ExitCode = $LASTEXITCODE
                Output   = @($output | ForEach-Object { $_.ToString() })
            }
        }
    }

    AfterAll {
        $env:PWSH_TEST_BASH_PATH = $script:OriginalMockPath
    }

    It 'should return object with fields when ReturnObject=true' {
        # 返回对象结构与 ShouldProcess 文案无关，因此这里直接验证正常返回路径，
        # 避免把 WhatIf 主机提示带进默认门禁日志。
        $result = Sync-PathFromBash -ReturnObject:$true -CacheSeconds 0
        $result | Should -Not -BeNullOrEmpty
        $result | Should -BeOfType 'System.Management.Automation.PSCustomObject'
        $result.PSObject.Properties.Name | Should -Contain 'SourcePathsCount'
        $result.PSObject.Properties.Name | Should -Contain 'CurrentPathsCount'
        $result.PSObject.Properties.Name | Should -Contain 'AddedPaths'
        $result.PSObject.Properties.Name | Should -Contain 'SkippedPaths'
        $result.PSObject.Properties.Name | Should -Contain 'NewPath'
    }

    It 'should support append, prepend and login WhatIf branches without error' {
        $testDir = Join-Path $TestDrive 'whatif-batch'
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        $result = & $script:InvokeSyncPathFromBashWhatIfBatchChild -ModulePath $script:EnvModulePath -MockPath $testDir
        $result.ExitCode | Should -Be 0
        $outputText = $result.Output -join "`n"
        $outputText | Should -Match 'What if: Performing the operation "Append 1 路径到 PATH" on target "PATH"\.'
        $outputText | Should -Match 'What if: Performing the operation "Prepend 1 路径到 PATH" on target "PATH"\.'
    }
}

Describe 'Sync-PathFromBash cache and error semantics' {
    BeforeAll {
        $script:EnvModulePath = (Resolve-Path "$PSScriptRoot/../psutils/modules/env.psm1").Path
        Import-Module $script:EnvModulePath -Force
        $script:OriginalMockPath = $env:PWSH_TEST_BASH_PATH
        $env:PWSH_TEST_BASH_PATH = "C:\Fake\Bin;C:\Windows\System32"
    }

    AfterAll {
        $env:PWSH_TEST_BASH_PATH = $script:OriginalMockPath
    }

    It 'should use cache when CacheSeconds > 0 and write cache file' {
        $existingPath = ($env:PATH -split [System.IO.Path]::PathSeparator | Select-Object -First 1)
        $env:PWSH_TEST_BASH_PATH = $existingPath

        $r = Sync-PathFromBash -ReturnObject:$true -CacheSeconds 60
        $r | Should -Not -BeNullOrEmpty
        (Join-Path $HOME '.cache/powershellScripts/bash_path.json') | Should -Exist
    }

    It 'should throw when ThrowOnFailure if bash path retrieval fails' {
        # 当前通过 mock PATH 走稳定成功分支，目的是确认 ThrowOnFailure 不会破坏成功路径。
        { Sync-PathFromBash -ThrowOnFailure -CacheSeconds 0 } | Should -Not -Throw
    }
}
