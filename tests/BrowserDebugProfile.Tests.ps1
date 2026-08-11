Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:ToolRoot = Join-Path $script:RepoRoot 'scripts/pwsh/devops/browser-debug'
    $env:PWSH_TEST_SKIP_BROWSER_DEBUG_MAIN = '1'
    . (Join-Path $script:ToolRoot 'main.ps1')
}

AfterAll {
    Remove-Item Env:\PWSH_TEST_SKIP_BROWSER_DEBUG_MAIN -ErrorAction SilentlyContinue
    Remove-Item Env:\BROWSER_DEBUG_REGISTRY_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\BROWSER_DEBUG_ROOT_PATH -ErrorAction SilentlyContinue
}

Describe 'browser-debug manifest 与 CLI schema' {
    It '只公开一个生成入口' {
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:ToolRoot 'tool.psd1')
        $manifest.BinName | Should -Be 'browser-debug.ps1'
        $manifest.Entry | Should -Be 'main.ps1'
    }

    It '从同一 schema 提供帮助和动作补全' {
        (Get-BrowserDebugHelpText -Resource profile) | Should -Match 'profile start <name>'
        (Get-BrowserDebugHelpText -Resource profile -Action create) | Should -Match '--source-user-data-path'
        (Get-BrowserDebugHelpText -Resource profile -Action create) | Should -Match '--without-extensions'
        (Get-BrowserDebugHelpText -Resource profile -Action shortcut) | Should -Match 'profile shortcut <name> --mode local\|lan'
        (Get-BrowserDebugHelpText -Resource profile -Action start) | Should -Match '--open-guide'
        Get-BrowserDebugCompletionCandidates -Line 'browser-debug profile st' -Position 24 | Should -Be @('start', 'status', 'stop')
        Get-BrowserDebugCompletionCandidates -Line 'browser-debug profile start demo --mode l' -Position 41 | Should -Be @('lan', 'local')
        Get-BrowserDebugCompletionCandidates -Line 'browser-debug profile create demo --with' -Position 40 | Should -Contain '--without-extensions'
    }

    It '解析 kebab-case 选项并输出稳定 JSON 错误' {
        $parsed = ConvertFrom-BrowserDebugArguments -Arguments @('profile', 'start', 'demo', '--mode', 'lan', '--json')
        $parsed.Name | Should -Be 'demo'
        $parsed.Options['mode'] | Should -Be 'lan'
        (ConvertFrom-BrowserDebugArguments -Arguments @('profile', 'start', 'demo', '--open-guide')).Options['open-guide'] | Should -BeTrue
        $result = Invoke-BrowserDebugCli -Arguments @('unknown', '--json')
        $result.ExitCode | Should -Be 1
        ($result.Output | ConvertFrom-Json).schemaVersion | Should -Be 1
        ($result.Output | ConvertFrom-Json).success | Should -BeFalse
    }

    It '严格拒绝未知选项、多余位置参数和缺少的必需选项' {
        { ConvertFrom-BrowserDebugArguments -Arguments @('profile', 'start', 'demo', '--unknown', 'value') } | Should -Throw '*未知选项*'
        { ConvertFrom-BrowserDebugArguments -Arguments @('profile', 'status', 'demo', 'extra') } | Should -Throw '*多余位置参数*'
        { ConvertFrom-BrowserDebugArguments -Arguments @('profile', 'create', 'demo') } | Should -Throw '*--browser*'
        { ConvertFrom-BrowserDebugArguments -Arguments @('ssh', 'create', 'demo', '--profile', 'work') } | Should -Throw '*--direction*'
        { ConvertFrom-BrowserDebugArguments -Arguments @('profile', '--unknown', 'value', '--help') } | Should -Throw '*未知选项*'
        { Invoke-BrowserDebugCli -Arguments @('help', 'profile', 'start', 'extra') } | Should -Not -Throw
        (Invoke-BrowserDebugCli -Arguments @('help', 'profile', 'start', 'extra')).ExitCode | Should -Be 1
        (Invoke-BrowserDebugCli -Arguments @('--help', 'extra')).ExitCode | Should -Be 1
    }

    It 'action 帮助展开选项且空列表 JSON 保持数组' {
        (Get-BrowserDebugHelpText -Resource profile -Action start) | Should -Match '--listen-address'
        $registryPath = Join-Path $TestDrive 'empty-registry.json'
        $result = Invoke-BrowserDebugCli -Arguments @('profile', 'list', '--registry-path', $registryPath, '--json')
        $json = $result.Output | ConvertFrom-Json
        $json.data.GetType().IsArray | Should -BeTrue
        $json.data.Count | Should -Be 0
    }
}

