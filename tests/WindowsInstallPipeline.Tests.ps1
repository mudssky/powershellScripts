BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:RepoRoot 'windows/pwsh/WindowsInstall.psm1') -Force
    Import-Module (Join-Path $script:RepoRoot 'windows/bootstrap/WindowsBootstrap.psm1') -Force
    Import-Module (Join-Path $script:RepoRoot 'scripts/pwsh/install/ProfileTools.psm1') -Force
    Import-Module (Join-Path $script:RepoRoot 'psutils') -Force
    $script:AllWindowsCommandsMissing = @{
        winget                = $false
        pwsh                  = $false
        scoop                 = $false
        wsl                   = $false
        AutoHotkey            = $false
        'Get-WinGetSource'    = $false
        'Add-WinGetSource'    = $false
        'Remove-WinGetSource' = $false
    }
    $script:AllWindowsCommandsAvailable = $script:AllWindowsCommandsMissing.Clone()
    foreach ($commandName in @('winget', 'pwsh', 'scoop', 'wsl')) {
        $script:AllWindowsCommandsAvailable[$commandName] = $true
    }

    function Invoke-WindowsTestProcess {
        <#
        .SYNOPSIS
            在独立 pwsh 进程执行脚本，避免被脚本 exit 终止 Pester。

        .PARAMETER ScriptPath
            要执行的 PowerShell 脚本路径。

        .PARAMETER ArgumentList
            传给脚本的参数数组。

        .PARAMETER Environment
            仅对子进程生效的环境变量覆盖。
        .OUTPUTS
            PSCustomObject。包含 ExitCode、Stdout 和 Stderr。
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$ScriptPath,

            [string[]]$ArgumentList,

            [hashtable]$Environment = @{}
        )

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = (Get-Command pwsh -ErrorAction Stop).Source
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($entry in $Environment.GetEnumerator()) {
            $startInfo.Environment[[string]$entry.Key] = [string]$entry.Value
        }
        foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $ScriptPath) + @($ArgumentList)) {
            $startInfo.ArgumentList.Add([string]$argument)
        }
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout; Stderr = $stderr }
    }
}

