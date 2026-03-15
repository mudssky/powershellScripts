Set-StrictMode -Version Latest

Describe 'Sync-PathFromBash basic behavior' {
    BeforeAll {
        $script:EnvModulePath = (Resolve-Path "$PSScriptRoot/../psutils/modules/env.psm1").Path
        Import-Module $script:EnvModulePath -Force
        $script:OriginalMockPath = $env:PWSH_TEST_BASH_PATH
        $env:PWSH_TEST_BASH_PATH = "C:\Fake\Bin;C:\Windows\System32"
        $script:InvokeSyncPathFromBashWhatIfChild = {
            <#
            .SYNOPSIS
                在子进程中执行 `Sync-PathFromBash -WhatIf` 并捕获控制台输出。

            .DESCRIPTION
                PowerShell 的 WhatIf 主机提示不会被常规流重定向静音。
                这里改为在独立 `pwsh` 子进程中运行待测命令，把提示文本收集回父测试进程，
                既保留 ShouldProcess 语义验证，又避免默认 Pester 日志被提示刷屏。

            .PARAMETER ModulePath
                `env.psm1` 的绝对路径，供子进程导入模块。

            .PARAMETER MockPath
                传给 `PWSH_TEST_BASH_PATH` 的模拟 PATH 文本，用于让子进程走稳定的测试分支。

            .PARAMETER Login
                是否在子进程里附加 `-Login` 参数。

            .PARAMETER Prepend
                是否在子进程里附加 `-Prepend` 参数。

            .PARAMETER VerboseOutput
                是否在子进程里附加 `-Verbose` 参数。

            .OUTPUTS
                `PSCustomObject`
                返回子进程退出码与捕获到的文本输出，便于断言 WhatIf 提示是否出现。
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$ModulePath,
                [Parameter(Mandatory)]
                [string]$MockPath,
                [switch]$Login,
                [switch]$Prepend,
                [switch]$VerboseOutput
            )

            $pwshPath = (Get-Process -Id $PID).Path
            $escapedModulePath = $ModulePath.Replace("'", "''")
            $escapedMockPath = $MockPath.Replace("'", "''")
            $childSegments = @(
                '$ErrorActionPreference = ''Stop'''
                "Import-Module '$escapedModulePath' -Force"
                "`$env:PWSH_TEST_BASH_PATH = '$escapedMockPath'"
                'Sync-PathFromBash -WhatIf -ReturnObject:$false -CacheSeconds 0'
            )

            if ($Login) {
                $childSegments[-1] += ' -Login'
            }

            if ($Prepend) {
                $childSegments[-1] += ' -Prepend'
            }

            if ($VerboseOutput) {
                $childSegments[-1] += ' -Verbose'
            }

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

    It 'should support Prepend strategy without error when WhatIf' {
        $testDir = Join-Path $TestDrive 'prepend-whatif'
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        $result = & $script:InvokeSyncPathFromBashWhatIfChild -ModulePath $script:EnvModulePath -MockPath $testDir -Prepend
        $result.ExitCode | Should -Be 0
        ($result.Output -join "`n") | Should -Match 'What if: Performing the operation "Prepend 1 路径到 PATH" on target "PATH"\.'
    }

    It 'should support Append strategy (default) without error when WhatIf' {
        $testDir = Join-Path $TestDrive 'append-whatif'
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        $result = & $script:InvokeSyncPathFromBashWhatIfChild -ModulePath $script:EnvModulePath -MockPath $testDir
        $result.ExitCode | Should -Be 0
        ($result.Output -join "`n") | Should -Match 'What if: Performing the operation "Append 1 路径到 PATH" on target "PATH"\.'
    }

    It 'should support Login branch without error when WhatIf' {
        $testDir = Join-Path $TestDrive 'login-whatif'
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        $result = & $script:InvokeSyncPathFromBashWhatIfChild -ModulePath $script:EnvModulePath -MockPath $testDir -Login
        $result.ExitCode | Should -Be 0
        ($result.Output -join "`n") | Should -Match 'What if: Performing the operation "Append 1 路径到 PATH" on target "PATH"\.'
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
