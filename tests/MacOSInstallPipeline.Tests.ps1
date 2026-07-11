Set-StrictMode -Version Latest

Describe 'macOS PowerShell 安装叶子' {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    }

    It '05 仅选择 Core CLI，06 仅选择 Core 字体，08 仅选择 Full 应用' {
        $coreOutput = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'macos/05installCoreCli.ps1') -WhatIf 2>&1
        $coreExitCode = $LASTEXITCODE
        $fontOutput = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'macos/06installFonts.ps1') -WhatIf 2>&1
        $fontExitCode = $LASTEXITCODE
        $fullOutput = pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'macos/08installFullApps.ps1') -WhatIf 2>&1
        $fullExitCode = $LASTEXITCODE

        $coreText = $coreOutput | Out-String
        $fontText = $fontOutput | Out-String
        $fullText = $fullOutput | Out-String

        $coreExitCode | Should -Be 0
        $fontExitCode | Should -Be 0
        $fullExitCode | Should -Be 0
        $coreText | Should -Match '\] ripgrep:'
        $coreText | Should -Match '\] uv:'
        $coreText | Should -Not -Match '\] hammerspoon:'
        $fontText | Should -Match '\] font-jetbrains-mono-nerd-font:'
        $fontText | Should -Not -Match '\] ripgrep:'
        $fullText | Should -Match '\] hammerspoon:'
        $fullText | Should -Match '\] blueutil:'
        $fullText | Should -Not -Match '\] font-jetbrains-mono-nerd-font:'
    }

    It '05 到 08 拒绝互斥的交互模式参数: <ScriptName>' -ForEach @(
        @{ ScriptName = '05installCoreCli.ps1' }
        @{ ScriptName = '06installFonts.ps1' }
        @{ ScriptName = '07installProfileTools.ps1' }
        @{ ScriptName = '08installFullApps.ps1' }
    ) {
        $output = pwsh -NoProfile -File (Join-Path $script:ProjectRoot "macos/$ScriptName") -Unattended -NonInteractive 2>&1

        $LASTEXITCODE | Should -Be 2
        ($output | Out-String) | Should -Match '不能同时使用'
    }

    It '07 的 WhatIf 不依赖本机已有 fnm、uv、bash 或 pnpm' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("macos-profile-tools.{0}" -f [System.Guid]::NewGuid())
        $emptyPath = Join-Path $tempRoot 'empty-bin'
        New-Item -ItemType Directory -Path $emptyPath -Force | Out-Null
        try {
            $originalPath = $env:PATH
            # 只保留 pwsh 所在目录，确保叶子预览不会意外依赖其他本机工具。
            $pwshDirectory = Split-Path -Parent (Get-Command pwsh -ErrorAction Stop).Source
            $env:PATH = $pwshDirectory + [IO.Path]::PathSeparator + $emptyPath
            $output = & pwsh -NoProfile -File (Join-Path $script:ProjectRoot 'macos/07installProfileTools.ps1') -WhatIf 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            $env:PATH = $originalPath
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }

        $exitCode | Should -Be 0
        ($output | Out-String) | Should -Match '\[Preview\] node-runtime:'
        ($output | Out-String) | Should -Match '\[Preview\] nbstripout:'
    }

    It '模块清单只在 Windows 加入 BurntToast' {
        $macResults = @(& (Join-Path $script:ProjectRoot 'profile/installer/installModules.ps1') -Platform macOS -WhatIf)
        $windowsResults = @(& (Join-Path $script:ProjectRoot 'profile/installer/installModules.ps1') -Platform Windows -WhatIf)

        @($macResults.Name) | Should -Contain 'Pester'
        @($macResults.Name) | Should -Contain 'PSReadLine'
        @($macResults.Name) | Should -Not -Contain 'BurntToast'
        @($windowsResults.Name) | Should -Contain 'BurntToast'
    }

    It '只读 helper 从统一清单返回 Core、字体和 Full 应用名称' {
        $helperPath = Join-Path $script:ProjectRoot 'macos/pwsh/Test-InstallState.ps1'
        $core = pwsh -NoProfile -File $helperPath -Step core-cli -OutputFormat Json | Out-String | ConvertFrom-Json
        $fonts = pwsh -NoProfile -File $helperPath -Step fonts -OutputFormat Json | Out-String | ConvertFrom-Json
        $full = pwsh -NoProfile -File $helperPath -Step full-apps -OutputFormat Json | Out-String | ConvertFrom-Json

        @($core.Name) | Should -Contain 'ripgrep'
        @($core.Name) | Should -Contain 'uv'
        @($fonts.Name) | Should -Contain 'font-jetbrains-mono-nerd-font'
        @($full.Name) | Should -Contain 'hammerspoon'
        @($full.Name) | Should -Contain 'blueutil'
        @($full | Where-Object Name -eq 'jordanbaird-ice').Status | Should -Be @('Warn')
    }
}

