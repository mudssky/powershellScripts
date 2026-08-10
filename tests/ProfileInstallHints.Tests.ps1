Set-StrictMode -Version Latest

BeforeAll {
    $script:ProfileRootDir = Join-Path $PSScriptRoot '..' 'profile'
    Import-Module (Join-Path $PSScriptRoot '..' 'psutils/modules/commandDiscovery.psm1') -Force
    . (Join-Path $script:ProfileRootDir 'core/platform.ps1')
    . (Join-Path $script:ProfileRootDir 'core/encoding.ps1')
    . (Join-Path $script:ProfileRootDir 'core/bootstrap.ps1')
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
        $script:ProfilePlatformContext = Get-ProfilePlatformContext
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
        $script:OriginalPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')

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
                # Windows 跟踪两个 Shell 工具，但它们不进入 Profile 缺失安装提示。
                $script:ExpectedTrackedCommandNames = @('starship', 'zoxide', 'sccache', 'carapace', 'atuin', 'scoop', 'winget', 'choco')
                $script:MockCommandDiscoveryResults = @(
                    [PSCustomObject]@{ Name = 'starship'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'zoxide'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'sccache'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'carapace'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'atuin'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'scoop'; Found = $true; Path = 'C:\Users\mudssky\scoop\shims\scoop.cmd' }
                    [PSCustomObject]@{ Name = 'winget'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'choco'; Found = $false; Path = $null }
                )
                $script:ExpectedHintMessage = '未安装以下工具：starship、zoxide。可手动执行下面这行命令一次性安装。'
                $script:ExpectedHintCommand = 'scoop install starship zoxide'
            }
            'macos' {
                # macOS 跟踪两个 Shell 工具，但聚合提示只保留既有显式提示定义。
                $script:ExpectedTrackedCommandNames = @('starship', 'zoxide', 'sccache', 'fnm', 'carapace', 'atuin', 'brew')
                $script:MockCommandDiscoveryResults = @(
                    [PSCustomObject]@{ Name = 'starship'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'zoxide'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'sccache'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'fnm'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'carapace'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'atuin'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'brew'; Found = $true; Path = '/opt/homebrew/bin/brew' }
                )
                $script:ExpectedHintMessage = '未安装以下工具：starship、zoxide、fnm。可手动执行下面这行命令一次性安装。'
                $script:ExpectedHintCommand = 'brew install starship zoxide fnm'
            }
            default {
                # Linux 允许 brew 不可用时回退 apt；Shell 工具仍不进入 Profile 提示定义。
                $script:ExpectedTrackedCommandNames = @('starship', 'zoxide', 'sccache', 'fnm', 'carapace', 'atuin', 'brew', 'apt')
                $script:MockCommandDiscoveryResults = @(
                    [PSCustomObject]@{ Name = 'starship'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'zoxide'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'sccache'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'fnm'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'carapace'; Found = $false; Path = $null }
                    [PSCustomObject]@{ Name = 'atuin'; Found = $false; Path = $null }
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
        [Environment]::SetEnvironmentVariable('PATH', $script:OriginalPath, 'Process')
    }

    It 'should use Find-ExecutableCommand results to render one aggregated install hint' {
        Initialize-Environment -ScriptRoot (Resolve-Path $script:ProfileRootDir).Path -PlatformContext $script:ProfilePlatformContext -SkipProxy -SkipAliases

        Should -Invoke Find-ExecutableCommand -Times 1 -Exactly -ParameterFilter {
            $CacheMisses -and ((@($Name) -join '|') -eq ($script:ExpectedTrackedCommandNames -join '|'))
        }
        $script:WrittenHostLines | Should -Contain $script:ExpectedHintMessage
        $script:WrittenHostLines | Should -Contain $script:ExpectedHintCommand
    }

    It 'Minimal mode should skip command discovery and install hints' {
        $script:ProfileMode = 'Minimal'
        $script:UseMinimalProfile = $true

        Initialize-Environment `
            -ScriptRoot (Resolve-Path $script:ProfileRootDir).Path `
            -ProfileMode Minimal `
            -PlatformContext $script:ProfilePlatformContext `
            -SkipProxy

        Should -Invoke Find-ExecutableCommand -Times 0 -Exactly
        $script:WrittenHostLines.Count | Should -Be 0
    }
}

