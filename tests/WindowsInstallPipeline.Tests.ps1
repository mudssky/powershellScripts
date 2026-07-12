BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:RepoRoot 'windows/pwsh/WindowsInstall.psm1') -Force
    Import-Module (Join-Path $script:RepoRoot 'windows/bootstrap/WindowsBootstrap.psm1') -Force
    Import-Module (Join-Path $script:RepoRoot 'scripts/pwsh/install/ProfileTools.psm1') -Force
    Import-Module (Join-Path $script:RepoRoot 'psutils') -Force

    function Invoke-WindowsTestProcess {
        <#
        .SYNOPSIS
            在独立 pwsh 进程执行脚本，避免被脚本 exit 终止 Pester。

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
            -CommandAvailability @{ winget = $true; pwsh = $true; scoop = $true; wsl = $true }

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
            -Administrator $false

        $platform.Edition | Should -Be 'Windows10'
        $platform.SupportLevel | Should -Be 'Full'
        $platform.SupportsModernWslConfig | Should -BeFalse
    }

    It '将 ARM64 和 Server 保持在非完整支持路径' {
        (Get-WindowsInstallEnvironment -WindowsHost $true -ProductName 'Windows 11 Pro' -InstallationType Client -BuildNumber 22631 -Architecture arm64 -Administrator $false).SupportLevel |
            Should -Be 'Blocked'
        (Get-WindowsInstallEnvironment -WindowsHost $true -ProductName 'Windows Server 2025' -InstallationType Server -BuildNumber 26100 -Architecture amd64 -Administrator $true).SupportLevel |
            Should -Be 'Partial'
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

    It 'Core 只包含确认的 10 个 Scoop CLI' {
        $core = @(Select-PackageManagerApps -Apps @($script:PackageManagers.scoop) -TargetOS Windows -RequiredTag @('core', 'cli'))
        @($core.name) | Should -Be @('zoxide', 'fnm', 'starship', 'fzf', 'ripgrep', 'jq', 'uv', 'bat', 'fd', 'eza')
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
        function global:scoop {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromRemainingArguments)]
                [object[]]$RemainingArguments
            )

            Write-Host 'Installed apps:'
            Write-Output ([pscustomobject]@{ Name = 'JetBrainsMono-NF' })
            Write-Output ([pscustomobject]@{ Name = 'FiraCode-NF' })
        }

        try {
            $output = @(& (Join-Path $script:RepoRoot 'windows/pwsh/Test-InstallState.ps1') `
                    -Step fonts `
                    -OutputFormat Json 6>&1)
            $document = ($output -join [System.Environment]::NewLine) | ConvertFrom-Json

            @($document).Count | Should -Be 2
            @($document.Status | Select-Object -Unique) | Should -Be @('Pass')
        }
        finally {
            Remove-Item Function:\global:scoop -ErrorAction SilentlyContinue
        }
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

    It '03 WhatIf 输出单个可解析 JSON document' {
        $result = Invoke-WindowsTestProcess `
            -ScriptPath (Join-Path $script:RepoRoot 'windows/03configureSources.ps1') `
            -ArgumentList @('-NetworkMode', 'Direct', '-TransactionId', 'windows-test', '-OutputFormat', 'Json', '-WhatIf')
        $result.ExitCode | Should -Be 0
        $document = $result.Stdout | ConvertFrom-Json
        $document.SchemaVersion | Should -Be 1
        @($document.Results.Target) | Should -Contain 'winget'
        @($document.Results.Target) | Should -Contain 'npm'
    }

    It 'Core、字体、Full 和 AutoHotkey 叶子 WhatIf 不执行真实安装' {
        $cases = @(
            @{ Path = 'windows/05installCoreCli.ps1'; Arguments = @('-Preset', 'Core', '-WhatIf'); Expected = 'zoxide' },
            @{ Path = 'windows/06installFonts.ps1'; Arguments = @('-Preset', 'Core', '-WhatIf'); Expected = 'JetBrainsMono-NF' },
            @{ Path = 'windows/08installFullApps.ps1'; Arguments = @('-Preset', 'Full', '-WhatIf'); Expected = 'terminal-extras|xh' },
            @{ Path = 'windows/09deployAutoHotkey.ps1'; Arguments = @('-Preset', 'Full', '-StartupPath', (Join-Path $TestDrive 'Startup'), '-WhatIf'); Expected = 'AutoHotkey' }
        )
        foreach ($case in $cases) {
            $result = Invoke-WindowsTestProcess -ScriptPath (Join-Path $script:RepoRoot $case.Path) -ArgumentList $case.Arguments
            $result.ExitCode | Should -Be 0
            ($result.Stdout + $result.Stderr) | Should -Match $case.Expected
        }
        Test-Path -LiteralPath (Join-Path $TestDrive 'Startup') | Should -BeFalse
    }

    It 'WSL WhatIf 不写配置也不调用 shutdown' {
        $target = Join-Path $TestDrive '.wslconfig'
        $result = Invoke-WindowsTestProcess `
            -ScriptPath (Join-Path $script:RepoRoot 'windows/wsl/Initialize-WslHost.ps1') `
            -ArgumentList @('-Distribution', 'Ubuntu-24.04', '-WslConfigTargetPath', $target, '-WhatIf')
        $result.ExitCode | Should -Be 0
        $result.Stdout | Should -Match 'Preview'
        $result.Stdout | Should -Not -Match 'wsl --shutdown.*执行'
        Test-Path -LiteralPath $target | Should -BeFalse
    }

    It '99 始终输出单个 JSON document' {
        $result = Invoke-WindowsTestProcess `
            -ScriptPath (Join-Path $script:RepoRoot 'windows/99verifyInstall.ps1') `
            -ArgumentList @('-Preset', 'Core', '-OutputFormat', 'Json')
        $document = $result.Stdout | ConvertFrom-Json
        $document.SchemaVersion | Should -Be 1
        $document.Preset | Should -Be 'Core'
        $document.Results.Count | Should -BeGreaterThan 0
    }

    It '根步骤注册表启用 Windows 03/05/06/07/08/09/99 且保持 04/10/11 unsupported' {
        Import-Module (Join-Path $script:RepoRoot 'scripts/pwsh/install/InstallOrchestrator.psm1') -Force
        $registry = Import-InstallStepRegistry -Path (Join-Path $script:RepoRoot 'config/install/steps.psd1')
        $catalog = @(Get-InstallStepCatalog -Registry $registry -Platform windows)
        @($catalog | Where-Object Supported | ForEach-Object Number) | Should -Be @('03', '05', '06', '07', '08', '09', '99')
        @($catalog | Where-Object { -not $_.Supported } | ForEach-Object Number) | Should -Be @('04', '10', '11')
    }
}
