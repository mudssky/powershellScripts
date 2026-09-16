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

    It 'Core 只包含确认的 14 个 Scoop CLI' {
        $core = @(Select-PackageManagerApps -Apps @($script:PackageManagers.scoop) -TargetOS Windows -RequiredTag @('core', 'cli'))
        @($core.name) | Should -Be @('delta', 'zoxide', 'fnm', 'go', 'starship', 'fzf', 'ripgrep', 'jq', 'uv', 'bat', 'fd', 'eza', 'carapace-bin', 'atuin')
        ($core | Where-Object name -eq 'go').command | Should -Be 'scoop install go'
        @($core.name) | Should -Not -Contain 'tldr'
        @($core | Where-Object name -eq 'carapace-bin').bucket | Should -Be @('extras')
    }

    It 'Full terminal extras 不包含 GUI 条目' {
        $extras = @(Select-PackageManagerApps -Apps @($script:PackageManagers.scoop) -TargetOS Windows -RequiredTag @('cli', 'terminal-extras'))
        $extras.Count | Should -BeGreaterThan 0
        @($extras.name) | Should -Not -Contain 'neovide'
        @($extras.tag | ForEach-Object { $_ }) | Should -Not -Contain 'gui'
    }

    It '默认 Full 平台 winget 条目为 AutoHotkey 与 SSHCopyID' {
        $platformApps = @(Select-PackageManagerApps -Apps @($script:PackageManagers.winget) -TargetOS Windows -RequiredTag @('full', 'platform'))
        @($platformApps.name) | Should -Be @('autohotkey', 'sshcopyid')
    }

    It '应用清单通过统一 catalog 校验且 SSHCopyID 满足 winget 条目契约' {
        { Test-PackageManagerAppCatalog -ConfigObject $script:AppsConfig } | Should -Not -Throw
        $sshCopyId = @($script:PackageManagers.winget | Where-Object { $_.name -eq 'sshcopyid' })
        $sshCopyId.Count | Should -Be 1
        $sshCopyId[0].cliName | Should -Be 'ssh-copy-id'
        $sshCopyId[0].command | Should -Be 'winget install --id axeprpr.SSHCopyID -e --accept-package-agreements --accept-source-agreements'
        @($sshCopyId[0].supportOs) | Should -Be @('Windows')
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

    It 'winget 包装 Preview 按 full/platform 产出安装计划并透传 WhatIf' {
        $result = @(Invoke-WindowsWingetCatalogInstall `
                -RepoRoot $script:RepoRoot `
                -RequiredTag @('full', 'platform') `
                -Preview)

        $sshCopyId = @($result | Where-Object Name -eq 'sshcopyid')
        $sshCopyId.Count | Should -Be 1
        $sshCopyId[0].PackageManager | Should -Be 'winget'
        $sshCopyId[0].Command | Should -Be 'winget install --id axeprpr.SSHCopyID -e --accept-package-agreements --accept-source-agreements'
        $autoHotkey = @($result | Where-Object Name -eq 'autohotkey')
        $autoHotkey[0].Command | Should -Be 'winget install --id AutoHotkey.AutoHotkey --exact'

        # skipInstall 且无标签的 eartrumpet 不进入统一安装结果。
        @($result | Where-Object Name -eq 'eartrumpet').Count | Should -Be 0

        # Preview 透传后最多产出 Preview/AlreadyPresent，不产生真实安装或失败。
        @($result | Where-Object { $_.Status -in @('Installed', 'Failed', 'Blocked') }).Count | Should -Be 0
        @($result | Where-Object Name -in @('autohotkey', 'sshcopyid') | Where-Object Status -notin @('Preview', 'AlreadyPresent')).Count | Should -Be 0
    }

    It 'winget 包装按 RequiredTag 过滤且无匹配条目时返回 Failed' {
        $result = @(Invoke-WindowsWingetCatalogInstall `
                -RepoRoot $script:RepoRoot `
                -RequiredTag @('core', 'cli') `
                -Preview)

        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'winget'
        $result[0].Status | Should -Be 'Failed'
        $result[0].ExitCode | Should -Be 1
        $result[0].Message | Should -Be '没有匹配标签: core, cli'
    }

    It '缺少 winget 时真实执行返回 Blocked/10' -Skip:$IsWindows {
        $result = @(Invoke-WindowsWingetCatalogInstall `
                -RepoRoot $script:RepoRoot `
                -RequiredTag @('full', 'platform'))

        $result.Count | Should -Be 1
        $result[0].Status | Should -Be 'Blocked'
        $result[0].ExitCode | Should -Be 10
        $result[0].Message | Should -Match 'winget'
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
        $script:WslConfigFixture = @{
            Wsl = @{
                Settings = @(
                    @{ Section = 'wsl2'; Name = 'baseOption'; Value = 'base'; MinimumBuild = 19045 }
                    @{ Section = 'experimental'; Name = 'experimentalOption'; Value = 'enabled'; MinimumBuild = 22621 }
                    @{ Section = 'wsl2'; Name = 'modernOption'; Value = 'modern'; MinimumBuild = 22621 }
                    @{ Section = 'wsl2'; Name = 'futureOption'; Value = 'future'; MinimumBuild = 26000 }
                )
            }
        }
    }

    It '按 Windows build 过滤不受支持的设置和空 section' {
        $content = ConvertTo-WindowsWslConfigContent -Catalog $script:WslConfigFixture -BuildNumber 19045

        $content | Should -BeExactly "[wsl2]`nbaseOption=base`n"
    }

    It '按 section 首次出现顺序和 section 内声明顺序生成配置' {
        $content = ConvertTo-WindowsWslConfigContent -Catalog $script:WslConfigFixture -BuildNumber 22621

        $content | Should -BeExactly "[wsl2]`nbaseOption=base`nmodernOption=modern`n`n[experimental]`nexperimentalOption=enabled`n"
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

Describe 'Windows 步骤 10 login-items 接线' {
    It '叶子 -WhatIf 输出委托计划且零落盘退出 0' {
        $result = Invoke-WindowsTestProcess `
            -ScriptPath (Join-Path $script:RepoRoot 'windows/10deployWslAutostart.ps1') `
            -ArgumentList @('-WhatIf')

        $result.ExitCode | Should -Be 0 -Because $result.Stderr
        $result.Stdout | Should -Match '\[Preview\]'
        $result.Stdout | Should -Match 'Initialize-WslSshAccess'
        $result.Stdout | Should -Match '-ListenPort 2222'
        $result.Stdout | Should -Match '-GuestPort 2223'

        # 无 USER/USERNAME 环境同样零落盘退出 0，以占位符呈现并附注意项。
        $anonymousResult = Invoke-WindowsTestProcess `
            -ScriptPath (Join-Path $script:RepoRoot 'windows/10deployWslAutostart.ps1') `
            -ArgumentList @('-WhatIf') `
            -Environment @{ USER = ''; USERNAME = '' }
        $anonymousResult.ExitCode | Should -Be 0 -Because $anonymousResult.Stderr
        $anonymousResult.Stdout | Should -Match '\(当前用户\)'

        # 显式公钥路径按原值回显，与真实透传参数一致。
        $keyPath = Join-Path $TestDrive 'controller.pub'
        Set-Content -LiteralPath $keyPath -Value 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE0U+v3dbT3bF7l6b3Vq7Z1W8pQ0jY8+YqjQ2YyK0fX fixture' -NoNewline
        $explicitResult = Invoke-WindowsTestProcess `
            -ScriptPath (Join-Path $script:RepoRoot 'windows/10deployWslAutostart.ps1') `
            -ArgumentList @('-WhatIf', '-AuthorizedKeyPath', $keyPath)
        $explicitResult.ExitCode | Should -Be 0 -Because $explicitResult.Stderr
        $explicitResult.Stdout | Should -Match ([regex]::Escape($keyPath))
    }

    It 'WSL 缺席时叶子真实执行返回 Blocked/10 且不做任何修改' -Skip:$IsWindows {
        # 顺序契约：WSL/build 前置不足必须优先于用户参数校验返回 Blocked/10（否则无 USER 容器误报 exit 2）。
        $leafContent = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'windows/10deployWslAutostart.ps1') -Raw
        $leafContent.IndexOf('前置条件不足，未做任何修改') |
            Should -BeLessThan $leafContent.IndexOf('无法解析当前 Windows/WSL 用户')

        $result = Invoke-WindowsTestProcess `
            -ScriptPath (Join-Path $script:RepoRoot 'windows/10deployWslAutostart.ps1') `
            -ArgumentList @()

        $result.ExitCode | Should -Be 10
        $result.Stdout | Should -Match '\[Blocked\]'
        $result.Stderr | Should -Not -BeNullOrEmpty
    }

    It 'runtime config 缺失时报告未配置' {
        InModuleScope WindowsInstall -Parameters @{ TestRoot = $TestDrive } {
            param($TestRoot)
            $emptyRoot = Join-Path $TestRoot 'wsl-ssh-empty'
            New-Item -ItemType Directory -Path $emptyRoot -Force | Out-Null

            $state = Get-WindowsWslSshLoginItemsState -RuntimeRoot $emptyRoot
            $state.Configured | Should -BeFalse
            @($state.Items).Count | Should -Be 0

            $state = Get-WindowsWslSshLoginItemsState -RuntimeRoot (Join-Path $TestRoot 'wsl-ssh-missing')
            $state.Configured | Should -BeFalse
        }
    }

    It '计划任务 Trigger/Principal 匹配与监听判定复用机制层资源命名' {
        InModuleScope WindowsInstall -Parameters @{ TestRoot = $TestDrive } {
            param($TestRoot)
            $runtimeRoot = Join-Path $TestRoot 'wsl-ssh'
            New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $runtimeRoot 'ubuntu-24-04.json') `
                -Value '{"schemaVersion":1,"distribution":"Ubuntu-24.04","listenAddress":"0.0.0.0","listenPort":2222,"guestPort":2223}' `
                -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $runtimeRoot 'ubuntu-24-04.status.json') `
                -Value '{"wslIPv4":"100.100.1.1"}' -Encoding utf8NoBOM

            # Linux CI 没有 ScheduledTasks/NetTCPIP 模块，先定义同名空实现供 Pester 拦截。
            function Get-ScheduledTask { }
            function Get-NetTCPConnection { }
            Mock Get-ScheduledTask {
                [pscustomobject]@{
                    Principal = [pscustomobject]@{ LogonType = 'S4U'; RunLevel = 'Highest'; UserId = 'fixture-user' }
                    Triggers  = @([pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskBootTrigger' } })
                }
            }
            Mock Get-NetTCPConnection {
                [pscustomobject]@{ LocalAddress = '0.0.0.0'; LocalPort = 2222; State = 'Listen' }
            }

            $state = Get-WindowsWslSshLoginItemsState -RuntimeRoot $runtimeRoot
            $state.Configured | Should -BeTrue
            @($state.Items).Count | Should -Be 1
            $item = @($state.Items)[0]
            $item.Distribution | Should -Be 'Ubuntu-24.04'
            $item.TaskName | Should -Be 'powershellScripts-WSL-SSH-ubuntu-24-04'
            $item.TaskExists | Should -BeTrue
            $item.TaskMatches | Should -BeTrue
            $item.ListenerListening | Should -BeTrue
        }
    }

    It 'Principal 非 S4U 或监听缺失时判定为不匹配' {
        InModuleScope WindowsInstall -Parameters @{ TestRoot = $TestDrive } {
            param($TestRoot)
            $runtimeRoot = Join-Path $TestRoot 'wsl-ssh-mismatch'
            New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $runtimeRoot 'ubuntu-24-04.json') `
                -Value '{"schemaVersion":1,"distribution":"Ubuntu-24.04","listenAddress":"0.0.0.0","listenPort":2222,"guestPort":2223}' `
                -Encoding utf8NoBOM

            # Linux CI 没有 ScheduledTasks/NetTCPIP 模块，先定义同名空实现供 Pester 拦截。
            function Get-ScheduledTask { }
            function Get-NetTCPConnection { }
            Mock Get-ScheduledTask {
                [pscustomobject]@{
                    Principal = [pscustomobject]@{ LogonType = 'Interactive'; RunLevel = 'Limited'; UserId = 'fixture-user' }
                    Triggers  = @([pscustomobject]@{ CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskLogonTrigger' } })
                }
            }
            Mock Get-NetTCPConnection { $null }

            $state = Get-WindowsWslSshLoginItemsState -RuntimeRoot $runtimeRoot
            $item = @($state.Items)[0]
            $item.TaskExists | Should -BeTrue
            $item.TaskMatches | Should -BeFalse
            $item.ListenerListening | Should -BeFalse
        }
    }

    It '99 对 login-items 输出单文档 JSON 且未配置场景不失败' {
        $result = Invoke-WindowsTestProcess `
            -ScriptPath (Join-Path $script:RepoRoot 'windows/99verifyInstall.ps1') `
            -ArgumentList @('-Preset', 'Full', '-Step', 'login-items', '-OutputFormat', 'Json')

        $result.ExitCode | Should -Be 0 -Because $result.Stderr
        $document = $result.Stdout | ConvertFrom-Json
        $document.SchemaVersion | Should -Be 1
        $loginResults = @($document.Results | Where-Object Step -eq 'login-items')
        $loginResults.Count | Should -BeGreaterOrEqual 2
        @($loginResults.Name) | Should -Contain 'sshcopyid'
        $sshCopyIdResult = @($loginResults | Where-Object Name -eq 'sshcopyid')[0]
        $sshCopyIdResult.Status | Should -BeIn @('Pass', 'Warn')
        $wslTaskResults = @($loginResults | Where-Object { $_.Name -like 'wsl-ssh-task*' })
        $wslTaskResults.Count | Should -Be 1
        $wslTaskResults[0].Status | Should -BeIn @('Pass', 'Skipped')
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

    It '根步骤注册表启用 Windows 03/05/06/07/08/09/10/99 且保持 04/11 unsupported' {
        Import-Module (Join-Path $script:RepoRoot 'scripts/pwsh/install/InstallOrchestrator.psm1') -Force
        $registry = Import-InstallStepRegistry -Path (Join-Path $script:RepoRoot 'config/install/steps.psd1')
        $catalog = @(Get-InstallStepCatalog -Registry $registry -Platform windows)
        @($catalog | Where-Object Supported | ForEach-Object Number) | Should -Be @('03', '05', '06', '07', '08', '09', '10', '99')
        @($catalog | Where-Object { -not $_.Supported } | ForEach-Object Number) | Should -Be @('04', '11')
        $loginItemsStep = @($catalog | Where-Object Number -eq '10')[0]
        $loginItemsStep.Id | Should -Be 'login-items'
        $loginItemsStep.Path | Should -Be 'windows/10deployWslAutostart.ps1'
        $loginItemsStep.Runner | Should -Be 'pwsh'
        $loginItemsRegistryEntry = @($registry.Steps | Where-Object { [string]$_.Id -eq 'login-items' })[0]
        [string]$loginItemsRegistryEntry.Platforms['windows'].PreviewArgument | Should -Be '-WhatIf'
    }

    It '08 -WhatIf 同时输出 Scoop 与 WinGet 安装计划且零副作用退出 0' {
        $result = Invoke-WindowsTestProcess `
            -ScriptPath (Join-Path $script:RepoRoot 'windows/08installFullApps.ps1') `
            -ArgumentList @('-WhatIf')

        $result.ExitCode | Should -Be 0 -Because $result.Stderr
        # Scoop terminal-extras 计划仍在，且追加的 winget 段覆盖 sshcopyid。
        $result.Stdout | Should -Match 'ast-grep'
        $result.Stdout | Should -Match 'sshcopyid'
        # winget 段两行：autohotkey/sshcopyid 为 Preview（宿主已装则 AlreadyPresent）；eartrumpet 被标签过滤排除。
        $wingetLines = @($result.Stdout -split "`n" | Where-Object { $_ -match '^\[[A-Za-z]+\] (autohotkey|eartrumpet|sshcopyid)' })
        $wingetLines.Count | Should -Be 2
        @($wingetLines | Where-Object { $_ -match '^\[(Preview|AlreadyPresent)\] (autohotkey|sshcopyid)' }).Count | Should -Be 2
    }
}