Describe 'Windows 安装平台模型' {
    It '将 Windows 11 22H2+ x64 分类为 Full' {
        $platform = Get-WindowsInstallEnvironment `
            -WindowsHost $true `
            -ProductName 'Windows 11 Pro' `
            -InstallationType Client `
            -BuildNumber 22631 `
            -Architecture AMD64 `
            -Administrator $false `
            -CommandAvailability $script:AllWindowsCommandsAvailable

        $platform.Edition | Should -Be 'Windows11'
        $platform.Architecture | Should -Be 'amd64'
        $platform.SupportLevel | Should -Be 'Full'
        $platform.SupportsModernWslConfig | Should -BeTrue
    }

    It '将 Windows 10 22H2 x64 分类为 Full 但禁用现代 WSL 配置' {
        $platform = Get-WindowsInstallEnvironment `
            -WindowsHost $true `
            -ProductName 'Windows 10 Pro' `
            -InstallationType Client `
            -BuildNumber 19045 `
            -Architecture x64 `
            -Administrator $false `
            -CommandAvailability $script:AllWindowsCommandsMissing

        $platform.Edition | Should -Be 'Windows10'
        $platform.SupportLevel | Should -Be 'Full'
        $platform.SupportsModernWslConfig | Should -BeFalse
    }

    It '将 ARM64 和 Server 保持在非完整支持路径' {
        (Get-WindowsInstallEnvironment -WindowsHost $true -ProductName 'Windows 11 Pro' -InstallationType Client -BuildNumber 22631 -Architecture arm64 -Administrator $false -CommandAvailability $script:AllWindowsCommandsMissing).SupportLevel |
            Should -Be 'Blocked'
        (Get-WindowsInstallEnvironment -WindowsHost $true -ProductName 'Windows Server 2025' -InstallationType Server -BuildNumber 26100 -Architecture amd64 -Administrator $true -CommandAvailability $script:AllWindowsCommandsMissing).SupportLevel |
            Should -Be 'Partial'
    }

    It '完整 CommandAvailability 不触发真实命令或模块发现' {
        InModuleScope WindowsInstall -Parameters @{ Availability = $script:AllWindowsCommandsMissing } {
            param($Availability)
            Mock Find-ExecutableCommand { throw '不应执行外部命令发现' }
            Mock Get-Module { throw '不应执行 WinGet 模块发现' } -ParameterFilter { $ListAvailable }

            $platform = Get-WindowsInstallEnvironment `
                -WindowsHost $true `
                -ProductName 'Windows 11 Pro' `
                -InstallationType Client `
                -BuildNumber 22631 `
                -Architecture amd64 `
                -Administrator $false `
                -CommandAvailability $Availability

            $platform.HasWinget | Should -BeFalse
            $platform.HasWingetSourceCmdlets | Should -BeFalse
            Should -Invoke Find-ExecutableCommand -Times 0 -Exactly
        }
    }

    It '批量发现 PATH 外部命令并按 WinGet 模块导出判断 cmdlet' {
        InModuleScope WindowsInstall {
            $script:WindowsWinGetSourceAvailability = $null
            Mock Find-ExecutableCommand {
                param([string[]]$Name)
                foreach ($commandName in $Name) {
                    [pscustomobject]@{ Name = $commandName; Found = $commandName -in @('winget', 'pwsh', 'scoop') ; Path = $null }
                }
            }
            Mock Get-Module {
                [pscustomobject]@{
                    Version          = [version]'1.0.0'
                    ExportedCommands = @{
                        'Get-WinGetSource' = $true
                        'Add-WinGetSource' = $true
                    }
                }
            } -ParameterFilter { $ListAvailable -and $Name -eq 'Microsoft.WinGet.Client' }

            $availability = Get-WindowsCommandAvailability
            $secondAvailability = Get-WindowsCommandAvailability

            $availability.winget | Should -BeTrue
            $availability.wsl | Should -BeFalse
            $availability.'Get-WinGetSource' | Should -BeTrue
            $availability.'Remove-WinGetSource' | Should -BeFalse
            $secondAvailability.'Add-WinGetSource' | Should -BeTrue
            Should -Invoke Find-ExecutableCommand -Times 2 -Exactly
            Should -Invoke Get-Module -Times 1 -Exactly -ParameterFilter { $ListAvailable }
        }
    }

    It '不完整 CommandAvailability 明确失败且不回退真实扫描' {
        InModuleScope WindowsInstall {
            Mock Find-ExecutableCommand { throw '不应执行外部命令发现' }
            Mock Get-Module { throw '不应执行 WinGet 模块发现' } -ParameterFilter { $ListAvailable }

            { Get-WindowsCommandAvailability -Override @{ winget = $true } } |
                Should -Throw '*CommandAvailability 缺少必需能力*'
            Should -Invoke Find-ExecutableCommand -Times 0 -Exactly
            Should -Invoke Get-Module -Times 0 -Exactly -ParameterFilter { $ListAvailable }
        }
    }

    It 'PATH 未命中 AutoHotkey 时仍检查已知安装路径' {
        InModuleScope WindowsInstall {
            Mock Find-ExecutableCommand { [pscustomobject]@{ Name = 'AutoHotkey.exe'; Found = $false; Path = $null } }
            Mock Test-Path { $LiteralPath -eq 'C:\Program Files\AutoHotkey\v2\AutoHotkey.exe' }

            Test-WindowsAutoHotkeyAvailable -WindowsHost $true | Should -BeTrue
            Should -Invoke Test-Path -Times 1 -Exactly
        }
    }

    It '按 Failed 优先于 Blocked 汇总退出码' {
        Get-WindowsInstallExitCode @(
            (New-WindowsInstallResult -Name blocked -Status Blocked -ExitCode 10),
            (New-WindowsInstallResult -Name failed -Status Failed -ExitCode 1)
        ) | Should -Be 1
    }
}

Describe 'Windows 声明式 package catalog' {
    BeforeAll {
        $script:WindowsCatalog = Import-WindowsPackageCatalog -Path (Join-Path $script:RepoRoot 'config/install/windows-packages.psd1')
        $script:AppsConfig = (Resolve-ConfigSources -Sources @(
                @{ Type = 'JsonFile'; Name = 'Apps'; Path = (Join-Path $script:RepoRoot 'profile/installer/apps-config.json') }
            ) -BasePath $script:RepoRoot -ErrorOnMissing).Values
        $script:PackageManagers = ConvertTo-ConfigHashtable -InputObject $script:AppsConfig.packageManagers
    }

    It 'Core 只包含确认的 13 个 Scoop CLI' {
        $core = @(Select-PackageManagerApps -Apps @($script:PackageManagers.scoop) -TargetOS Windows -RequiredTag @('core', 'cli'))
        @($core.name) | Should -Be @('delta', 'zoxide', 'fnm', 'starship', 'fzf', 'ripgrep', 'jq', 'uv', 'bat', 'fd', 'eza', 'carapace-bin', 'atuin')
        @($core.name) | Should -Not -Contain 'tldr'
        @($core | Where-Object name -eq 'carapace-bin').bucket | Should -Be @('extras')
    }

    It 'Full terminal extras 不包含 GUI 条目' {
        $extras = @(Select-PackageManagerApps -Apps @($script:PackageManagers.scoop) -TargetOS Windows -RequiredTag @('cli', 'terminal-extras'))
        $extras.Count | Should -BeGreaterThan 0
        @($extras.name) | Should -Not -Contain 'neovide'
        @($extras.tag | ForEach-Object { $_ }) | Should -Not -Contain 'gui'
    }

    It 'AutoHotkey 是唯一默认 Full 平台 winget 条目' {
        $platformApps = @(Select-PackageManagerApps -Apps @($script:PackageManagers.winget) -TargetOS Windows -RequiredTag @('full', 'platform'))
        @($platformApps.name) | Should -Be @('autohotkey')
    }

    It 'Windows package catalog schema 和字体清单稳定' {
        $script:WindowsCatalog.SchemaVersion | Should -Be 1
        @($script:WindowsCatalog.Scoop.Fonts) | Should -Be @('JetBrainsMono-NF', 'FiraCode-NF')
    }

    It '识别 Scoop 新版对象输出和旧版文本输出中的名称' {
        Test-WindowsScoopListContains `
            -InputObject @([pscustomobject]@{ Name = 'nerd-fonts'; Source = 'fixture' }) `
            -Name nerd-fonts | Should -BeTrue
        Test-WindowsScoopListContains `
            -InputObject @('main https://example.invalid/main', 'nerd-fonts https://example.invalid/fonts') `
            -Name nerd-fonts | Should -BeTrue
        Test-WindowsScoopListContains `
            -InputObject @([pscustomobject]@{ Name = 'main' }) `
            -Name nerd-fonts | Should -BeFalse
    }

    It 'Scoop bucket helper 支持预览与新版对象幂等检查' {
        $preview = Initialize-WindowsScoopBucket -Bucket extras -Preview
        $preview.Status | Should -Be 'Preview'
        $preview.Message | Should -Be 'scoop bucket add extras'

        function global:scoop {
            param([Parameter(ValueFromRemainingArguments = $true)][object[]]$RemainingArgs)
            $global:LASTEXITCODE = 0
            [pscustomobject]@{ Name = 'extras'; Source = 'fixture' }
        }
        try {
            $existing = Initialize-WindowsScoopBucket -Bucket extras
            $existing.Status | Should -Be 'AlreadyPresent'
            $existing.ExitCode | Should -Be 0
        }
        finally {
            Remove-Item Function:\scoop -ErrorAction SilentlyContinue
        }
    }

    It '必需 bucket 添加失败时停止应用安装' {
        InModuleScope WindowsInstall -Parameters @{ RepositoryRoot = $script:RepoRoot } {
            param($RepositoryRoot)
            Mock Initialize-WindowsScoopBucket {
                New-WindowsInstallResult -Name 'bucket:extras' -Status Failed -Message 'fixture failure' -ExitCode 1
            }
            Mock Install-PackageManagerApps { throw 'bucket 失败后不应进入应用安装' }

            $result = @(Invoke-WindowsScoopCatalogInstall `
                    -RepoRoot $RepositoryRoot `
                    -RequiredTag @('core', 'cli') `
                    -Preview)

            $result.Count | Should -Be 1
            $result[0].Status | Should -Be 'Failed'
            Should -Invoke Install-PackageManagerApps -Times 0 -Exactly
        }
    }

    It '应用清单只允许 Scoop 条目声明合法 bucket' {
        $nonScoop = @{ packageManagers = @{ homebrew = @(@{ name = 'bad'; bucket = 'extras' }) } }
        $invalidName = @{ packageManagers = @{ scoop = @(@{ name = 'bad'; bucket = '../extras' }) } }

        { Test-PackageManagerAppCatalog -ConfigObject $nonScoop } | Should -Throw '*仅 Scoop 条目允许声明 bucket*'
        { Test-PackageManagerAppCatalog -ConfigObject $invalidName } | Should -Throw '*bucket 无效*'
    }

    It '只允许普通令牌或绑定真实用户 profile 的自动化用户阶段' {
        Test-WindowsUserStageContext -Administrator $false -AutomationSession $false -UserProfile '' |
            Should -BeTrue
        Test-WindowsUserStageContext -Administrator $true -AutomationSession $true -UserProfile 'C:\Users\fixture' |
            Should -BeTrue
        Test-WindowsUserStageContext -Administrator $true -AutomationSession $false -UserProfile 'C:\Users\fixture' |
            Should -BeFalse
        Test-WindowsUserStageContext -Administrator $true -AutomationSession $true -UserProfile 'C:\Windows\System32\config\systemprofile' |
            Should -BeFalse
    }

    It 'Profile Tools 原生命令输出不会污染结构化返回值' {
        InModuleScope ProfileTools {
            function Invoke-ProfileToolFixture {
                Write-Output 'fixture-warning'
                $global:LASTEXITCODE = 0
            }

            $result = @(Invoke-ProfileToolNativeCommand `
                    -Name fixture `
                    -FilePath Invoke-ProfileToolFixture `
                    -ArgumentList @('install', '--lts'))

            $result.Count | Should -Be 1
            $result[0].Status | Should -Be 'Succeeded'
            $result[0].Message | Should -Be 'fixture-warning'
        }
    }

    It 'Profile Tools 使用 fnm JSON 初始化非交互 Node 环境' {
        InModuleScope ProfileTools {
            function Invoke-FnmEnvironmentFixture {
                Write-Output '{"FNM_MULTISHELL_PATH":"fnm-multishell","FNM_DIR":"fnm-root"}'
                $global:LASTEXITCODE = 0
            }

            $originalPath = [System.Environment]::GetEnvironmentVariable('PATH', 'Process')
            $originalMultishellPath = [System.Environment]::GetEnvironmentVariable('FNM_MULTISHELL_PATH', 'Process')
            $originalFnmDir = [System.Environment]::GetEnvironmentVariable('FNM_DIR', 'Process')
            try {
                $result = Initialize-ProfileToolFnmEnvironment `
                    -FilePath Invoke-FnmEnvironmentFixture `
                    -Platform Windows

                $result.Status | Should -Be 'Succeeded'
                [System.Environment]::GetEnvironmentVariable('FNM_MULTISHELL_PATH', 'Process') |
                    Should -Be 'fnm-multishell'
                ([System.Environment]::GetEnvironmentVariable('PATH', 'Process') -split [System.IO.Path]::PathSeparator)[0] |
                    Should -Be 'fnm-multishell'
            }
            finally {
                [System.Environment]::SetEnvironmentVariable('PATH', $originalPath, 'Process')
                [System.Environment]::SetEnvironmentVariable('FNM_MULTISHELL_PATH', $originalMultishellPath, 'Process')
                [System.Environment]::SetEnvironmentVariable('FNM_DIR', $originalFnmDir, 'Process')
            }
        }
    }

    It 'Profile Tools 拒绝 fnm JSON 写入非 FNM 环境变量' {
        InModuleScope ProfileTools {
            function Invoke-UnsafeFnmEnvironmentFixture {
                Write-Output '{"FNM_MULTISHELL_PATH":"C:\\fnm\\multishell","PATH":"C:\\unsafe"}'
                $global:LASTEXITCODE = 0
            }

            $result = Initialize-ProfileToolFnmEnvironment `
                -FilePath Invoke-UnsafeFnmEnvironmentFixture `
                -Platform Windows

            $result.Status | Should -Be 'Failed'
            $result.Message | Should -Match '不允许的环境变量: PATH'
        }
    }

    It 'Windows 验证 JSON 不包含 Scoop Information stream' {
        $shimRoot = Join-Path $TestDrive 'scoop-shim'
        New-Item -ItemType Directory -Path $shimRoot -Force | Out-Null
        if ($IsWindows) {
            $shimPath = Join-Path $shimRoot 'scoop.cmd'
            Set-Content -LiteralPath $shimPath -Encoding ascii -Value @(
                '@echo off',
                'echo Installed apps:',
                'echo JetBrainsMono-NF',
                'echo FiraCode-NF'
            )
        }
        else {
            $shimPath = Join-Path $shimRoot 'scoop'
            Set-Content -LiteralPath $shimPath -Encoding utf8NoBOM -Value @(
                '#!/usr/bin/env sh',
                'echo "Installed apps:"',
                'echo "JetBrainsMono-NF"',
                'echo "FiraCode-NF"'
            )
            chmod +x $shimPath
        }

        $result = Invoke-WindowsTestProcess `
            -ScriptPath (Join-Path $script:RepoRoot 'windows/pwsh/Test-InstallState.ps1') `
            -ArgumentList @('-Step', 'fonts', '-OutputFormat', 'Json') `
            -Environment @{ PATH = $shimRoot + [System.IO.Path]::PathSeparator + $env:PATH }
        $document = $result.Stdout | ConvertFrom-Json

        $result.ExitCode | Should -Be 0 -Because $result.Stderr
        @($document).Count | Should -Be 2
        @($document.Status | Select-Object -Unique) | Should -Be @('Pass')
    }
}

Describe 'Windows WSL 配置合同' {
    BeforeAll {
        $script:WindowsCatalog = Import-WindowsPackageCatalog -Path (Join-Path $script:RepoRoot 'config/install/windows-packages.psd1')
    }

    It 'Windows 10 配置不包含 mirrored networking' {
        $content = ConvertTo-WindowsWslConfigContent -Catalog $script:WindowsCatalog -BuildNumber 19045
        $content | Should -Match 'memory=16GB'
        $content | Should -Not -Match 'networkingMode=mirrored'
        $content | Should -Not -Match '\[experimental\]'
    }

    It 'Windows 11 22H2 配置与仓库模板一致' {
        $content = ConvertTo-WindowsWslConfigContent -Catalog $script:WindowsCatalog -BuildNumber 22621
        $template = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'windows/wsl/.wslconfig') -Raw
        $content | Should -BeExactly $template
    }

    It '配置相同不备份，变化时先创建可读时间戳备份' {
        $target = Join-Path $TestDrive '.wslconfig'
        $first = Set-WindowsManagedContent -Path $target -Content "[wsl2]`nmemory=4GB`n"
        $second = Set-WindowsManagedContent -Path $target -Content "[wsl2]`nmemory=4GB`n"
        $third = Set-WindowsManagedContent -Path $target -Content "[wsl2]`nmemory=8GB`n"

        $first.Status | Should -Be 'RestartRequired'
        $second.Status | Should -Be 'AlreadyPresent'
        $third.Status | Should -Be 'RestartRequired'
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '.wslconfig.*.bak' -Force).Count | Should -Be 1
        (Get-Content -LiteralPath $target -Raw) | Should -BeExactly "[wsl2]`nmemory=8GB`n"
    }
}

