Set-StrictMode -Version Latest

BeforeAll {
    $script:ProfileRootDir = Join-Path $PSScriptRoot '..' 'profile'
    Import-Module (Join-Path $PSScriptRoot '..' 'psutils/modules/commandDiscovery.psm1') -Force
    . (Join-Path $script:ProfileRootDir 'features/environment.ps1')
}

Describe 'Profile install hint helpers' {
    It 'Windows package manager priority should prefer scoop over winget and choco' {
        $result = Get-ProfilePreferredPackageManager -AvailableCommands @('choco', 'scoop', 'winget') -Platform 'windows'

        $result | Should -Be 'scoop'
    }

    It 'Linux package manager priority should fall back to apt when brew is unavailable' {
        $result = Get-ProfilePreferredPackageManager -AvailableCommands @('apt') -Platform 'linux'

        $result | Should -Be 'apt'
    }

    It 'should aggregate missing Windows tools into one scoop command' {
        $hint = Get-ProfileMissingToolInstallHint -ToolNames @('starship', 'zoxide') -AvailableCommands @('scoop', 'winget') -Platform 'windows'

        $hint.Message | Should -Be '未安装以下工具：starship、zoxide。可手动执行下面这行命令一次性安装。'
        $hint.Command | Should -Be 'scoop install starship zoxide'
        $hint.PackageManager | Should -Be 'scoop'
    }

    It 'should build one-line winget commands by chaining installs' {
        $command = Get-ProfilePackageManagerInstallCommand -PackageManager 'winget' -Packages @('starship', 'zoxide')

        $command | Should -Be 'winget install starship; winget install zoxide'
    }

    It 'should build a Linux apt command when brew is unavailable' {
        $hint = Get-ProfileMissingToolInstallHint -ToolNames @('starship', 'zoxide', 'fnm') -AvailableCommands @('apt') -Platform 'linux'

        $hint.Message | Should -Be '未安装以下工具：starship、zoxide、fnm。可手动执行下面这行命令一次性安装。'
        $hint.Command | Should -Be 'sudo apt install starship zoxide fnm'
        $hint.PackageManager | Should -Be 'apt'
    }

    It 'should return a message without command when the chosen package manager lacks mappings' {
        $hint = Get-ProfileMissingToolInstallHint -ToolNames @('starship', 'zoxide') -AvailableCommands @('choco') -Platform 'windows'

        $hint.Command | Should -BeNullOrEmpty
        $hint.Message | Should -Be '未安装以下工具：starship、zoxide。当前未找到可自动拼接的安装命令，请按当前系统包管理器手动安装。'
        $hint.PackageManager | Should -Be 'choco'
    }

    It 'should suppress skipped tools when calculating install hint eligibility' {
        $candidates = @('starship', 'zoxide', 'fnm') | Where-Object {
            Test-ProfileInstallHintEligibility -ToolName $_ -Platform 'linux' -SkipStarship -SkipZoxide:$false
        }

        @($candidates).Count | Should -Be 2
        $candidates[0] | Should -Be 'zoxide'
        $candidates[1] | Should -Be 'fnm'
    }

    It 'should not prompt fnm on Windows' {
        $result = Test-ProfileInstallHintEligibility -ToolName 'fnm' -Platform 'windows'

        $result | Should -BeFalse
    }

    It 'should return null when no missing tool applies to the current platform' {
        $hint = Get-ProfileMissingToolInstallHint -ToolNames @('fnm') -AvailableCommands @('scoop') -Platform 'windows'

        $hint | Should -Be $null
    }
}

