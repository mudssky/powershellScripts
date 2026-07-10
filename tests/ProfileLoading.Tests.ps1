Set-StrictMode -Version Latest

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ProfileRoot = Join-Path $script:ProjectRoot 'profile'
    $script:ProfilePath = Join-Path $script:ProfileRoot 'profile.ps1'
    $script:DebugProfilePath = Join-Path $script:ProfileRoot 'Debug-ProfilePerformance.ps1'
    $script:PwshPath = (Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
    . (Join-Path $script:ProfileRoot 'core/platform.ps1')

    function Invoke-ProfileContractChild {
        <#
        .SYNOPSIS
            在独立 pwsh 进程执行 Profile 契约脚本并解析最后一行 JSON。

        .PARAMETER Body
            子进程中在 Profile 加载后执行的断言数据构造脚本。

        .PARAMETER Mode
            子进程使用的 Profile 模式。

        .PARAMETER ProfilePath
            可选的 Profile 入口路径。

        .OUTPUTS
            System.Management.Automation.PSCustomObject
            返回子进程退出码、原始输出和解析后的 JSON 对象。
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Body,
            [ValidateSet('Full', 'Minimal', 'UltraMinimal')]
            [string]$Mode = 'UltraMinimal',
            [string]$ProfilePath = $script:ProfilePath
        )

        $escapedProfilePath = $ProfilePath.Replace("'", "''")
        $modeSetup = switch ($Mode) {
            'Full' { "`$env:POWERSHELL_PROFILE_FULL = '1'" }
            'Minimal' { "`$env:POWERSHELL_PROFILE_MODE = 'minimal'" }
            'UltraMinimal' { "`$env:POWERSHELL_PROFILE_MODE = 'ultra'" }
        }
        $childScript = @"
foreach (`$name in @('POWERSHELL_PROFILE_FULL','POWERSHELL_PROFILE_MODE','POWERSHELL_PROFILE_ULTRA_MINIMAL','CODEX_THREAD_ID','CODEX_SANDBOX_NETWORK_DISABLED')) {
    Remove-Item "Env:`$name" -ErrorAction SilentlyContinue
}
$modeSetup
. '$escapedProfilePath'
$Body
"@
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $script:PwshPath
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.ArgumentList.Add('-NoProfile')
        $startInfo.ArgumentList.Add('-NoLogo')
        $startInfo.ArgumentList.Add('-EncodedCommand')
        $startInfo.ArgumentList.Add($encodedCommand)

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $process.Start() | Out-Null
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $standardOutput = $stdoutTask.GetAwaiter().GetResult()
        $standardError = $stderrTask.GetAwaiter().GetResult()
        $output = @(
            $standardOutput -split '\r?\n'
            $standardError -split '\r?\n'
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $jsonLine = @($output | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -Last 1)
        $data = if ($jsonLine.Count -gt 0) { $jsonLine[0] | ConvertFrom-Json } else { $null }

        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            Output   = @($output)
            Data     = $data
        }
    }
}

Describe 'Profile platform context' {
    It 'should expose the expected Windows policy' {
        $context = Get-ProfilePlatformContext -Platform Windows

        $context.Id | Should -Be 'windows'
        $context.IsWindows | Should -BeTrue
        $context.CoreModules | Should -Be @('os', 'cache', 'commandDiscovery', 'proxy', 'wrapper')
        $context.PackageManagers | Should -Be @('scoop', 'winget', 'choco')
        $context.SyncBashPath | Should -BeFalse
        $context.CacheId | Should -Be 'win'
    }

    It 'should share Unix modules while keeping Linux-only PATH sync' {
        $macos = Get-ProfilePlatformContext -Platform MacOS
        $linux = Get-ProfilePlatformContext -Platform Linux

        $macos.CoreModules | Should -Be $linux.CoreModules
        $macos.IsUnix | Should -BeTrue
        $linux.IsUnix | Should -BeTrue
        $macos.SyncBashPath | Should -BeFalse
        $linux.SyncBashPath | Should -BeTrue
        $macos.PackageManagers | Should -Be @('brew')
        $linux.PackageManagers | Should -Be @('brew', 'apt')
    }
}