Describe 'browser-debug registry' {
    BeforeEach {
        $script:RegistryPath = Join-Path $TestDrive 'registry/registry.json'
    }

    It '首次写入并在后续修改前创建可读时间戳备份' {
        $registry = New-BrowserDebugRegistry
        Write-BrowserDebugRegistry -RegistryPath $script:RegistryPath -Registry $registry | Out-Null
        $registry.profiles = @([pscustomobject]@{ name = 'demo' })
        Write-BrowserDebugRegistry -RegistryPath $script:RegistryPath -Registry $registry | Out-Null
        Test-Path -LiteralPath $script:RegistryPath | Should -BeTrue
        @(Get-ChildItem (Split-Path -Parent $script:RegistryPath) -Filter 'registry.json.*.bak').Count | Should -Be 1
        (Read-BrowserDebugRegistry -RegistryPath $script:RegistryPath).profiles[0].name | Should -Be 'demo'
    }

    It '在全新 PowerShell 进程中重复读取时保持共享配置命令可用' {
        $registry = New-BrowserDebugRegistry
        Write-BrowserDebugRegistry -RegistryPath $script:RegistryPath -Registry $registry | Out-Null
        $mainPath = Join-Path $script:ToolRoot 'main.ps1'
        $childScript = @"
`$env:PWSH_TEST_SKIP_BROWSER_DEBUG_MAIN = '1'
. '$($mainPath.Replace("'", "''"))'
Read-BrowserDebugRegistry -RegistryPath '$($script:RegistryPath.Replace("'", "''"))' | Out-Null
Read-BrowserDebugRegistry -RegistryPath '$($script:RegistryPath.Replace("'", "''"))' | Out-Null
if (-not (Get-Command Resolve-ConfigSources -ErrorAction SilentlyContinue)) { exit 9 }
"@
        & pwsh -NoLogo -NoProfile -Command $childScript
        $LASTEXITCODE | Should -Be 0
    }

    It '补全只读 registry 中的动态名称' {
        $registry = New-BrowserDebugRegistry
        $registry.profiles = @([pscustomobject]@{ name = 'alpha' }, [pscustomobject]@{ name = 'beta' })
        Write-BrowserDebugRegistry -RegistryPath $script:RegistryPath -Registry $registry | Out-Null
        Get-BrowserDebugCompletionCandidates -Line 'browser-debug profile status a' -Position 30 -RegistryPath $script:RegistryPath | Should -Be 'alpha'
    }
}

Describe 'browser-debug Profile 集成' {
    BeforeAll {
        . (Join-Path $script:RepoRoot 'profile/features/environment.ps1')
    }

    BeforeEach {
        Remove-Variable -Name __BrowserDebugCompletionRegistered -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name __BrowserDebugCompletionCommandPath -Scope Global -ErrorAction SilentlyContinue
        Remove-Item Alias:\browser-debug -Force -ErrorAction SilentlyContinue
        $script:FakeProfileRoot = Join-Path $TestDrive 'profile-root'
        $fakeToolRoot = Join-Path $script:FakeProfileRoot 'scripts/pwsh/devops/browser-debug'
        $fakeBinRoot = Join-Path $script:FakeProfileRoot 'bin'
        New-Item -ItemType Directory -Path $fakeToolRoot, $fakeBinRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:ToolRoot 'completion.ps1') -Destination (Join-Path $fakeToolRoot 'completion.ps1') -Force
        Set-Content -LiteralPath (Join-Path $fakeBinRoot 'browser-debug.ps1') -Encoding utf8NoBOM -Value @'
param([Parameter(ValueFromRemainingArguments = $true)][object[]]$RemainingArgs)
if ($RemainingArgs[0] -eq '__complete') { 'profile' }
'@
    }

    It '幂等注册别名和真实 Native Completion，不读取 registry' {
        Mock Read-BrowserDebugRegistry { throw 'Profile 启动路径不应读取 registry' }
        Register-BrowserDebugProfileIntegration -ProfileRoot $script:FakeProfileRoot
        Register-BrowserDebugProfileIntegration -ProfileRoot $script:FakeProfileRoot
        (Get-Alias browser-debug).Definition | Should -Be (Join-Path $script:FakeProfileRoot 'bin/browser-debug.ps1')
        $Global:__BrowserDebugCompletionRegistered | Should -BeTrue
        $completion = [System.Management.Automation.CommandCompletion]::CompleteInput('browser-debug pro', 17, $null)
        $completion.CompletionMatches.CompletionText | Should -Contain 'profile'
        Should -Invoke Read-BrowserDebugRegistry -Times 0
    }

    It '通过真实 alias 与 ps1 入口调用内部补全且不终止当前会话' {
        $completionPath = Join-Path $script:ToolRoot 'completion.ps1'
        $commandPath = Join-Path $script:RepoRoot 'bin/browser-debug.ps1'
        $childCommand = @"
Remove-Item Env:\PWSH_TEST_SKIP_BROWSER_DEBUG_MAIN -ErrorAction SilentlyContinue
. '$($completionPath.Replace("'", "''"))'
Register-BrowserDebugCompletion -CommandPath '$($commandPath.Replace("'", "''"))'
[System.Management.Automation.CommandCompletion]::CompleteInput('browser-debug pro', 17, `$null).CompletionMatches.CompletionText
'current-session-alive'
"@
        $aliasCompletion = & pwsh -NoLogo -NoProfile -Command $childCommand
        $savedSkipMain = $env:PWSH_TEST_SKIP_BROWSER_DEBUG_MAIN
        Remove-Item Env:\PWSH_TEST_SKIP_BROWSER_DEBUG_MAIN -ErrorAction SilentlyContinue
        try { $scriptCompletion = & pwsh -NoLogo -NoProfile -File $commandPath __complete --line 'browser-debug.ps1 pro' --position 21 }
        finally { $env:PWSH_TEST_SKIP_BROWSER_DEBUG_MAIN = $savedSkipMain }
        $aliasCompletion | Should -Contain 'profile'
        $aliasCompletion | Should -Contain 'current-session-alive'
        $scriptCompletion | Should -Contain 'profile'
        'current-session-alive' | Should -Be 'current-session-alive'
    }
}