Describe 'Initialize-Environment command discovery integration' {
    BeforeEach {
        $script:ProfileMode = 'Full'
        $script:UseUltraMinimalProfile = $false
        $script:UseMinimalProfile = $false
        $script:profileLoadStartTime = Get-Date
        $script:ProfileModeDecision = [PSCustomObject]@{
            Mode      = 'Full'
            Source    = 'explicit'
            Reason    = 'test'
            Markers   = @('test')
            ElapsedMs = 0
            V2        = $null
        }
        $script:WrittenHostLines = [System.Collections.Generic.List[string]]::new()

        function global:Set-ProfileUtf8Encoding {}
        function global:Test-EnvSwitchEnabled {
            param([string]$Name)
            return $false
        }
        function global:Sync-PathFromBash {
            param([int]$CacheSeconds)
            # 这个集成测试只验证命令探测后的聚合提示，不需要真实同步 Bash PATH。
            return $env:PATH
        }
        function global:Write-ProfileModeDecisionSummary {}
        function global:Write-ProfileModeFallbackGuide {
            param([switch]$VerboseOnly)
        }

        $script:RuntimePlatform = Get-ProfileInstallHintPlatform
        switch ($script:RuntimePlatform) {
            'windows' {
                # Windows 只跟踪 starship / zoxide / sccache 以及三种包管理器，fnm 不参与提示。
                $script:ExpectedTrackedCommandNames = @('starship', 'zoxide', 'sccache', 'scoop', 'winget', 'choco')
                $script:MockCommandDiscoveryResults = @(
                    [PSCustomObject]@{ Name = 'starship'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'zoxide'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'sccache'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'scoop'; Found = $true; Path = 'C:\Users\mudssky\scoop\shims\scoop.cmd' }
                    [PSCustomObject]@{ Name = 'winget'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'choco'; Found = $false; Path = $null }
                )
                $script:ExpectedHintMessage = '未安装以下工具：starship、zoxide。可手动执行下面这行命令一次性安装。'
                $script:ExpectedHintCommand = 'scoop install starship zoxide'
            }
            'macos' {
                # macOS 会把 fnm 也纳入缺失提示，并优先使用 brew 生成单行安装命令。
                $script:ExpectedTrackedCommandNames = @('starship', 'zoxide', 'sccache', 'fnm', 'brew')
                $script:MockCommandDiscoveryResults = @(
                    [PSCustomObject]@{ Name = 'starship'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'zoxide'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'sccache'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'fnm'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'brew'; Found = $true; Path = '/opt/homebrew/bin/brew' }
                )
                $script:ExpectedHintMessage = '未安装以下工具：starship、zoxide、fnm。可手动执行下面这行命令一次性安装。'
                $script:ExpectedHintCommand = 'brew install starship zoxide fnm'
            }
            default {
                # Linux 允许在 brew 不可用时回退到 apt，因此这里显式模拟 apt 可用的常见路径。
                $script:ExpectedTrackedCommandNames = @('starship', 'zoxide', 'sccache', 'fnm', 'brew', 'apt')
                $script:MockCommandDiscoveryResults = @(
                    [PSCustomObject]@{ Name = 'starship'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'zoxide'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'sccache'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'fnm'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'brew'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'apt'; Found = $true; Path = '/usr/bin/apt' }
                )
                $script:ExpectedHintMessage = '未安装以下工具：starship、zoxide、fnm。可手动执行下面这行命令一次性安装。'
                $script:ExpectedHintCommand = 'sudo apt install starship zoxide fnm'
            }
        }

        Mock Write-Host {
            param(
                [Parameter(Position = 0)]
                [object]$Object,
                [System.ConsoleColor]$ForegroundColor,
                [switch]$NoNewline,
                [object]$BackgroundColor,
                [object]$Separator
            )

            if ($null -ne $Object) {
                $script:WrittenHostLines.Add([string]$Object) | Out-Null
            }
        }

        Mock Find-ExecutableCommand {
            return $script:MockCommandDiscoveryResults
        } -ParameterFilter {
            $CacheMisses -and ((@($Name) -join '|') -eq ($script:ExpectedTrackedCommandNames -join '|'))
        }
    }

    AfterEach {
        Remove-Item Function:\Set-ProfileUtf8Encoding -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-EnvSwitchEnabled -ErrorAction SilentlyContinue
        Remove-Item Function:\Sync-PathFromBash -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-ProfileModeDecisionSummary -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-ProfileModeFallbackGuide -ErrorAction SilentlyContinue
    }

    It 'should use Find-ExecutableCommand results to render one aggregated install hint' {
        Initialize-Environment -ScriptRoot (Resolve-Path $script:ProfileRootDir).Path -SkipProxy -SkipAliases

        Should -Invoke Find-ExecutableCommand -Times 1 -Exactly -ParameterFilter {
            $CacheMisses -and ((@($Name) -join '|') -eq ($script:ExpectedTrackedCommandNames -join '|'))
        }
        $script:WrittenHostLines | Should -Contain $script:ExpectedHintMessage
        $script:WrittenHostLines | Should -Contain $script:ExpectedHintCommand
    }
}