Describe 'Initialize-Environment Shell 工具初始化' {
    BeforeEach {
        $script:ProfileMode = 'Full'
        $script:UseUltraMinimalProfile = $false
        $script:UseMinimalProfile = $false
        $script:ProfilePlatformContext = Get-ProfilePlatformContext -Platform Windows
        $script:profileLoadStartTime = Get-Date
        $script:ProfileModeDecision = [PSCustomObject]@{
            Mode = 'Full'; Source = 'explicit'; Reason = 'test'; Markers = @('test'); ElapsedMs = 0; V2 = $null
        }
        $script:ToolCacheRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
        $Global:CarapaceFixtureCalls = [System.Collections.Generic.List[string]]::new()
        $Global:AtuinFixtureCalls = [System.Collections.Generic.List[string]]::new()
        $Global:CarapaceFixtureExitCode = 0
        $Global:__CarapaceInitialized = $false
        $Global:__AtuinInitialized = $false
        $Global:CarapaceFixtureLoaded = $false
        $Global:AtuinFixtureLoaded = $false

        function global:Set-ProfileUtf8Encoding {}
        function global:Test-EnvSwitchEnabled {
            param([string]$Name)
            return $false
        }
        function global:Write-ProfileModeDecisionSummary {}
        function global:Write-ProfileModeFallbackGuide {
            param([switch]$VerboseOnly)
        }
        function global:Invoke-WithFileCache {
            <#
            .SYNOPSIS
                在测试目录模拟文件缓存。
            .PARAMETER Key
                缓存键。
            .PARAMETER MaxAge
                兼容生产函数签名的最大年龄。
            .PARAMETER Generator
                首次缺失时生成脚本内容的回调。
            .PARAMETER BaseDir
                兼容生产函数签名的缓存目录。
            .OUTPUTS
                System.String。返回生成的脚本路径。
            #>
            param(
                [string]$Key,
                [TimeSpan]$MaxAge,
                [ScriptBlock]$Generator,
                [string]$BaseDir
            )
            $path = Join-Path $script:ToolCacheRoot "$Key.ps1"
            if (-not (Test-Path -LiteralPath $path)) {
                New-Item -ItemType Directory -Path $script:ToolCacheRoot -Force | Out-Null
                (& $Generator) | Set-Content -LiteralPath $path -Encoding utf8NoBOM
            }
            return $path
        }
        function global:carapace {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$RemainingArgs)
            $Global:CarapaceFixtureCalls.Add(($RemainingArgs -join ' ')) | Out-Null
            $global:LASTEXITCODE = $Global:CarapaceFixtureExitCode
            if ($Global:CarapaceFixtureExitCode -eq 0) {
                '$Global:CarapaceFixtureLoaded = $true'
            }
        }
        function global:atuin {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$RemainingArgs)
            $Global:AtuinFixtureCalls.Add(($RemainingArgs -join ' ')) | Out-Null
            $global:LASTEXITCODE = 0
            '$Global:AtuinFixtureLoaded = $true'
        }

        Mock Find-ExecutableCommand {
            @(
                [PSCustomObject]@{ Name = 'starship'; Found = $false; Path = $null }
                [PSCustomObject]@{ Name = 'zoxide'; Found = $false; Path = $null }
                [PSCustomObject]@{ Name = 'sccache'; Found = $false; Path = $null }
                [PSCustomObject]@{ Name = 'carapace'; Found = $true; Path = 'fixture:carapace' }
                [PSCustomObject]@{ Name = 'atuin'; Found = $true; Path = 'fixture:atuin' }
                [PSCustomObject]@{ Name = 'scoop'; Found = $false; Path = $null }
                [PSCustomObject]@{ Name = 'winget'; Found = $false; Path = $null }
                [PSCustomObject]@{ Name = 'choco'; Found = $false; Path = $null }
            )
        }
    }

    AfterEach {
        foreach ($name in @(
                'Set-ProfileUtf8Encoding', 'Test-EnvSwitchEnabled',
                'Write-ProfileModeDecisionSummary', 'Write-ProfileModeFallbackGuide',
                'Invoke-WithFileCache', 'carapace', 'atuin')) {
            Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
        }
        foreach ($name in @(
                'CarapaceFixtureCalls', 'AtuinFixtureCalls', 'CarapaceFixtureExitCode',
                '__CarapaceInitialized', '__AtuinInitialized',
                'CarapaceFixtureLoaded', 'AtuinFixtureLoaded')) {
            Remove-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'Full 模式缓存并只初始化 Carapace 与 Atuin 一次' {
        $parameters = @{
            ScriptRoot = (Resolve-Path $script:ProfileRootDir).Path
            PlatformContext = $script:ProfilePlatformContext
            SkipProxy = $true
            SkipAliases = $true
            SkipStarship = $true
            SkipZoxide = $true
        }

        Initialize-Environment @parameters
        Initialize-Environment @parameters

        @($Global:CarapaceFixtureCalls) | Should -Be @('_carapace')
        @($Global:AtuinFixtureCalls) | Should -Be @('init powershell --disable-up-arrow')
        $Global:CarapaceFixtureLoaded | Should -BeTrue
        $Global:AtuinFixtureLoaded | Should -BeTrue
        $Global:__CarapaceInitialized | Should -BeTrue
        $Global:__AtuinInitialized | Should -BeTrue
    }

    It 'Carapace 初始化失败时仍继续初始化 Atuin' {
        $Global:CarapaceFixtureExitCode = 1

        Initialize-Environment `
            -ScriptRoot (Resolve-Path $script:ProfileRootDir).Path `
            -PlatformContext $script:ProfilePlatformContext `
            -SkipProxy -SkipAliases -SkipStarship -SkipZoxide

        $Global:__CarapaceInitialized | Should -BeFalse
        $Global:__AtuinInitialized | Should -BeTrue
        $Global:AtuinFixtureLoaded | Should -BeTrue
    }
}
