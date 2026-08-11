BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot

    function Invoke-WindowsEntrypointProcess {
        <#
        .SYNOPSIS
            在独立 pwsh 进程执行 Windows 安装入口。

        .PARAMETER ScriptPath
            要执行的 PowerShell 脚本路径。

        .PARAMETER ArgumentList
            传给脚本的参数数组。

        .OUTPUTS
            PSCustomObject。包含 ExitCode、Stdout 和 Stderr。
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$ScriptPath,

            [string[]]$ArgumentList
        )

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = (Get-Command pwsh -ErrorAction Stop).Source
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $ScriptPath) + @($ArgumentList)) {
            $startInfo.ArgumentList.Add([string]$argument)
        }
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        try {
            $null = $process.Start()
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout; Stderr = $stderr }
        }
        finally {
            $process.Dispose()
        }
    }
}

Describe 'Windows 安装入口 smoke' {
    It 'Core 预览先声明 Extras bucket 再包含 Shell 工具与 Delta' {
        $result = Invoke-WindowsEntrypointProcess `
            -ScriptPath (Join-Path $script:RepoRoot 'windows/05installCoreCli.ps1') `
            -ArgumentList @('-WhatIf')
        $text = $result.Stdout + $result.Stderr

        $result.ExitCode | Should -Be 0
        $bucketMatch = [regex]::Match($text, '(?m)^\[Preview\] bucket:extras: ')
        $deltaMatch = [regex]::Match($text, '(?m)^\[(?:Preview|AlreadyPresent)\] delta: ')
        $carapaceMatch = [regex]::Match($text, '(?m)^\[(?:Preview|AlreadyPresent)\] carapace-bin: ')
        $atuinMatch = [regex]::Match($text, '(?m)^\[(?:Preview|AlreadyPresent)\] atuin: ')
        $bucketMatch.Success | Should -BeTrue
        $deltaMatch.Success | Should -BeTrue
        $carapaceMatch.Success | Should -BeTrue
        $atuinMatch.Success | Should -BeTrue
        $bucketMatch.Index | Should -BeLessThan $deltaMatch.Index
        $bucketMatch.Index | Should -BeLessThan $carapaceMatch.Index
        $bucketMatch.Index | Should -BeLessThan $atuinMatch.Index
    }

    It '03 WhatIf 输出单个可解析 JSON document' {
        $result = Invoke-WindowsEntrypointProcess `
            -ScriptPath (Join-Path $script:RepoRoot 'windows/03configureSources.ps1') `
            -ArgumentList @('-NetworkMode', 'Direct', '-TransactionId', 'windows-test', '-OutputFormat', 'Json', '-WhatIf')
        $result.ExitCode | Should -Be 0
        $document = $result.Stdout | ConvertFrom-Json
        $document.SchemaVersion | Should -Be 1
        @($document.Results.Target) | Should -Contain 'winget'
        @($document.Results.Target) | Should -Contain 'npm'
    }

    It '99 始终输出单个 JSON document' {
        $result = Invoke-WindowsEntrypointProcess `
            -ScriptPath (Join-Path $script:RepoRoot 'windows/99verifyInstall.ps1') `
            -ArgumentList @('-Preset', 'Core', '-Step', 'repo', '-OutputFormat', 'Json')
        $document = $result.Stdout | ConvertFrom-Json
        $document.SchemaVersion | Should -Be 1
        $document.Preset | Should -Be 'Core'
        @($document.Results.Step) | Should -Be @('repo')
    }
}
