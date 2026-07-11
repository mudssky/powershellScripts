Set-StrictMode -Version Latest

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'linux/pwsh/LinuxInstall.psm1'
    $script:CatalogPath = Join-Path $script:ProjectRoot 'config/install/linux-packages.psd1'
    Import-Module $script:ModulePath -Force

    function New-LinuxEnvironmentFixture {
        <#
        .SYNOPSIS
            创建隔离的平台探测 fixture。

        .PARAMETER OsRelease
            os-release 文件内容。

        .PARAMETER ProcVersion
            proc version 文件内容。

        .PARAMETER WithSystemd
            是否创建 systemd 运行态目录。

        .OUTPUTS
            PSCustomObject。包含 Root、OsReleasePath、ProcVersionPath 和 SystemdDirectory。
        #>
        param(
            [Parameter(Mandatory)]
            [string]$OsRelease,

            [string]$ProcVersion = 'Linux version 6.8.0-generic',

            [switch]$WithSystemd
        )

        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("linux-install-{0}" -f [guid]::NewGuid().ToString('N'))
        $systemdDirectory = Join-Path $root 'run/systemd/system'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        if ($WithSystemd) {
            New-Item -ItemType Directory -Path $systemdDirectory -Force | Out-Null
        }
        $osReleasePath = Join-Path $root 'os-release'
        $procVersionPath = Join-Path $root 'proc-version'
        Set-Content -LiteralPath $osReleasePath -Value $OsRelease -Encoding utf8NoBOM
        Set-Content -LiteralPath $procVersionPath -Value $ProcVersion -Encoding utf8NoBOM
        return [pscustomobject]@{
            Root               = $root
            OsReleasePath      = $osReleasePath
            ProcVersionPath    = $procVersionPath
            SystemdDirectory   = $systemdDirectory
        }
    }
}

