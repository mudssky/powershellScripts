Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $script:BootstrapPath = Join-Path $script:RepoRoot 'scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1'
    $script:PwshPath = (Get-Process -Id $PID).Path

    function Invoke-PackageSourceBootstrapCli {
        <#
        .SYNOPSIS
            在隔离子进程中执行 Windows Stage 0 helper。

        .PARAMETER Arguments
            传给 helper 的参数。

        .OUTPUTS
            PSCustomObject。包含 ExitCode、StdOut 与 StdErr。
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string[]]$Arguments
        )

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $script:PwshPath
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $script:BootstrapPath) + $Arguments) {
            $startInfo.ArgumentList.Add($argument)
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    }
}

Describe 'Invoke-PackageSourceBootstrap.ps1' {
    It 'PowerShell parser 不报告语法错误' {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:BootstrapPath,
            [ref]$tokens,
            [ref]$errors
        )

        @($errors).Count | Should -Be 0
    }

    It 'Direct dry-run 返回稳定 JSON 且不要求 Windows' {
        $result = Invoke-PackageSourceBootstrapCli -Arguments @(
            '-Mode', 'Direct',
            '-DryRun',
            '-OutputFormat', 'Json'
        )

        $result.ExitCode | Should -Be 0 -Because $result.StdErr
        $document = $result.StdOut | ConvertFrom-Json
        $document.Status | Should -Be 'Direct'
        $document.ExitCode | Should -Be 0
    }

    It '非 Windows 的 China 模式明确返回 Blocked' {
        if ($IsWindows) {
            Set-ItResult -Skipped -Because '该断言只验证非 Windows 防护'
            return
        }

        $result = Invoke-PackageSourceBootstrapCli -Arguments @(
            '-Mode', 'China',
            '-DryRun',
            '-OutputFormat', 'Json'
        )

        $result.ExitCode | Should -Be 10
        $document = $result.StdOut | ConvertFrom-Json
        $document.Status | Should -Be 'Blocked'
        $document.Message | Should -Match '只能在 Windows'
    }
}