Describe 'Profile real entry contracts' {
    It 'UltraMinimal should keep public functions without loading psutils modules' {
        $body = @'
$repoRoot = Split-Path -Parent $script:ProfileRoot
$moduleCount = @(Get-Module | Where-Object { $_.Path -like "$repoRoot/psutils/modules/*" }).Count
[PSCustomObject]@{
    Mode = $script:ProfileMode
    ModuleCount = $moduleCount
    HasHelp = [bool](Get-Command Show-MyProfileHelp -ErrorAction SilentlyContinue)
    HasInitialize = [bool](Get-Command Initialize-Environment -ErrorAction SilentlyContinue)
    HasInstall = [bool](Get-Command Set-PowerShellProfile -ErrorAction SilentlyContinue)
    HasRuntimeDefinitions = $script:ProfileTimings.Contains('runtime-definitions')
    HasRepositoryBin = @($env:PATH -split [regex]::Escape([string][IO.Path]::PathSeparator)) -contains (Join-Path $env:POWERSHELL_SCRIPTS_ROOT 'bin')
} | ConvertTo-Json -Compress
'@
        $result = Invoke-ProfileContractChild -Body $body -Mode UltraMinimal

        $result.ExitCode | Should -Be 0 -Because ($result.Output -join [Environment]::NewLine)
        $result.Data.Mode | Should -Be 'UltraMinimal'
        $result.Data.ModuleCount | Should -Be 0
        $result.Data.HasHelp | Should -BeTrue
        $result.Data.HasInitialize | Should -BeTrue
        $result.Data.HasInstall | Should -BeTrue
        $result.Data.HasRuntimeDefinitions | Should -BeFalse
        $result.Data.HasRepositoryBin | Should -BeTrue
    }

    It 'Minimal should keep core commands and skip user aliases' {
        $body = @'
[PSCustomObject]@{
    Mode = $script:ProfileMode
    UserAliasCount = $script:userAlias.Count
    HasCache = [bool](Get-Command Invoke-WithCache -ErrorAction SilentlyContinue)
    HasCommandDiscovery = [bool](Get-Command Find-ExecutableCommand -ErrorAction SilentlyContinue)
    HasProxy = [bool](Get-Command Set-Proxy -ErrorAction SilentlyContinue)
    OnIdleCount = @(Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue).Count
} | ConvertTo-Json -Compress
'@
        $result = Invoke-ProfileContractChild -Body $body -Mode Minimal

        $result.ExitCode | Should -Be 0 -Because ($result.Output -join [Environment]::NewLine)
        $result.Data.Mode | Should -Be 'Minimal'
        $result.Data.UserAliasCount | Should -Be 0
        $result.Data.HasCache | Should -BeTrue
        $result.Data.HasCommandDiscovery | Should -BeTrue
        $result.Data.HasProxy | Should -BeTrue
        $result.Data.OnIdleCount | Should -Be 1
    }

    It 'reloading Profile should keep one OnIdle subscription' {
        $escapedProfilePath = $script:ProfilePath.Replace("'", "''")
        $body = @"
. '$escapedProfilePath'
[PSCustomObject]@{
    OnIdleCount = @(Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue).Count
    State = `$Global:__PowerShellProfileOnIdleState.Status
} | ConvertTo-Json -Compress
"@
        $result = Invoke-ProfileContractChild -Body $body -Mode Minimal

        $result.ExitCode | Should -Be 0 -Because ($result.Output -join [Environment]::NewLine)
        $result.Data.OnIdleCount | Should -Be 1
        $result.Data.State | Should -Be 'Registered'
    }

    It 'missing core modules should visibly fall back to UltraMinimal' {
        $temporaryRepository = Join-Path $TestDrive 'missing-core-repository'
        $temporaryProfileRoot = Join-Path $temporaryRepository 'profile'
        Copy-Item -Path $script:ProfileRoot -Destination $temporaryProfileRoot -Recurse -Force
        $temporaryProfilePath = Join-Path $temporaryProfileRoot 'profile.ps1'
        $body = @'
[PSCustomObject]@{
    Mode = $script:ProfileMode
    FallbackComponent = $script:ProfileFallback.Component
    HasRepositoryRoot = -not [string]::IsNullOrWhiteSpace($env:POWERSHELL_SCRIPTS_ROOT)
} | ConvertTo-Json -Compress
'@

        $result = Invoke-ProfileContractChild -Body $body -Mode Minimal -ProfilePath $temporaryProfilePath

        $result.ExitCode | Should -Be 0 -Because ($result.Output -join [Environment]::NewLine)
        $result.Data.Mode | Should -Be 'UltraMinimal'
        $result.Data.FallbackComponent | Should -Be 'core-loaders'
        $result.Data.HasRepositoryRoot | Should -BeTrue
        ($result.Output -join [Environment]::NewLine) | Should -Match '\[ProfileFallback\].*component=core-loaders'
    }
}

Describe 'Profile performance diagnostic contract' {
    It 'should summarize real UltraMinimal samples as JSON' {
        $output = @(& $script:PwshPath -NoProfile -NoLogo -File $script:DebugProfilePath -Mode UltraMinimal -Iterations 2 -AsJson 2>&1)
        $exitCode = $LASTEXITCODE
        $report = ($output -join [Environment]::NewLine) | ConvertFrom-Json

        $exitCode | Should -Be 0
        $report.Mode | Should -Be 'UltraMinimal'
        $report.Iterations | Should -Be 2
        $report.ProfileInternal.SamplesMs.Count | Should -Be 2
        $report.ProcessElapsed.SamplesMs.Count | Should -Be 2
        $report.Phases.PSObject.Properties.Name | Should -Contain 'bootstrap-definitions'
        $report.Phases.PSObject.Properties.Name | Should -Not -Contain 'core-loaders'
    }
}