Describe 'Linux install platform model' -Tag 'Unit' {
    BeforeEach {
        $script:FixtureRoots = [System.Collections.Generic.List[string]]::new()
    }

    AfterEach {
        foreach ($root in $script:FixtureRoots) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'classifies Ubuntu amd64 with systemd as fully supported' {
        $fixture = New-LinuxEnvironmentFixture -OsRelease "ID=ubuntu`nID_LIKE=debian" -WithSystemd
        $script:FixtureRoots.Add($fixture.Root)

        $environment = Get-LinuxInstallEnvironment `
            -OsReleasePath $fixture.OsReleasePath `
            -ProcVersionPath $fixture.ProcVersionPath `
            -SystemdDirectory $fixture.SystemdDirectory `
            -Architecture x86_64 `
            -WslInterop '' `
            -WslDistroName '' `
            -Display '' `
            -WaylandDisplay '' `
            -XdgCurrentDesktop ''

        $environment.DistributionId | Should -Be 'ubuntu'
        $environment.DistributionFamily | Should -Be 'debian'
        $environment.SourceTarget | Should -Be 'ubuntu'
        $environment.Architecture | Should -Be 'amd64'
        $environment.IsWsl | Should -BeFalse
        $environment.HasSystemd | Should -BeTrue
        $environment.SupportLevel | Should -Be 'Full'
    }

    It 'detects WSL from proc version and defaults font mode to Server' {
        $fixture = New-LinuxEnvironmentFixture `
            -OsRelease "ID=debian" `
            -ProcVersion 'Linux version 6.6.87.2-microsoft-standard-WSL2'
        $script:FixtureRoots.Add($fixture.Root)

        $environment = Get-LinuxInstallEnvironment `
            -OsReleasePath $fixture.OsReleasePath `
            -ProcVersionPath $fixture.ProcVersionPath `
            -SystemdDirectory $fixture.SystemdDirectory `
            -Architecture amd64 `
            -WslInterop '' `
            -WslDistroName '' `
            -Display ':0' `
            -WaylandDisplay 'wayland-0' `
            -XdgCurrentDesktop 'WSLg'

        $environment.IsWsl | Should -BeTrue
        $environment.HasDesktop | Should -BeTrue
        Resolve-LinuxFontEnvironment -Environment Auto -Platform $environment | Should -Be 'Server'
        Resolve-LinuxFontEnvironment -Environment Desktop -Platform $environment | Should -Be 'Desktop'
    }

    It 'classifies Arch as partial and arm64 as blocked' {
        $archFixture = New-LinuxEnvironmentFixture -OsRelease "ID=arch"
        $armFixture = New-LinuxEnvironmentFixture -OsRelease "ID=ubuntu`nID_LIKE=debian"
        $script:FixtureRoots.Add($archFixture.Root)
        $script:FixtureRoots.Add($armFixture.Root)

        $arch = Get-LinuxInstallEnvironment `
            -OsReleasePath $archFixture.OsReleasePath `
            -ProcVersionPath $archFixture.ProcVersionPath `
            -SystemdDirectory $archFixture.SystemdDirectory `
            -Architecture x86_64 `
            -WslInterop '' `
            -WslDistroName ''
        $arm = Get-LinuxInstallEnvironment `
            -OsReleasePath $armFixture.OsReleasePath `
            -ProcVersionPath $armFixture.ProcVersionPath `
            -SystemdDirectory $armFixture.SystemdDirectory `
            -Architecture aarch64 `
            -WslInterop '' `
            -WslDistroName ''

        $arch.SupportLevel | Should -Be 'Partial'
        $arch.SourceTarget | Should -Be 'arch'
        $arm.Architecture | Should -Be 'arm64'
        $arm.SupportLevel | Should -Be 'Blocked'
    }

    It 'blocks unknown distributions and normalizes architecture aliases' {
        $fixture = New-LinuxEnvironmentFixture -OsRelease "ID=fedora`nID_LIKE=`"rhel fedora`""
        $script:FixtureRoots.Add($fixture.Root)

        $environment = Get-LinuxInstallEnvironment `
            -OsReleasePath $fixture.OsReleasePath `
            -ProcVersionPath $fixture.ProcVersionPath `
            -SystemdDirectory $fixture.SystemdDirectory `
            -Architecture x64 `
            -WslInterop '' `
            -WslDistroName ''

        $environment.DistributionFamily | Should -Be 'unknown'
        $environment.SourceTarget | Should -Be ''
        $environment.SupportLevel | Should -Be 'Blocked'
        ConvertTo-LinuxArchitecture -Architecture x86_64 | Should -Be 'amd64'
        ConvertTo-LinuxArchitecture -Architecture arm64 | Should -Be 'arm64'
        ConvertTo-LinuxArchitecture -Architecture riscv64 | Should -Be 'unknown'
    }
}

Describe 'Linux package catalog and result contract' -Tag 'Unit' {
    It 'loads the Debian family from the shared config resolver' {
        $catalog = Import-LinuxPackageCatalog -Path $script:CatalogPath
        $family = Get-LinuxPackageFamily -Catalog $catalog -DistributionFamily debian

        $catalog.SchemaVersion | Should -Be 1
        $family.DistributionIds | Should -Contain 'ubuntu'
        $family.CoreSystem | Should -Contain 'build-essential'
        $family.Docker.Required | Should -Contain 'docker.io'
        $family.DesktopFonts.Required | Should -Contain 'fontconfig'
    }

    It 'rejects unsupported package families' {
        $catalog = Import-LinuxPackageCatalog -Path $script:CatalogPath

        { Get-LinuxPackageFamily -Catalog $catalog -DistributionFamily arch } |
            Should -Throw '*不支持发行版族*'
    }

    It 'uses Failed before Blocked when aggregating exit codes' {
        $results = @(
            New-LinuxInstallResult -Name repo -Status Succeeded
            New-LinuxInstallResult -Name wsl -Status RestartRequired -ExitCode 10
        )
        Get-LinuxInstallExitCode -Result $results | Should -Be 10

        $results += New-LinuxInstallResult -Name docker -Status Failed -ExitCode 1
        Get-LinuxInstallExitCode -Result $results | Should -Be 1
    }

    It 'maps strict non-interactive sudo failure to Blocked without retrying interactively' {
        Mock Invoke-LinuxNativeCommand {
            New-LinuxInstallResult -Name sudo -Status Failed -ExitCode 1
        } -ModuleName LinuxInstall

        $result = Get-LinuxSudoPreflightResult -NonInteractive

        $result.Status | Should -Be 'Blocked'
        $result.ExitCode | Should -Be 10
        $result.Message | Should -Match '严格非交互模式'
        Should -Invoke Invoke-LinuxNativeCommand -ModuleName LinuxInstall -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'sudo' -and
            $FilePath -eq 'sudo' -and
            ($ArgumentList -join ' ') -eq '-n true'
        }
    }
}

Describe 'Linux PowerShell install leaves' -Tag 'Leaves' {
    BeforeEach {
        $script:LeafFixture = New-LinuxEnvironmentFixture `
            -OsRelease "ID=ubuntu`nID_LIKE=debian" `
            -WithSystemd
        $env:POWERSHELL_SCRIPTS_OS_RELEASE_PATH = $script:LeafFixture.OsReleasePath
        $env:POWERSHELL_SCRIPTS_PROC_VERSION_PATH = $script:LeafFixture.ProcVersionPath
        $env:POWERSHELL_SCRIPTS_SYSTEMD_DIRECTORY = $script:LeafFixture.SystemdDirectory
        $env:POWERSHELL_SCRIPTS_ARCHITECTURE = 'x86_64'
        Remove-Item Env:\WSL_INTEROP -ErrorAction SilentlyContinue
        Remove-Item Env:\WSL_DISTRO_NAME -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item Env:\POWERSHELL_SCRIPTS_OS_RELEASE_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\POWERSHELL_SCRIPTS_PROC_VERSION_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\POWERSHELL_SCRIPTS_SYSTEMD_DIRECTORY -ErrorAction SilentlyContinue
        Remove-Item Env:\POWERSHELL_SCRIPTS_ARCHITECTURE -ErrorAction SilentlyContinue
        Remove-Item Env:\WSL_INTEROP -ErrorAction SilentlyContinue
        Remove-Item Env:\WSL_DISTRO_NAME -ErrorAction SilentlyContinue
        Remove-Item Env:\DISPLAY -ErrorAction SilentlyContinue
        Remove-Item Env:\WAYLAND_DISPLAY -ErrorAction SilentlyContinue
        Remove-Item Env:\XDG_CURRENT_DESKTOP -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:LeafFixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It '05 只选择 Core CLI，08 只选择 terminal extras' {
        $coreOutput = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'linux/05installCoreCli.ps1') -WhatIf 2>&1
        $coreExitCode = $LASTEXITCODE
        $fullOutput = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'linux/08installFullApps.ps1') -WhatIf 2>&1
        $fullExitCode = $LASTEXITCODE
        $coreText = $coreOutput | Out-String
        $fullText = $fullOutput | Out-String

        $coreExitCode | Should -Be 0
        $fullExitCode | Should -Be 0
        $coreText | Should -Match '\] ripgrep:'
        $coreText | Should -Match '\] uv:'
        $coreText | Should -Not -Match '\] lazygit:'
        $fullText | Should -Match '\] lazygit:'
        $fullText | Should -Match '\] neovim:'
        $fullText | Should -Not -Match '\] ripgrep:'
        $fullText | Should -Not -Match 'hammerspoon'
    }

    It '06 在 WSL 默认跳过，显式 Desktop 只生成 apt 与 font-cache 计划' {
        $env:WSL_DISTRO_NAME = 'Ubuntu-24.04'
        $serverOutput = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'linux/06installFonts.ps1') -WhatIf 2>&1
        $serverExitCode = $LASTEXITCODE
        $desktopOutput = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'linux/06installFonts.ps1') -Environment Desktop -WhatIf 2>&1
        $desktopExitCode = $LASTEXITCODE

        $serverExitCode | Should -Be 0
        ($serverOutput | Out-String) | Should -Match '\[Skipped\] fonts:'
        $desktopExitCode | Should -Be 0
        ($desktopOutput | Out-String) | Should -Match '\[Preview\] fonts-packages:'
        ($desktopOutput | Out-String) | Should -Match '\[Preview\] font-cache:'
    }

    It '07 WhatIf 汇总系统包、公共 Profile Tools 与 Docker 且不写系统' {
        $output = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'linux/07installProfileTools.ps1') -WhatIf 2>&1
        $exitCode = $LASTEXITCODE
        $text = $output | Out-String

        $exitCode | Should -Be 0
        $text | Should -Match '\[Preview\] core-system:'
        $text | Should -Match '\[Preview\] node-runtime:'
        $text | Should -Match '\[Preview\] docker:'
    }

    It '05 到 08 拒绝互斥交互参数: <ScriptName>' -ForEach @(
        @{ ScriptName = '05installCoreCli.ps1' }
        @{ ScriptName = '06installFonts.ps1' }
        @{ ScriptName = '07installProfileTools.ps1' }
        @{ ScriptName = '08installFullApps.ps1' }
    ) {
        $output = pwsh -NoProfile -File (Join-Path $script:ProjectRoot "linux/$ScriptName") -Unattended -NonInteractive 2>&1

        $LASTEXITCODE | Should -Be 2
        ($output | Out-String) | Should -Match '不能同时使用'
    }
}

Describe 'WSL guest config and Docker plan' -Tag 'Wsl', 'Unit' {
    BeforeEach {
        $script:WslRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wsl-config-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:WslRoot -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:WslRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'backs up changed wsl.conf once and is idempotent on rerun' {
        $sourcePath = Join-Path $script:ProjectRoot 'linux/wsl/wsl.conf'
        $targetPath = Join-Path $script:WslRoot 'wsl.conf'
        Set-Content -LiteralPath $targetPath -Value "[boot]`nsystemd=false`n" -Encoding utf8NoBOM

        $first = Install-WslGuestConfig -SourcePath $sourcePath -TargetPath $targetPath
        $second = Install-WslGuestConfig -SourcePath $sourcePath -TargetPath $targetPath

        $first.Status | Should -Be 'RestartRequired'
        $first.Message | Should -Match 'wsl --shutdown'
        $second.Status | Should -Be 'AlreadyPresent'
        @(Get-ChildItem -LiteralPath $script:WslRoot -Filter '*.bak').Count | Should -Be 1
        (Get-Content -LiteralPath $targetPath -Raw) | Should -BeExactly (Get-Content -LiteralPath $sourcePath -Raw)
    }

    It 'previews Docker packages without probing the local daemon' {
        $catalog = Import-LinuxPackageCatalog -Path $script:CatalogPath
        $family = Get-LinuxPackageFamily -Catalog $catalog -DistributionFamily debian
        $platform = [pscustomobject]@{
            SupportLevel = 'Full'
            HasSystemd   = $true
        }

        $result = @(Install-LinuxDocker -Platform $platform -PackageFamily $family -Preview)

        $result.Count | Should -Be 1
        $result[0].Status | Should -Be 'Preview'
        $result[0].Message | Should -Match 'docker.io'
    }

    It 'returns RestartRequired after granting Docker group access' {
        $catalog = Import-LinuxPackageCatalog -Path $script:CatalogPath
        $family = Get-LinuxPackageFamily -Catalog $catalog -DistributionFamily debian
        $platform = [pscustomobject]@{
            SupportLevel = 'Full'
            HasSystemd   = $true
            IsWsl        = $false
        }
        $originalUser = $env:USER
        $env:USER = 'pipeline-user'

        Mock Test-LinuxDockerAvailable { $false } -ModuleName LinuxInstall
        Mock Resolve-LinuxAptAlternative { 'docker-compose-v2' } -ModuleName LinuxInstall
        Mock Install-LinuxAptPackages {
            @(New-LinuxInstallResult -Name docker-packages -Status Succeeded)
        } -ModuleName LinuxInstall
        Mock Invoke-LinuxNativeCommand {
            param($Name)
            New-LinuxInstallResult -Name $Name -Status Succeeded
        } -ModuleName LinuxInstall

        try {
            $result = @(Install-LinuxDocker -Platform $platform -PackageFamily $family)

            @($result.Status) | Should -Contain 'RestartRequired'
            ($result | Where-Object Name -eq 'docker-access').Message | Should -Match '重新登录'
            Should -Invoke Invoke-LinuxNativeCommand -ModuleName LinuxInstall -ParameterFilter {
                $Name -eq 'docker-group' -and $ArgumentList -join ' ' -eq 'usermod -aG docker pipeline-user'
            }
            Should -Invoke Invoke-LinuxNativeCommand -ModuleName LinuxInstall -ParameterFilter {
                $Name -eq 'docker-daemon' -and $ArgumentList -join ' ' -eq 'docker info'
            }
        }
        finally {
            $env:USER = $originalUser
        }
    }
}

Describe 'Linux read-only verification' -Tag 'Verify' {
    BeforeEach {
        $script:VerifyFixture = New-LinuxEnvironmentFixture `
            -OsRelease "ID=ubuntu`nID_LIKE=debian" `
            -WithSystemd
        $env:POWERSHELL_SCRIPTS_OS_RELEASE_PATH = $script:VerifyFixture.OsReleasePath
        $env:POWERSHELL_SCRIPTS_PROC_VERSION_PATH = $script:VerifyFixture.ProcVersionPath
        $env:POWERSHELL_SCRIPTS_SYSTEMD_DIRECTORY = $script:VerifyFixture.SystemdDirectory
        $env:POWERSHELL_SCRIPTS_ARCHITECTURE = 'x86_64'
        Remove-Item Env:\WSL_INTEROP -ErrorAction SilentlyContinue
        Remove-Item Env:\WSL_DISTRO_NAME -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item Env:\POWERSHELL_SCRIPTS_OS_RELEASE_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\POWERSHELL_SCRIPTS_PROC_VERSION_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\POWERSHELL_SCRIPTS_SYSTEMD_DIRECTORY -ErrorAction SilentlyContinue
        Remove-Item Env:\POWERSHELL_SCRIPTS_ARCHITECTURE -ErrorAction SilentlyContinue
        Remove-Item Env:\WSL_INTEROP -ErrorAction SilentlyContinue
        Remove-Item Env:\WSL_DISTRO_NAME -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:VerifyFixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'outputs one JSON document for an exact successful step' {
        $jsonOutput = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'linux/99verifyInstall.ps1') -Step repo -OutputFormat Json 2>$null
        $exitCode = $LASTEXITCODE
        $document = $jsonOutput | Out-String | ConvertFrom-Json

        $exitCode | Should -Be 0
        $document.Preset | Should -Be 'Core'
        $document.Status | Should -Be 'Succeeded'
        @($document.Results.Step | Select-Object -Unique) | Should -Be @('repo')
    }

    It 'uses apps-config names for Core CLI verification' {
        $jsonOutput = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'linux/99verifyInstall.ps1') -Step core-cli -OutputFormat Json 2>$null
        $document = $jsonOutput | Out-String | ConvertFrom-Json
        $names = @($document.Results.Name)

        $LASTEXITCODE | Should -BeIn @(0, 1, 10)
        $names | Should -Contain 'ripgrep'
        $names | Should -Contain 'uv'
        $names | Should -Not -Contain 'hammerspoon'
    }

    It 'rejects unknown verification steps with exit code 2' {
        $output = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'linux/99verifyInstall.ps1') -Step unknown 2>&1

        $LASTEXITCODE | Should -Be 2
        ($output | Out-String) | Should -Match '未知 Linux 验证步骤'
    }

    It 'reports ARM as Blocked without running install checks' {
        $env:POWERSHELL_SCRIPTS_ARCHITECTURE = 'aarch64'
        $jsonOutput = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'linux/99verifyInstall.ps1') -Step platform -OutputFormat Json 2>$null
        $exitCode = $LASTEXITCODE
        $document = $jsonOutput | Out-String | ConvertFrom-Json

        $exitCode | Should -Be 10
        $document.Status | Should -Be 'Blocked'
        $document.Environment | Should -Be 'ubuntu-arm64'
    }

    It 'passes matching WSL guest config after systemd is active' {
        $env:WSL_DISTRO_NAME = 'Ubuntu-24.04'
        $targetPath = Join-Path $script:VerifyFixture.Root 'wsl.conf'
        Copy-Item -LiteralPath (Join-Path $script:ProjectRoot 'linux/wsl/wsl.conf') -Destination $targetPath

        $jsonOutput = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'linux/99verifyInstall.ps1') `
            -Step wsl-config `
            -WslConfigTargetPath $targetPath `
            -OutputFormat Json 2>$null
        $exitCode = $LASTEXITCODE
        $document = $jsonOutput | Out-String | ConvertFrom-Json

        $exitCode | Should -Be 0
        @($document.Results.Status) | Should -Be @('Pass')
    }
}

Describe 'Linux orchestrator integration' -Tag 'Integration' {
    BeforeEach {
        $script:IntegrationFixture = New-LinuxEnvironmentFixture `
            -OsRelease "ID=ubuntu`nID_LIKE=debian" `
            -WithSystemd
        $env:POWERSHELL_SCRIPTS_UNAME_S = 'Linux'
        $env:POWERSHELL_SCRIPTS_OS_RELEASE_PATH = $script:IntegrationFixture.OsReleasePath
        $env:POWERSHELL_SCRIPTS_PROC_VERSION_PATH = $script:IntegrationFixture.ProcVersionPath
        $env:POWERSHELL_SCRIPTS_SYSTEMD_DIRECTORY = $script:IntegrationFixture.SystemdDirectory
        $env:POWERSHELL_SCRIPTS_ARCHITECTURE = 'x86_64'
        Remove-Item Env:\WSL_INTEROP -ErrorAction SilentlyContinue
        Remove-Item Env:\WSL_DISTRO_NAME -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item Env:\POWERSHELL_SCRIPTS_UNAME_S -ErrorAction SilentlyContinue
        Remove-Item Env:\POWERSHELL_SCRIPTS_OS_RELEASE_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\POWERSHELL_SCRIPTS_PROC_VERSION_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\POWERSHELL_SCRIPTS_SYSTEMD_DIRECTORY -ErrorAction SilentlyContinue
        Remove-Item Env:\POWERSHELL_SCRIPTS_ARCHITECTURE -ErrorAction SilentlyContinue
        Remove-Item Env:\WSL_INTEROP -ErrorAction SilentlyContinue
        Remove-Item Env:\WSL_DISTRO_NAME -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:IntegrationFixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It '03 Direct WhatIf returns one source JSON document on Linux' -Skip:(-not $IsLinux) {
        $output = bash (Join-Path $script:ProjectRoot 'linux/03configureSources.sh') `
            --network-mode Direct `
            --transaction-id integration-source `
            --output-format json `
            --dry-run 2>$null
        $exitCode = $LASTEXITCODE
        $document = $output | Out-String | ConvertFrom-Json

        $exitCode | Should -Be 0
        $document.ExitCode | Should -Be 0
        @($document.Results.Target) | Should -Contain 'ubuntu'
        @($document.Results.Target) | Should -Contain 'brew'
    }

    It 'root Core WhatIf reaches every Linux Core step without argument errors' -Skip:(-not $IsLinux) {
        $output = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'install.ps1') `
            -Preset Core `
            -NetworkMode Direct `
            -WhatIf `
            -OutputFormat Json 2>$null
        $document = $output | Out-String | ConvertFrom-Json

        @($document.Results.Id) | Should -Be @('sources', 'shell', 'core-cli', 'fonts', 'profile-tools', 'verify')
        ($document.Results.Message -join "`n") | Should -Not -Match '参数错误|未知参数|不支持的 preset'
        ($document.Results | Where-Object Id -eq 'sources').Status | Should -Be 'Preview'
    }
}