Describe 'browser-debug Profile 生命周期' {
    BeforeEach {
        $script:RegistryPath = Join-Path $TestDrive 'registry.json'
        $script:ProfileRoot = Join-Path $TestDrive 'profiles'
        Remove-Item -LiteralPath $script:RegistryPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:ProfileRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $TestDrive 'Desktop') -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $TestDrive -Filter 'registry.json.*.bak' -ErrorAction SilentlyContinue | Remove-Item -Force
        $env:BROWSER_DEBUG_ROOT_PATH = $script:ProfileRoot
        Mock Resolve-BrowserDebugExecutable { 'C:\Program Files\Browser\browser.exe' }
        Mock Resolve-BrowserDebugDefaultUserDataPath { Join-Path $TestDrive 'source-user-data' }
        Mock Resolve-BrowserDebugDesktopPath { Join-Path $TestDrive 'Desktop' }
        Mock Add-BrowserDebugProfileShortcut {
            $fileName = if ($Mode -eq 'lan') { "$($Profile.name)-LAN.lnk" } else { "$($Profile.name).lnk" }
            $path = Join-Path $ShortcutDirectory $fileName
            & $PersistScriptBlock $path
            $path
        }
        Mock Copy-BrowserDebugUserData {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
            [pscustomobject]@{ sourceUserDataPath = [System.IO.Path]::GetFullPath($SourcePath); profilePath = [System.IO.Path]::GetFullPath($DestinationPath); extensionsCopied = -not $WithoutExtensions }
        }
        Mock Test-BrowserDebugPortOpen { $false }
        Mock Get-BrowserDebugChromiumProcesses { @() }
        Mock Get-BrowserDebugCdpVersion { $null }
    }

    It 'create 克隆 User Data、登记和创建快捷方式，但不启动浏览器' {
        Mock Start-BrowserDebugProfileProcess { throw '不应启动' }
        $profile = Invoke-BrowserDebugProfileCreate -Name demo -Options ([ordered]@{ browser = 'chrome'; 'cdp-port' = '9333' }) -RegistryPath $script:RegistryPath
        $profile.cdpPort | Should -Be 9333
        $profile.extensionsCopied | Should -BeTrue
        $profile.shortcutPath | Should -Be (Join-Path $TestDrive 'Desktop/demo.lnk')
        $profile.shortcutPaths.local | Should -Be $profile.shortcutPath
        $profile.shortcutPaths.lan | Should -BeNullOrEmpty
        Test-Path -LiteralPath $profile.profilePath -PathType Container | Should -BeTrue
        (Read-BrowserDebugRegistry -RegistryPath $script:RegistryPath).profiles.Count | Should -Be 1
        Should -Invoke Copy-BrowserDebugUserData -Times 1
        Should -Invoke Add-BrowserDebugProfileShortcut -ParameterFilter { $Mode -eq 'local' }
        Should -Invoke Start-BrowserDebugProfileProcess -Times 0
    }

    It 'create 支持自定义来源并通过 without-extensions 排除扩展' {
        $customSource = Join-Path $TestDrive 'custom-edge-user-data'
        $profile = Invoke-BrowserDebugProfileCreate -Name demo -Options ([ordered]@{
                browser                 = 'edge'
                'source-user-data-path' = $customSource
                'without-extensions'    = $true
            }) -RegistryPath $script:RegistryPath
        $profile.sourceUserDataPath | Should -Be ([System.IO.Path]::GetFullPath($customSource))
        $profile.extensionsCopied | Should -BeFalse
        Should -Invoke Copy-BrowserDebugUserData -ParameterFilter {
            $SourcePath -eq $customSource -and $WithoutExtensions
        }
    }

    It '快捷方式或 registry 写入失败时回滚已克隆目录且不登记' {
        Mock Add-BrowserDebugProfileShortcut { throw 'shortcut failed' }
        { Invoke-BrowserDebugProfileCreate -Name demo -Options ([ordered]@{ browser = 'chrome' }) -RegistryPath $script:RegistryPath } | Should -Throw '*shortcut failed*'
        Test-Path -LiteralPath (Join-Path $script:ProfileRoot 'demo') | Should -BeFalse
        (Read-BrowserDebugRegistry -RegistryPath $script:RegistryPath).profiles.Count | Should -Be 0
    }

    It '拒绝复用其他已登记 Profile 的路径或覆盖既有快捷方式' {
        $registry = New-BrowserDebugRegistry
        $sharedPath = Join-Path $script:ProfileRoot 'shared'
        $registry.profiles = @([pscustomobject]@{ name = 'other'; profilePath = $sharedPath; cdpPort = 9444 })
        Write-BrowserDebugRegistry -RegistryPath $script:RegistryPath -Registry $registry | Out-Null
        { Invoke-BrowserDebugProfileCreate -Name demo -Options ([ordered]@{ browser = 'chrome'; 'profile-path' = $sharedPath }) -RegistryPath $script:RegistryPath } | Should -Throw '*已被登记*'

        $desktop = Join-Path $TestDrive 'Desktop'
        New-Item -ItemType Directory -Path $desktop -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $desktop 'demo.lnk') -Value 'existing'
        { Invoke-BrowserDebugProfileCreate -Name demo -Options ([ordered]@{ browser = 'chrome'; 'shortcut-directory' = $desktop }) -RegistryPath $script:RegistryPath } | Should -Throw '*快捷方式已存在*'
        Should -Invoke Copy-BrowserDebugUserData -Times 0
    }

    It '停止状态允许持久修改端口，运行状态拒绝修改' {
        Invoke-BrowserDebugProfileCreate -Name demo -Options ([ordered]@{ browser = 'chrome'; 'cdp-port' = '9333' }) -RegistryPath $script:RegistryPath | Out-Null
        $updated = Invoke-BrowserDebugProfileSet -Name demo -Options ([ordered]@{ 'cdp-port' = '9444' }) -RegistryPath $script:RegistryPath
        $updated.cdpPort | Should -Be 9444
        Mock Get-BrowserDebugProfileRuntimeStatus { [pscustomobject]@{ running = $true } }
        { Invoke-BrowserDebugProfileSet -Name demo -Options ([ordered]@{ 'cdp-port' = '9555' }) -RegistryPath $script:RegistryPath } | Should -Throw '*先执行 profile stop*'
    }

    It 'start 默认 local 并允许显式 lan 地址' {
        Invoke-BrowserDebugProfileCreate -Name demo -Options ([ordered]@{ browser = 'edge' }) -RegistryPath $script:RegistryPath | Out-Null
        Mock Start-BrowserDebugProfileProcess { [pscustomobject]@{ mode = $Mode; listenAddress = $ListenAddress } }
        (Invoke-BrowserDebugProfileStart -Name demo -Options ([ordered]@{}) -RegistryPath $script:RegistryPath).mode | Should -Be 'local'
        $lan = Invoke-BrowserDebugProfileStart -Name demo -Options ([ordered]@{ mode = 'lan'; 'listen-address' = '192.168.1.10' }) -RegistryPath $script:RegistryPath
        $lan.mode | Should -Be 'lan'
        $lan.listenAddress | Should -Be '192.168.1.10'
        { Invoke-BrowserDebugProfileStart -Name demo -Options ([ordered]@{ mode = 'lan'; 'listen-address' = '127.0.0.1' }) -RegistryPath $script:RegistryPath } | Should -Throw '*不能是回环*'
        { Invoke-BrowserDebugProfileStart -Name demo -Options ([ordered]@{ mode = 'lan'; 'listen-address' = 'host.local' }) -RegistryPath $script:RegistryPath } | Should -Throw '*IPv4*'
    }

    It '可在运行中追加 LAN 快捷方式且保留 Local 登记' {
        Invoke-BrowserDebugProfileCreate -Name demo -Options ([ordered]@{ browser = 'edge' }) -RegistryPath $script:RegistryPath | Out-Null
        Mock Get-BrowserDebugProfileRuntimeStatus { [pscustomobject]@{ running = $true } }
        $result = Invoke-BrowserDebugProfileShortcut -Name demo -Options ([ordered]@{ mode = 'lan' }) -RegistryPath $script:RegistryPath
        $result.shortcutPath | Should -Be (Join-Path $TestDrive 'Desktop/demo-LAN.lnk')
        $profile = Invoke-BrowserDebugProfileGet -Name demo -RegistryPath $script:RegistryPath
        $profile.shortcutPaths.local | Should -Be (Join-Path $TestDrive 'Desktop/demo.lnk')
        $profile.shortcutPaths.lan | Should -Be $result.shortcutPath
        $profile.shortcutPath | Should -Be $profile.shortcutPaths.local
        Should -Invoke Get-BrowserDebugProfileRuntimeStatus -Times 0
    }

    It 'open-guide 对同模式运行实例复用，对不同模式明确拒绝' {
        Invoke-BrowserDebugProfileCreate -Name demo -Options ([ordered]@{ browser = 'edge' }) -RegistryPath $script:RegistryPath | Out-Null
        Mock Get-BrowserDebugProfileRuntimeStatus {
            [pscustomobject]@{
                running = $true; mode = 'local'; listenAddress = '127.0.0.1'; cdpAvailable = $true
                endpoint = 'http://127.0.0.1:9222'; cdpPort = 9222; processIds = @(321); cdpVersion = [pscustomobject]@{ Browser = 'Edge/1' }
            }
        }
        Mock New-BrowserDebugGuideSnapshot { [pscustomobject]@{ name = 'demo'; mode = 'local' } }
        Mock Write-BrowserDebugGuide { Join-Path $TestDrive 'guides/demo-local.html' }
        Mock Open-BrowserDebugGuide {}
        $reused = Invoke-BrowserDebugProfileStart -Name demo -Options ([ordered]@{ mode = 'local'; 'open-guide' = $true }) -RegistryPath $script:RegistryPath
        $reused.reused | Should -BeTrue
        $reused.processId | Should -Be 321
        $reused.guidePath | Should -Match 'demo-local\.html$'
        { Invoke-BrowserDebugProfileStart -Name demo -Options ([ordered]@{ mode = 'lan'; 'open-guide' = $true }) -RegistryPath $script:RegistryPath } | Should -Throw '*不能复用为 lan*profile stop demo*'
    }

    It '帮助页生成或打开失败只返回 warning，不改变浏览器成功结果' {
        Invoke-BrowserDebugProfileCreate -Name demo -Options ([ordered]@{ browser = 'edge' }) -RegistryPath $script:RegistryPath | Out-Null
        Mock Get-BrowserDebugProfileRuntimeStatus { [pscustomobject]@{ running = $false; portOpen = $false } }
        Mock Start-BrowserDebugProfileProcess { [pscustomobject]@{ processId = 123; processIds = @(123); mode = 'local'; listenAddress = '127.0.0.1'; cdpVersion = [pscustomobject]@{ Browser = 'Edge/1' } } }
        Mock New-BrowserDebugGuideSnapshot { throw 'guide failed' }
        $result = Invoke-BrowserDebugProfileStart -Name demo -Options ([ordered]@{ 'open-guide' = $true }) -RegistryPath $script:RegistryPath
        $result.processId | Should -Be 123
        $result.warnings | Should -BeLike '*guide failed*'
    }

    It '浏览器 detached 启动参数包含独立 Profile、端口和监听地址' {
        $profile = [pscustomobject]@{ name = 'demo'; browserPath = 'C:\Browser\chrome.exe'; profilePath = 'C:\Profiles\demo'; cdpPort = 9333 }
        Mock Get-BrowserDebugProfileRuntimeStatus { [pscustomobject]@{ running = $false; portOpen = $false } }
        Mock Start-BrowserDebugDetachedProcess { [pscustomobject]@{ Id = 1234; HasExited = $false } }
        Mock Get-BrowserDebugCdpVersion { [pscustomobject]@{ Browser = 'Chrome' } }
        Mock Get-BrowserDebugChromiumProcesses {
            @([pscustomobject]@{ ProcessId = 1234; ExecutablePath = 'C:\Browser\chrome.exe'; CommandLine = 'chrome.exe --user-data-dir="C:\Profiles\demo" --remote-debugging-port=9333 --remote-debugging-address=192.168.1.10' })
        }
        $result = Start-BrowserDebugProfileProcess -Profile $profile -Mode lan -ListenAddress '192.168.1.10'
        $result.processId | Should -Be 1234
        $result.cdpPort | Should -Be 9333
        Should -Invoke Get-BrowserDebugCdpVersion -ParameterFilter { $Port -eq 9333 -and $Address -eq '192.168.1.10' }
        Should -Invoke Start-BrowserDebugDetachedProcess -ParameterFilter {
            $FilePath -eq 'C:\Browser\chrome.exe' -and
            $Arguments -contains '--user-data-dir=C:\Profiles\demo' -and
            $Arguments -contains '--remote-debugging-port=9333' -and
            $Arguments -contains '--remote-debugging-address=192.168.1.10' -and
            $Arguments -contains '--no-first-run' -and
            $Arguments -contains '--no-default-browser-check'
        }
    }

    It '启动器退出 0 后等待拥有目标 Profile 的子进程和 CDP 就绪' {
        $profile = [pscustomobject]@{ name = 'edge-debug'; browserPath = 'C:\Browser\msedge.exe'; profilePath = 'C:\Profiles\edge-debug'; cdpPort = 21229 }
        Mock Get-BrowserDebugProfileRuntimeStatus { [pscustomobject]@{ running = $false; portOpen = $false } }
        Mock Start-BrowserDebugDetachedProcess { [pscustomobject]@{ Id = 1000; HasExited = $true; ExitCode = 0 } }
        $script:CdpProbeCount = 0
        Mock Get-BrowserDebugCdpVersion {
            $script:CdpProbeCount++
            if ($script:CdpProbeCount -ge 2) { [pscustomobject]@{ Browser = 'Edg/140'; webSocketDebuggerUrl = 'ws://127.0.0.1:21229/devtools/browser/id' } }
        }
        Mock Get-BrowserDebugChromiumProcesses {
            @([pscustomobject]@{ ProcessId = 2000; ExecutablePath = 'C:\Browser\msedge.exe'; CommandLine = 'msedge.exe --user-data-dir="C:\Profiles\edge-debug" --remote-debugging-port=21229 --remote-debugging-address=127.0.0.1' })
        }
        $result = Start-BrowserDebugProfileProcess -Profile $profile -Mode local
        $result.processId | Should -Be 2000
        $result.launcherProcessId | Should -Be 1000
        $result.cdpVersion.Browser | Should -Be 'Edg/140'
        $script:CdpProbeCount | Should -BeGreaterOrEqual 2
    }

    It '启动器非零退出且没有 owned 进程或 CDP 时尽早报错' {
        $profile = [pscustomobject]@{ name = 'broken'; browserPath = 'C:\Browser\msedge.exe'; profilePath = 'C:\Profiles\broken'; cdpPort = 21230 }
        Mock Get-BrowserDebugProfileRuntimeStatus { [pscustomobject]@{ running = $false; portOpen = $false } }
        Mock Start-BrowserDebugDetachedProcess { [pscustomobject]@{ Id = 3000; HasExited = $true; ExitCode = 5 } }
        Mock Get-BrowserDebugCdpVersion { $null }
        Mock Get-BrowserDebugChromiumProcesses { @() }
        { Start-BrowserDebugProfileProcess -Profile $profile -Mode local } | Should -Throw '*异常退出*退出码: 5*未发现目标 Profile 进程或 CDP*'
    }

    It '启动器退出 0 但没有接管证据时保持明确超时错误' {
        $profile = [pscustomobject]@{ name = 'missing'; browserPath = 'C:\Browser\msedge.exe'; profilePath = 'C:\Profiles\missing'; cdpPort = 21231 }
        Mock Get-BrowserDebugProfileRuntimeStatus { [pscustomobject]@{ running = $false; portOpen = $false } }
        Mock Start-BrowserDebugDetachedProcess { [pscustomobject]@{ Id = 4000; HasExited = $true; ExitCode = 0 } }
        Mock Get-BrowserDebugCdpVersion { $null }
        Mock Get-BrowserDebugChromiumProcesses { @() }
        { Start-BrowserDebugProfileProcess -Profile $profile -Mode local -StartupTimeoutSeconds 1 } | Should -Throw '*启动器已退出*退出码: 0*未在超时内同时就绪*'
    }

    It '只把可执行文件和规范化 user-data-dir 同时匹配的进程视为所有者' {
        $profile = [pscustomobject]@{ browserPath = 'C:\Browser\chrome.exe'; profilePath = 'C:\Profiles\demo' }
        Test-BrowserDebugProcessOwnership -Profile $profile -Process ([pscustomobject]@{ ExecutablePath = 'C:\Browser\chrome.exe'; CommandLine = 'chrome.exe --user-data-dir="C:\Profiles\demo"' }) | Should -BeTrue
        Test-BrowserDebugProcessOwnership -Profile $profile -Process ([pscustomobject]@{ ExecutablePath = 'C:\Browser\chrome.exe'; CommandLine = 'chrome.exe --user-data-dir="C:\Users\me\Default"' }) | Should -BeFalse
        Test-BrowserDebugProcessOwnership -Profile $profile -Process ([pscustomobject]@{ ExecutablePath = 'C:\Other\chrome.exe'; CommandLine = 'chrome.exe --user-data-dir="C:\Profiles\demo"' }) | Should -BeFalse
    }

    It 'status 从 owned 主进程读取实际端口和 LAN 接口而非 registry 陈旧值' {
        $profile = [pscustomobject]@{ name = 'demo'; browserPath = 'C:\Browser\edge.exe'; profilePath = 'C:\Profiles\demo'; cdpPort = 9222 }
        Mock Get-BrowserDebugChromiumProcesses {
            @([pscustomobject]@{ ProcessId = 777; ExecutablePath = 'C:\Browser\edge.exe'; CommandLine = 'edge.exe --user-data-dir="C:\Profiles\demo" --remote-debugging-port=9444 --remote-debugging-address=192.168.1.8' })
        }
        Mock Get-BrowserDebugCdpVersion { [pscustomobject]@{ Browser = 'Edge/1' } }
        Mock Test-BrowserDebugPortOpen { $true }
        $status = Get-BrowserDebugProfileRuntimeStatus -Profile $profile
        $status.processId | Should -Be 777
        $status.cdpPort | Should -Be 9444
        $status.mode | Should -Be 'lan'
        $status.listenAddress | Should -Be '192.168.1.8'
        $status.endpoint | Should -Be 'http://192.168.1.8:9444'
        Should -Invoke Get-BrowserDebugCdpVersion -ParameterFilter { $Port -eq 9444 -and $Address -eq '192.168.1.8' }
    }

    It '停止首个 owned 进程导致后续 PID 自行退出时仍幂等成功' {
        $profile = [pscustomobject]@{ browserPath = 'C:\Browser\msedge.exe'; profilePath = 'C:\Profiles\edge-debug' }
        Mock Get-BrowserDebugChromiumProcesses {
            @(
                [pscustomobject]@{ ProcessId = 100; ExecutablePath = 'C:\Browser\msedge.exe'; CommandLine = 'msedge.exe --user-data-dir="C:\Profiles\edge-debug"' }
                [pscustomobject]@{ ProcessId = 200; ExecutablePath = 'C:\Browser\msedge.exe'; CommandLine = 'msedge.exe --user-data-dir="C:\Profiles\edge-debug"' }
                [pscustomobject]@{ ProcessId = 300; ExecutablePath = 'C:\Browser\msedge.exe'; CommandLine = 'msedge.exe --user-data-dir="C:\Users\me\Default"' }
            )
        }
        Mock Stop-Process {
            if ($Id -eq 200) {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Management.Automation.ItemNotFoundException]::new("PID $Id 已退出"),
                    'NoProcessFoundForGivenId',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $Id
                )
                throw $errorRecord
            }
        }
        Stop-BrowserDebugProfileProcess -Profile $profile | Should -Be @(100, 200)
        Should -Invoke Stop-Process -Times 2
        Should -Invoke Stop-Process -Times 0 -ParameterFilter { $Id -eq 300 }
    }

    It '停止 owned 进程遇到访问拒绝时保留真实错误' {
        $profile = [pscustomobject]@{ browserPath = 'C:\Browser\msedge.exe'; profilePath = 'C:\Profiles\edge-debug' }
        Mock Get-BrowserDebugChromiumProcesses {
            @([pscustomobject]@{ ProcessId = 400; ExecutablePath = 'C:\Browser\msedge.exe'; CommandLine = 'msedge.exe --user-data-dir="C:\Profiles\edge-debug"' })
        }
        Mock Stop-Process {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.UnauthorizedAccessException]::new('访问被拒绝'),
                'CouldNotStopProcess',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $Id
            )
            throw $errorRecord
        }
        { Stop-BrowserDebugProfileProcess -Profile $profile } | Should -Throw '*访问被拒绝*'
    }
}