Describe 'Windows Stage 0 与叶子入口' {
    It '远程 bootstrap manifest 覆盖最小资产且 hash 全部匹配' {
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'windows/bootstrap/bootstrap-manifest.psd1')
        @($manifest.Assets.Path) | Should -Be @(
            'windows/bootstrap/WindowsBootstrap.psm1',
            'windows/bootstrap/Invoke-WindowsElevatedPlan.ps1',
            'scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1',
            'config/network/package-sources.bootstrap.env',
            'config/install/windows-packages.psd1'
        )
        foreach ($asset in @($manifest.Assets)) {
            $actualHash = (Get-FileHash -LiteralPath (Join-Path $script:RepoRoot $asset.Path) -Algorithm SHA256).Hash
            $actualHash | Should -Be ([string]$asset.Sha256).ToUpperInvariant()
        }
    }

    It '所有 Windows PowerShell 文件均可由当前 parser 解析' {
        $errors = [System.Collections.Generic.List[object]]::new()
        foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'windows') -Recurse -Include '*.ps1', '*.psm1')) {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
            foreach ($parseError in @($parseErrors)) {
                $errors.Add($parseError)
            }
        }
        $errors.Count | Should -Be 0
    }

    It '提升 executor 锁定 package ID、资产路径和二次签名验证' {
        $executor = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'windows/bootstrap/Invoke-WindowsElevatedPlan.ps1') -Raw
        $executor | Should -Match ([regex]::Escape("Git        = 'Git.Git'"))
        $executor | Should -Match ([regex]::Escape("PowerShell = 'Microsoft.PowerShell'"))
        $executor | Should -Match ([regex]::Escape("AutoHotkey = 'AutoHotkey.AutoHotkey'"))
        $executor | Should -Match 'Get-AuthenticodeSignature'
        $executor | Should -Match '拒绝资产树之外的 source helper'
    }

    It '根步骤注册表启用 Windows 03/05/06/07/08/09/99 且保持 04/10/11 unsupported' {
        Import-Module (Join-Path $script:RepoRoot 'scripts/pwsh/install/InstallOrchestrator.psm1') -Force
        $registry = Import-InstallStepRegistry -Path (Join-Path $script:RepoRoot 'config/install/steps.psd1')
        $catalog = @(Get-InstallStepCatalog -Registry $registry -Platform windows)
        @($catalog | Where-Object Supported | ForEach-Object Number) | Should -Be @('03', '05', '06', '07', '08', '09', '99')
        @($catalog | Where-Object { -not $_.Supported } | ForEach-Object Number) | Should -Be @('04', '10', '11')
    }
}