Describe 'PowerShell Profile 安装幂等性' {
    BeforeEach {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("profile-install.{0}" -f [System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
    }

    AfterEach {
        if ($script:TempRoot -and (Test-Path -LiteralPath $script:TempRoot)) {
            Remove-Item -LiteralPath $script:TempRoot -Recurse -Force
        }
    }

    It '只在真实变化时备份并写入 Profile' {
        $profilePath = Join-Path $script:TempRoot 'Microsoft.PowerShell_profile.ps1'
        $runnerPath = Join-Path $script:TempRoot 'invoke-profile-install.ps1'
        Set-Content -LiteralPath $profilePath -Value '# existing profile' -Encoding utf8NoBOM
        Set-Content -LiteralPath $runnerPath -Encoding utf8NoBOM -Value @'
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,
    [Parameter(Mandatory)]
    [string]$ProfilePath
)
$PROFILE = $ProfilePath
$script:ProfileEntryScriptPath = Join-Path $ProjectRoot 'profile/profile.ps1'
. (Join-Path $ProjectRoot 'profile/features/install.ps1')
$first = Set-PowerShellProfile
$second = Set-PowerShellProfile
[pscustomobject]@{
    FirstStatus = $first.Status
    SecondStatus = $second.Status
    BackupPath = $first.BackupPath
    BackupCount = @(Get-ChildItem -LiteralPath (Split-Path -Parent $ProfilePath) -Filter '*.bak').Count
    Content = Get-Content -LiteralPath $ProfilePath -Raw
} | ConvertTo-Json -Compress
'@

        $result = pwsh -NoProfile -File $runnerPath -ProjectRoot $script:ProjectRoot -ProfilePath $profilePath |
            Out-String |
            ConvertFrom-Json

        $LASTEXITCODE | Should -Be 0
        $result.FirstStatus | Should -Be 'Updated'
        $result.SecondStatus | Should -Be 'AlreadyPresent'
        $result.BackupCount | Should -Be 1
        $result.BackupPath | Should -Match '\.\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.bak$'
        $result.Content.Trim() | Should -Be ". `"$(Join-Path $script:ProjectRoot 'profile/profile.ps1')`""
    }
}

Describe 'macOS zsh 平台集成叶子' -Skip:(-not $IsMacOS) {
    BeforeEach {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("macos-leaves.{0}" -f [System.Guid]::NewGuid())
        $script:MockBin = Join-Path $script:TempRoot 'mock-bin'
        New-Item -ItemType Directory -Path $script:MockBin -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:MockBin 'open') -Encoding utf8NoBOM -Value "#!/bin/sh`nexit 0`n"
        chmod +x (Join-Path $script:MockBin 'open')
        $script:ChildPath = $script:MockBin + [IO.Path]::PathSeparator + $env:PATH
    }

    AfterEach {
        if ($script:TempRoot -and (Test-Path -LiteralPath $script:TempRoot)) {
            Remove-Item -LiteralPath $script:TempRoot -Recurse -Force
        }
    }

    It '04 在未提供 exclude 时可完成 shell dry-run' {
        $output = /usr/bin/env "HOME=$script:TempRoot" "PATH=$script:ChildPath" zsh `
            (Join-Path $script:ProjectRoot 'macos/04deployShellConfig.zsh') --preset Core --dry-run 2>&1

        $LASTEXITCODE | Should -Be 0
        ($output | Out-String) | Should -Match '同步完成'
    }

    It '09 重复部署相同 Hammerspoon 内容时不创建备份' {
        $firstOutput = /usr/bin/env "HOME=$script:TempRoot" "PATH=$script:ChildPath" zsh `
            (Join-Path $script:ProjectRoot 'macos/09deployHammerspoon.zsh') --preset Full --no-launch 2>&1
        $firstExitCode = $LASTEXITCODE
        $secondOutput = /usr/bin/env "HOME=$script:TempRoot" "PATH=$script:ChildPath" zsh `
            (Join-Path $script:ProjectRoot 'macos/09deployHammerspoon.zsh') --preset Full --no-launch 2>&1
        $secondExitCode = $LASTEXITCODE

        $firstExitCode | Should -Be 0
        $secondExitCode | Should -Be 0
        @(Get-ChildItem -LiteralPath (Join-Path $script:TempRoot '.hammerspoon') -Recurse -Filter '*.bak').Count | Should -Be 0
        ($secondOutput | Out-String) | Should -Match '内容未变化'
        ($firstOutput | Out-String) | Should -Match '配置部署完成'
    }

    It '10 dry-run 不调用 osascript，并支持移除预览' {
        $osascriptMarker = Join-Path $script:TempRoot 'osascript-called'
        Set-Content -LiteralPath (Join-Path $script:MockBin 'osascript') -Encoding utf8NoBOM -Value "#!/bin/sh`ntouch '$osascriptMarker'`nexit 0`n"
        chmod +x (Join-Path $script:MockBin 'osascript')

        $addOutput = /usr/bin/env "HOME=$script:TempRoot" "PATH=$script:ChildPath" zsh `
            (Join-Path $script:ProjectRoot 'macos/10configureLoginItems.zsh') --preset Full --dry-run 2>&1
        $addExitCode = $LASTEXITCODE
        $removeOutput = /usr/bin/env "HOME=$script:TempRoot" "PATH=$script:ChildPath" zsh `
            (Join-Path $script:ProjectRoot 'macos/10configureLoginItems.zsh') --preset Full --dry-run --remove 2>&1
        $removeExitCode = $LASTEXITCODE

        $addExitCode | Should -Be 0
        $removeExitCode | Should -Be 0
        Test-Path -LiteralPath $osascriptMarker | Should -BeFalse
        ($addOutput | Out-String) | Should -Match '确保登录项存在: Hammerspoon'
        ($removeOutput | Out-String) | Should -Match '移除登录项: Mos'
    }

    It '11 原子安装 Quick Action，内容变化时保留单个备份' {
        $scriptPath = Join-Path $script:ProjectRoot 'macos/11installQuickActions.zsh'
        $firstOutput = /usr/bin/env "HOME=$script:TempRoot" "PATH=$script:ChildPath" zsh $scriptPath --preset Full 2>&1
        $firstExitCode = $LASTEXITCODE
        $targetWorkflow = Join-Path $script:TempRoot 'Library/Services/Fix App Open Issue.workflow'
        Set-Content -LiteralPath (Join-Path $targetWorkflow 'local-change.txt') -Value 'changed' -Encoding utf8NoBOM
        $secondOutput = /usr/bin/env "HOME=$script:TempRoot" "PATH=$script:ChildPath" zsh $scriptPath --preset Full 2>&1
        $secondExitCode = $LASTEXITCODE

        $firstExitCode | Should -Be 0
        $secondExitCode | Should -Be 0
        Test-Path -LiteralPath $targetWorkflow -PathType Container | Should -BeTrue
        @(Get-ChildItem -LiteralPath (Join-Path $script:TempRoot 'Library/Services') -Directory -Filter '*.bak').Count | Should -Be 1
        ($firstOutput | Out-String) | Should -Match '已安装 Finder 快捷操作'
        ($secondOutput | Out-String) | Should -Match '备份现有 workflow'
    }

    It '99 输出单文档 JSON，并拒绝未知步骤' {
        $verifyPath = Join-Path $script:ProjectRoot 'macos/99verifyInstall.zsh'
        $jsonOutput = zsh $verifyPath --preset Core --step repo --output-format json 2>$null
        $jsonExitCode = $LASTEXITCODE
        $invalidOutput = zsh $verifyPath --step unknown-step 2>&1
        $invalidExitCode = $LASTEXITCODE

        $document = $jsonOutput | Out-String | ConvertFrom-Json
        $jsonExitCode | Should -Be 0
        $document.Preset | Should -Be 'Core'
        $document.Status | Should -Be 'Succeeded'
        @($document.Results | Select-Object -ExpandProperty Step -Unique) | Should -Be @('repo')
        $invalidExitCode | Should -Be 2
        ($invalidOutput | Out-String) | Should -Match '未知验证步骤'
    }

    It '99 的应用验证名称来自 apps-config' {
        $verifyPath = Join-Path $script:ProjectRoot 'macos/99verifyInstall.zsh'
        $jsonOutput = zsh $verifyPath --preset Core --step core-cli --output-format json 2>$null
        $exitCode = $LASTEXITCODE
        $document = $jsonOutput | Out-String | ConvertFrom-Json
        $messages = @($document.Results.Message)

        $exitCode | Should -BeIn @(0, 1, 10)
        ($messages -join "`n") | Should -Match 'ripgrep:'
        ($messages -join "`n") | Should -Match 'uv:'
        ($messages -join "`n") | Should -Not -Match 'hammerspoon:'
    }
}