Describe 'browser-debug User Data 克隆' {
    BeforeEach {
        $script:SourceUserData = Join-Path $TestDrive 'User Data'
        $script:CloneTarget = Join-Path $TestDrive 'profiles/demo'
        $script:BrowserPath = 'C:\Program Files\Browser\browser.exe'
        Remove-Item -LiteralPath $script:SourceUserData -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Split-Path -Parent $script:CloneTarget) -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $script:SourceUserData -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:SourceUserData 'Local State') -Value '{}'
        Mock Get-BrowserDebugChromiumProcesses { @() }
        Mock Invoke-BrowserDebugRobocopy {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $SourcePath 'Local State') -Destination $DestinationPath
            1
        }
    }

    It '默认复制扩展，只排除锁文件和运行时临时内容' {
        $result = Copy-BrowserDebugUserData -BrowserPath $script:BrowserPath -SourcePath $script:SourceUserData -DestinationPath $script:CloneTarget -DefaultSourcePath $script:SourceUserData
        $result.extensionsCopied | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:CloneTarget 'Local State') | Should -BeTrue
        Should -Invoke Invoke-BrowserDebugRobocopy -ParameterFilter {
            $ExcludedFiles -contains 'SingletonLock' -and
            $ExcludedFiles -contains 'LOCK' -and
            $ExcludedDirectories -notcontains 'Extensions'
        }
    }

    It 'without-extensions 排除扩展本体和扩展状态目录' {
        $result = Copy-BrowserDebugUserData -BrowserPath $script:BrowserPath -SourcePath $script:SourceUserData -DestinationPath $script:CloneTarget -DefaultSourcePath $script:SourceUserData -WithoutExtensions
        $result.extensionsCopied | Should -BeFalse
        Should -Invoke Invoke-BrowserDebugRobocopy -ParameterFilter {
            $ExcludedDirectories -contains 'Extensions' -and
            $ExcludedDirectories -contains 'Local Extension Settings' -and
            $ExcludedDirectories -contains 'Sync Extension Settings'
        }
    }

    It '来源浏览器运行时拒绝复制并提示关闭后重试' {
        Mock Get-BrowserDebugChromiumProcesses {
            @([pscustomobject]@{ ExecutablePath = $script:BrowserPath; CommandLine = 'browser.exe' })
        }
        { Copy-BrowserDebugUserData -BrowserPath $script:BrowserPath -SourcePath $script:SourceUserData -DestinationPath $script:CloneTarget -DefaultSourcePath $script:SourceUserData } | Should -Throw '*完全关闭浏览器后重试*'
        Should -Invoke Invoke-BrowserDebugRobocopy -Times 0
    }

    It '自定义来源只拒绝实际引用该 user-data-dir 的进程' {
        $otherPath = Join-Path $TestDrive 'Other User Data'
        Mock Get-BrowserDebugChromiumProcesses {
            @([pscustomobject]@{ ExecutablePath = $script:BrowserPath; CommandLine = "browser.exe --user-data-dir=`"$otherPath`"" })
        }
        { Copy-BrowserDebugUserData -BrowserPath $script:BrowserPath -SourcePath $script:SourceUserData -DestinationPath $script:CloneTarget -DefaultSourcePath $otherPath } | Should -Not -Throw
    }

    It '自定义来源位于活动 user-data-dir 内时也拒绝复制' {
        $activeRoot = Split-Path -Parent $script:SourceUserData
        Mock Get-BrowserDebugChromiumProcesses {
            @([pscustomobject]@{ ExecutablePath = $script:BrowserPath; CommandLine = "browser.exe --user-data-dir=`"$activeRoot`"" })
        }
        { Copy-BrowserDebugUserData -BrowserPath $script:BrowserPath -SourcePath $script:SourceUserData -DestinationPath $script:CloneTarget -DefaultSourcePath (Join-Path $TestDrive 'Default User Data') } | Should -Throw '*完全关闭浏览器后重试*'
    }

    It '存在 Chromium 锁文件时拒绝复制且不写目标' {
        Set-Content -LiteralPath (Join-Path $script:SourceUserData 'SingletonLock') -Value 'locked'
        { Copy-BrowserDebugUserData -BrowserPath $script:BrowserPath -SourcePath $script:SourceUserData -DestinationPath $script:CloneTarget -DefaultSourcePath $script:SourceUserData } | Should -Throw '*锁文件*完全关闭浏览器后重试*'
        Test-Path -LiteralPath $script:CloneTarget | Should -BeFalse
        Should -Invoke Invoke-BrowserDebugRobocopy -Times 0
    }

    It 'robocopy 失败时不留下最终 Profile 或临时克隆目录' {
        Mock Invoke-BrowserDebugRobocopy {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
            8
        }
        { Copy-BrowserDebugUserData -BrowserPath $script:BrowserPath -SourcePath $script:SourceUserData -DestinationPath $script:CloneTarget -DefaultSourcePath $script:SourceUserData } | Should -Throw '*退出码: 8*'
        Test-Path -LiteralPath $script:CloneTarget | Should -BeFalse
        @(Get-ChildItem -Path (Split-Path -Parent $script:CloneTarget) -Filter '.demo.clone.*' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It '拒绝直接复用来源目录或把目标放入来源内部' {
        { Copy-BrowserDebugUserData -BrowserPath $script:BrowserPath -SourcePath $script:SourceUserData -DestinationPath $script:SourceUserData -DefaultSourcePath $script:SourceUserData } | Should -Throw '*独立目录*'
        { Copy-BrowserDebugUserData -BrowserPath $script:BrowserPath -SourcePath $script:SourceUserData -DestinationPath (Join-Path $script:SourceUserData 'debug') -DefaultSourcePath $script:SourceUserData } | Should -Throw '*独立目录*'
    }
}

Describe 'browser-debug 快捷方式' {
    It 'Local 与 LAN 快捷方式只引用 Profile 名称、显式模式并打开指南' {
        $pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
        $profile = [pscustomobject]@{ name = 'demo'; browserPath = $pwshPath; cdpPort = 9333 }
        $shortcutPath = New-BrowserDebugShortcut -Profile $profile -ShortcutDirectory (Join-Path $TestDrive 'Desktop') -RepoRoot $script:RepoRoot
        Test-Path -LiteralPath $shortcutPath -PathType Leaf | Should -BeTrue
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
        $shortcut.Arguments | Should -Match 'profile start `?"?demo'
        $shortcut.Arguments | Should -Match '--mode local --open-guide'
        $shortcut.Arguments | Should -Not -Match '9333|--mode lan|ssh'

        $lanPath = New-BrowserDebugShortcut -Profile $profile -ShortcutDirectory (Join-Path $TestDrive 'Desktop') -RepoRoot $script:RepoRoot -Mode lan
        $lanPath | Should -Match 'demo-LAN\.lnk$'
        $lanShortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($lanPath)
        $lanShortcut.Arguments | Should -Match '--mode lan --open-guide'
    }

    It '同目录同模式幂等，未知同名文件拒绝覆盖' {
        $directory = Join-Path $TestDrive 'shortcuts'
        $profile = [pscustomobject]@{ name = 'demo'; browserPath = 'C:\Browser\edge.exe'; shortcutPath = $null; shortcutPaths = [pscustomobject]@{ local = $null; lan = $null } }
        Mock New-BrowserDebugShortcut {
            New-Item -ItemType File -Path $ShortcutPath -Force | Out-Null
            $ShortcutPath
        }
        $path = Add-BrowserDebugProfileShortcut -Profile $profile -Mode lan -ShortcutDirectory $directory -RepoRoot $script:RepoRoot -PersistScriptBlock {
            param($shortcutPath)
            $profile.shortcutPaths.lan = $shortcutPath
        }
        $secondPath = Add-BrowserDebugProfileShortcut -Profile $profile -Mode lan -ShortcutDirectory $directory -RepoRoot $script:RepoRoot -PersistScriptBlock { throw '不应重复持久化' }
        $secondPath | Should -Be $path
        Should -Invoke New-BrowserDebugShortcut -Times 1

        $unknownProfile = [pscustomobject]@{ name = 'demo'; browserPath = 'C:\Browser\edge.exe'; shortcutPath = $null; shortcutPaths = [pscustomobject]@{ local = $null; lan = $null } }
        { Add-BrowserDebugProfileShortcut -Profile $unknownProfile -Mode lan -ShortcutDirectory $directory -RepoRoot $script:RepoRoot -PersistScriptBlock {} } | Should -Throw '*未由该 Profile 登记*'
    }

    It '迁移快捷方式时 registry 持久化失败会恢复旧文件' {
        $oldDirectory = Join-Path $TestDrive 'old-shortcuts'
        $newDirectory = Join-Path $TestDrive 'new-shortcuts'
        New-Item -ItemType Directory -Path $oldDirectory -Force | Out-Null
        $oldPath = Join-Path $oldDirectory 'demo.lnk'
        Set-Content -LiteralPath $oldPath -Value 'old shortcut'
        $profile = [pscustomobject]@{ name = 'demo'; browserPath = 'C:\Browser\edge.exe'; shortcutPath = $oldPath; shortcutPaths = [pscustomobject]@{ local = $oldPath; lan = $null } }
        Mock New-BrowserDebugShortcut {
            New-Item -ItemType File -Path $ShortcutPath -Force | Out-Null
            $ShortcutPath
        }
        { Add-BrowserDebugProfileShortcut -Profile $profile -Mode local -ShortcutDirectory $newDirectory -RepoRoot $script:RepoRoot -PersistScriptBlock { throw 'registry failed' } } | Should -Throw '*registry failed*'
        Test-Path -LiteralPath $oldPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $newDirectory 'demo.lnk') | Should -BeFalse
    }
}

Describe 'browser-debug 启动帮助页' {
    It '通配 LAN 快照列出全部候选地址并使用实际端口同步 SSH 信息' {
        Mock Get-BrowserDebugLanIPv4Addresses { @('100.64.0.2', '172.20.0.1', '192.168.1.8') }
        $profile = [pscustomobject]@{ name = 'demo'; browser = 'edge'; profilePath = 'C:\Profiles\demo'; cdpPort = 9222 }
        $registry = [pscustomobject]@{ sshConfigurations = @([pscustomobject]@{ name = 'remote'; profile = 'demo'; direction = 'local-forward'; target = 'windows-host'; agentPort = 9555; sshConfigPath = $null; verboseLogging = $false }) }
        $startResult = [pscustomobject]@{ mode = 'lan'; listenAddress = '0.0.0.0'; cdpPort = 9444; cdpVersion = [pscustomobject]@{ Browser = 'Edge/1' } }
        $snapshot = New-BrowserDebugGuideSnapshot -Profile $profile -StartResult $startResult -Registry $registry
        $snapshot.cdpPort | Should -Be 9444
        $snapshot.endpoint | Should -Be 'http://127.0.0.1:9444'
        $snapshot.directConnections.endpoint | Should -Be @('http://100.64.0.2:9444', 'http://172.20.0.1:9444', 'http://192.168.1.8:9444')
        $snapshot.agentPrompt | Should -Match '页面列出的 LAN IPv4'
        $snapshot.sshConfigurations[0].sshCommand | Should -Match '127\.0\.0\.1:9444'
    }

    It '显式 LAN 监听只突出实际接口地址' {
        Mock Get-BrowserDebugLanIPv4Addresses { @('100.64.0.2', '192.168.1.8') }
        $profile = [pscustomobject]@{ name = 'demo'; browser = 'edge'; profilePath = 'C:\Profiles\demo'; cdpPort = 9444 }
        $snapshot = New-BrowserDebugGuideSnapshot -Profile $profile -StartResult ([pscustomobject]@{ mode = 'lan'; listenAddress = '192.168.1.8'; cdpPort = 9444; cdpVersion = $null }) -Registry ([pscustomobject]@{ sshConfigurations = @() })
        $snapshot.endpoint | Should -Be 'http://192.168.1.8:9444'
        $snapshot.directConnections.Count | Should -Be 1
        $snapshot.directConnections[0].address | Should -Be '192.168.1.8'
    }

    It '编码全部动态内容并包含模式、连接命令、复制按钮与 LAN 警告' {
        $snapshot = [pscustomobject]@{
            generatedAt = '2026-08-11T10:00:00+08:00'; name = '"><script>alert(1)</script><demo>'; browser = 'edge'; profilePath = 'C:\Profiles\<demo>'
            cdpPort = 9333; mode = 'lan'; listenAddress = '0.0.0.0'; endpoint = 'http://192.168.1.8:9333/" onfocus="alert(2)'
            probeUrl = 'http://192.168.1.8:9333/json/version'; playwrightCommand = 'playwright-cli attach --cdp=http://192.168.1.8:9333'
            cdpVersion = 'Edge/<1>'; lanAddresses = @('192.168.1.8'); agentPrompt = '连接 </script><script>alert(3)</script><现有> 浏览器'
            directConnections = @()
            sshConfigurations = @([pscustomobject]@{ name = '"><ssh>'; sshCommand = 'ssh host'; agentPrompt = '不要创建 <new>' })
            Cookie = 'cookie-secret'; password = 'password-secret'; token = 'token-secret'; history = 'history-secret'; tabTitle = 'tab-secret'
        }
        $html = ConvertTo-BrowserDebugGuideHtml -Snapshot $snapshot
        $html | Should -Match '&lt;demo&gt;'
        $html | Should -Match 'playwright-cli attach'
        $html | Should -Match 'data-copy='
        $html | Should -Match "execCommand\('copy'\)"
        $html | Should -Match 'LAN 安全警告'
        $html | Should -Not -Match '<demo>|<现有>|<ssh>|<new>'
        $html | Should -Not -Match '<script>alert|onfocus="alert'
        ([regex]::Matches($html, '<script>')).Count | Should -Be 1
        $html | Should -Not -Match 'cookie-secret|password-secret|token-secret|history-secret|tab-secret'
    }

    It '渲染专业运维布局、语义状态与无外部依赖的可访问复制控件' {
        $snapshot = [pscustomobject]@{
            generatedAt = '2026-08-11T10:00:00+08:00'; name = 'edge-debug'; browser = 'edge'; profilePath = 'D:\browser-debug-profiles\edge-debug'
            cdpPort = 21229; mode = 'lan'; listenAddress = '0.0.0.0'; endpoint = 'http://127.0.0.1:21229'
            probeUrl = 'http://127.0.0.1:21229/json/version'; playwrightCommand = 'playwright-cli attach --cdp=http://127.0.0.1:21229'
            cdpVersion = 'Edg/140.0'; lanAddresses = @('100.64.0.2', '192.168.1.8'); agentPrompt = '连接现有浏览器'
            directConnections = @([pscustomobject]@{ address = '192.168.1.8'; endpoint = 'http://192.168.1.8:21229'; probeUrl = 'http://192.168.1.8:21229/json/version'; playwrightCommand = 'playwright-cli attach --cdp=http://192.168.1.8:21229'; agentPrompt = 'LAN prompt' })
            sshConfigurations = @([pscustomobject]@{ name = 'remote'; sshCommand = 'ssh -L 21229:127.0.0.1:21229 host'; agentPrompt = 'SSH prompt'; endpoint = 'http://127.0.0.1:21229'; probeUrl = 'http://127.0.0.1:21229/json/version'; playwrightCommand = 'playwright-cli attach --cdp=http://127.0.0.1:21229' })
        }
        $html = ConvertTo-BrowserDebugGuideHtml -Snapshot $snapshot
        $html | Should -Match 'class="app-header"'
        $html | Should -Match 'browser-debug.*edge-debug'
        $html | Should -Match 'class="status-grid"'
        $html | Should -Match 'class="[^"]*quick-connect[^"]*"'
        $html | Should -Match 'class="scenario-section lan-section"'
        $html | Should -Match 'class="scenario-section ssh-section"'
        $html | Should -Match 'class="scenario-section agent-section"'
        $html | Should -Match 'class="status-dot"'
        $html | Should -Match 'class="copy-button"[^>]+aria-label="复制'
        $html | Should -Match 'class="copy-button"[^>]+title="复制'
        $html | Should -Match '<svg[^>]+aria-hidden="true"[^>]*><use href="#icon-copy"'
        $html | Should -Match 'id="icon-copy"|id="icon-check"'
        $html | Should -Match 'role="status" aria-live="polite"'
        $html | Should -Match ':focus-visible'
        $html | Should -Match 'prefers-reduced-motion:reduce'
        $html | Should -Match '@media\(max-width:720px\)'
        $html | Should -Match 'overflow-wrap:anywhere'
        $html | Should -Match 'body\{[^}]*display:flex[^}]*justify-content:center'
        $html | Should -Match '\.shell\{[^}]*flex:0 1 1180px[^}]*min-width:0'
        $html | Should -Match '\.app-header\{[^}]*text-align:center'
        $html | Should -Match '\.brand-line\{[^}]*justify-content:center'
        $html | Should -Match 'main\{text-align:left\}'
        $html | Should -Match '@media\(max-width:720px\)\{\.brand-line\{align-items:center\}\}'
        $html | Should -Match '@media\(max-width:440px\)\{\.running-badge\{align-self:center\}\}'
        $html | Should -Match '\.running-badge\{align-self:center\}'
        $html | Should -Match '#[0-9a-fA-F]{6}'
        $html | Should -Not -Match 'border-radius:(?:9|[1-9][0-9]+)px'
        $html | Should -Not -Match 'gradient|@import|<(?:link|script)[^>]+(?:href|src)='
        $html | Should -Match 'window\.isSecureContext'
        $html | Should -Match "execCommand\('copy'\)"
    }

    It '使用目标浏览器与同一 user-data-dir 打开 file 指南' {
        $profile = [pscustomobject]@{ browserPath = 'C:\Browser\edge.exe'; profilePath = 'C:\Profiles\demo' }
        $guidePath = Join-Path $TestDrive 'guides/demo-local.html'
        New-Item -ItemType Directory -Path (Split-Path -Parent $guidePath) -Force | Out-Null
        Set-Content -LiteralPath $guidePath -Value '<html></html>'
        Mock Start-BrowserDebugDetachedProcess { [pscustomobject]@{ Id = 1 } }
        Open-BrowserDebugGuide -Profile $profile -GuidePath $guidePath | Out-Null
        Should -Invoke Start-BrowserDebugDetachedProcess -ParameterFilter {
            $FilePath -eq 'C:\Browser\edge.exe' -and
            $Arguments -contains '--user-data-dir=C:\Profiles\demo' -and
            @($Arguments | Where-Object { $_ -like 'file://*demo-local.html' }).Count -eq 1
        }
    }

    It '浏览器未返回进程时把打开失败交给 warning 降级层' {
        $profile = [pscustomobject]@{ browserPath = 'C:\Browser\edge.exe'; profilePath = 'C:\Profiles\demo' }
        Mock Start-BrowserDebugDetachedProcess { $null }
        { Open-BrowserDebugGuide -Profile $profile -GuidePath (Join-Path $TestDrive 'guides/demo-local.html') } | Should -Throw '*未返回可用*'
    }
}

Describe 'browser-debug SSH 交接与生命周期' {
    BeforeEach {
        $script:RegistryPath = Join-Path $TestDrive 'registry.json'
        $registry = New-BrowserDebugRegistry
        $registry.profiles = @([pscustomobject]@{ name = 'demo'; cdpPort = 9333 })
        Write-BrowserDebugRegistry -RegistryPath $script:RegistryPath -Registry $registry | Out-Null
    }

    It 'local-forward 的命令、endpoint、Playwright 和 Prompt 保持一致' {
        Invoke-BrowserDebugSshCreate -Name local -Options ([ordered]@{ profile = 'demo'; direction = 'local-forward'; target = 'windows-host'; 'agent-port' = '9555' }) -RegistryPath $script:RegistryPath | Out-Null
        $info = Invoke-BrowserDebugSshInfo -Name local -RegistryPath $script:RegistryPath
        $info.sshCommand | Should -Match '-L 9555:127\.0\.0\.1:9333 windows-host'
        $info.endpoint | Should -Be 'http://127.0.0.1:9555'
        $info.playwrightCommand | Should -Be 'playwright-cli attach --cdp=http://127.0.0.1:9555'
        $info.agentPrompt | Should -Match '不要创建新的浏览器实例'
        { Invoke-BrowserDebugSshStart -Name local -RegistryPath $script:RegistryPath } | Should -Throw '*不由 Windows 启动*'
    }

    It 'reverse-forward 独立启动并保存 PID，不操作浏览器' {
        Invoke-BrowserDebugSshCreate -Name reverse -Options ([ordered]@{ profile = 'demo'; direction = 'reverse-forward'; target = 'agent-host'; 'agent-port' = '9666' }) -RegistryPath $script:RegistryPath | Out-Null
        Mock Start-BrowserDebugSshProcess { 4321 }
        Mock Get-BrowserDebugSshProcess { $null }
        Mock Start-BrowserDebugProfileProcess { throw '不应启动浏览器' }
        $result = Invoke-BrowserDebugSshStart -Name reverse -RegistryPath $script:RegistryPath
        $result.processId | Should -Be 4321
        (Invoke-BrowserDebugSshGet -Name reverse -RegistryPath $script:RegistryPath).reverseProcessId | Should -Be 4321
        Should -Invoke Start-BrowserDebugProfileProcess -Times 0
    }

    It 'reverse-forward registry 写入失败时停止刚启动且仍归属本配置的 SSH' {
        Invoke-BrowserDebugSshCreate -Name reverse -Options ([ordered]@{ profile = 'demo'; direction = 'reverse-forward'; target = 'agent-host'; 'agent-port' = '9666' }) -RegistryPath $script:RegistryPath | Out-Null
        Mock Start-BrowserDebugSshProcess { 4321 }
        Mock Get-BrowserDebugSshProcess { [pscustomobject]@{ CommandLine = 'ssh.exe -4 -N -o ExitOnForwardFailure=yes -R 9666:127.0.0.1:9333 agent-host' } }
        Mock Write-BrowserDebugRegistry { throw 'registry failed' }
        Mock Stop-Process {}
        { Invoke-BrowserDebugSshStart -Name reverse -RegistryPath $script:RegistryPath } | Should -Throw '*registry failed*'
        Should -Invoke Stop-Process -Times 1 -ParameterFilter { $Id -eq 4321 }
    }

    It 'ssh set 对陈旧或复用 PID 清理记录但不停止未知进程' {
        Invoke-BrowserDebugSshCreate -Name reverse -Options ([ordered]@{ profile = 'demo'; direction = 'reverse-forward'; target = 'agent-host'; 'agent-port' = '9666' }) -RegistryPath $script:RegistryPath | Out-Null
        $registry = Read-BrowserDebugRegistry -RegistryPath $script:RegistryPath
        $registry.sshConfigurations[0].reverseProcessId = 9876
        Write-BrowserDebugRegistry -RegistryPath $script:RegistryPath -Registry $registry | Out-Null
        Mock Get-BrowserDebugSshProcess { [pscustomobject]@{ CommandLine = 'ssh.exe other-host' } }
        Mock Stop-Process {}
        $updated = Invoke-BrowserDebugSshSet -Name reverse -Options ([ordered]@{ target = 'new-agent' }) -RegistryPath $script:RegistryPath
        $updated.reverseProcessId | Should -BeNullOrEmpty
        $updated.target | Should -Be 'new-agent'
        Should -Invoke Stop-Process -Times 0
    }

    It 'stop 遇到未知 SSH PID 所有者时拒绝终止' {
        Invoke-BrowserDebugSshCreate -Name reverse -Options ([ordered]@{ profile = 'demo'; direction = 'reverse-forward'; target = 'agent-host'; 'agent-port' = '9666' }) -RegistryPath $script:RegistryPath | Out-Null
        $registry = Read-BrowserDebugRegistry -RegistryPath $script:RegistryPath
        $registry.sshConfigurations[0].reverseProcessId = 9876
        Write-BrowserDebugRegistry -RegistryPath $script:RegistryPath -Registry $registry | Out-Null
        Mock Get-BrowserDebugSshProcess { [pscustomobject]@{ CommandLine = 'ssh.exe other-host' } }
        Mock Stop-Process {}
        { Invoke-BrowserDebugSshStop -Name reverse -RegistryPath $script:RegistryPath } | Should -Throw '*未知 SSH 进程*'
        Should -Invoke Stop-Process -Times 0
    }

    It 'SSH 所有权要求完整参数集合和 target 均匹配' {
        $configuration = [pscustomobject]@{ name = 'reverse'; direction = 'reverse-forward'; target = 'agent-host'; agentPort = 9666; sshConfigPath = 'C:\ssh config'; verboseLogging = $true }
        $profile = [pscustomobject]@{ name = 'demo'; cdpPort = 9333 }
        $info = New-BrowserDebugSshInfo -Configuration $configuration -Profile $profile
        $ownedCommandLine = 'ssh.exe -4 -N -o ExitOnForwardFailure=yes -vv -F "C:\ssh config" -R 9666:127.0.0.1:9333 agent-host'
        Test-BrowserDebugSshProcessOwnership -Process ([pscustomobject]@{ CommandLine = $ownedCommandLine }) -Info $info | Should -BeTrue
        Test-BrowserDebugSshProcessOwnership -Process ([pscustomobject]@{ CommandLine = $ownedCommandLine.Replace('-N ', '') }) -Info $info | Should -BeFalse
        Test-BrowserDebugSshProcessOwnership -Process ([pscustomobject]@{ CommandLine = $ownedCommandLine.Replace('agent-host', 'other-host') }) -Info $info | Should -BeFalse
    }
}
