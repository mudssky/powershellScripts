Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:LauncherScriptPath = Join-Path $script:RepoRoot 'scripts/pwsh/devops/project-launcher/main.ps1'
    $script:OriginalSkipProjectLauncherMain = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_PROJECT_LAUNCHER_MAIN', 'Process')
    $env:PWSH_TEST_SKIP_PROJECT_LAUNCHER_MAIN = '1'
    . $script:LauncherScriptPath
    Import-ProjectLauncherDependencies -RepoRoot $script:RepoRoot
}

AfterAll {
    if ($null -eq $script:OriginalSkipProjectLauncherMain) {
        Remove-Item Env:\PWSH_TEST_SKIP_PROJECT_LAUNCHER_MAIN -ErrorAction SilentlyContinue
    }
    else {
        $env:PWSH_TEST_SKIP_PROJECT_LAUNCHER_MAIN = $script:OriginalSkipProjectLauncherMain
    }
}

Describe 'Project launcher catalog' {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
        New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null
        $script:SshConfigPath = Join-Path $script:TestRoot 'ssh_config'
        $script:ConfigPath = Join-Path $script:TestRoot 'launcher.json'
    }

    It 'builds SSH and WSL items while preserving SSH core fields when JSON name matches' {
        Set-Content -Path $script:SshConfigPath -Encoding utf8NoBOM -Value @'
Host proj-srm-trellis
  HostName 192.168.27.77
  User administrator
  Port 32222
  RemoteCommand cd ~/projects/work/hubs/srm-trellis && exec zellij attach -c srm-trellis
'@
        Set-Content -Path $script:ConfigPath -Encoding utf8NoBOM -Value @'
{
  "defaults": {
    "wsl": {
      "distro": "Ubuntu-24.04"
    }
  },
  "entries": [
    {
      "name": "proj-srm-trellis",
      "displayName": "SRM Trellis",
      "hidden": false,
      "tags": ["remote", "work"],
      "command": "should-not-override"
    },
    {
      "name": "wsl-srm-trellis",
      "type": "wsl",
      "workDir": "~/projects/work/hubs/srm-trellis",
      "session": "srm-trellis"
    }
  ]
}
'@

        $config = Read-ProjectLauncherJsonConfig -ConfigPath $script:ConfigPath -BasePath $script:TestRoot
        $sshItems = Get-ProjectLauncherSshItems -SshConfigPath $script:SshConfigPath -IsExplicitPath
        $catalog = New-ProjectLauncherCatalog -SshItems $sshItems -Config $config

        $sshItem = $catalog | Where-Object Name -eq 'proj-srm-trellis' | Select-Object -First 1
        $wslItem = $catalog | Where-Object Name -eq 'wsl-srm-trellis' | Select-Object -First 1

        $sshItem.DisplayName | Should -Be 'SRM Trellis'
        $sshItem.Type | Should -Be 'ssh'
        $sshItem.Raw.HostName | Should -Be '192.168.27.77'
        $sshItem.Raw.RemoteCommand | Should -Be 'cd ~/projects/work/hubs/srm-trellis && exec zellij attach -c srm-trellis'
        $sshItem.CommandSummary | Should -Not -Be 'should-not-override'
        $sshItem.Source | Should -Be 'ssh-config+json'

        $wslItem.Type | Should -Be 'wsl'
        $wslItem.Raw.Distro | Should -Be 'Ubuntu-24.04'
        $wslItem.Raw.Command | Should -Be 'cd ~/projects/work/hubs/srm-trellis && exec zellij attach -c srm-trellis'
    }

    It 'uses entry command and entry distro before zellij fallback defaults' {
        Set-Content -Path $script:ConfigPath -Encoding utf8NoBOM -Value @'
{
  "defaults": {
    "wsl": {
      "distro": "Ubuntu-24.04"
    }
  },
  "entries": [
    {
      "name": "wsl-demo",
      "type": "wsl",
      "distro": "Debian",
      "command": "cd ~/projects/demo && exec zellij attach -c demo"
    }
  ]
}
'@

        $config = Read-ProjectLauncherJsonConfig -ConfigPath $script:ConfigPath -BasePath $script:TestRoot
        $catalog = New-ProjectLauncherCatalog -Config $config
        $item = $catalog | Select-Object -First 1
        $plan = New-ProjectLauncherExecutionPlan -Item $item

        $item.Raw.Distro | Should -Be 'Debian'
        $item.Raw.Command | Should -Be 'cd ~/projects/demo && exec zellij attach -c demo'
        $plan.Executable | Should -Be 'wsl.exe'
        $plan.Arguments | Should -Be @('-d', 'Debian', '--', 'bash', '-lc', 'cd ~/projects/demo && exec zellij attach -c demo')
    }

    It 'adds adjacent local JSON entries without replacing base entries' {
        $baseConfigPath = Join-Path $script:TestRoot 'launcher.json'
        $localConfigPath = Join-Path $script:TestRoot 'launcher.local.json'
        Set-Content -Path $baseConfigPath -Encoding utf8NoBOM -Value @'
{
  "defaults": {
    "wsl": {
      "distro": "Ubuntu-22.04"
    }
  },
  "entries": [
    {
      "name": "wsl-base",
      "type": "wsl",
      "command": "echo base"
    }
  ]
}
'@
        Set-Content -Path $localConfigPath -Encoding utf8NoBOM -Value @'
{
  "defaults": {
    "wsl": {
      "distro": "Ubuntu-24.04"
    }
  },
  "entries": [
    {
      "name": "wsl-local",
      "type": "wsl",
      "command": "echo local"
    }
  ]
}
'@

        $config = Read-ProjectLauncherJsonConfig -ConfigPath $baseConfigPath -BasePath $script:TestRoot
        $catalog = New-ProjectLauncherCatalog -Config $config

        ($catalog | ForEach-Object Name) | Should -Be @('wsl-base', 'wsl-local')
        ($catalog | Where-Object Name -eq 'wsl-base').Raw.Distro | Should -Be 'Ubuntu-24.04'
        ($catalog | Where-Object Name -eq 'wsl-local').Raw.Distro | Should -Be 'Ubuntu-24.04'
    }

    It 'auto-loads default project launcher local JSON from the working directory' {
        Push-Location $script:TestRoot
        try {
            Set-Content -Path (Join-Path $script:TestRoot 'project-launcher.local.json') -Encoding utf8NoBOM -Value @'
{
  "defaults": {
    "wsl": {
      "distro": "Ubuntu-24.04"
    }
  },
  "entries": [
    {
      "name": "wsl-auto-local",
      "type": "wsl",
      "command": "echo auto"
    }
  ]
}
'@

            $config = Read-ProjectLauncherJsonConfig -BasePath (Get-Location).Path
            $catalog = New-ProjectLauncherCatalog -Config $config
        }
        finally {
            Pop-Location
        }

        @($catalog).Count | Should -Be 1
        $catalog[0].Name | Should -Be 'wsl-auto-local'
        $catalog[0].Raw.Distro | Should -Be 'Ubuntu-24.04'
    }

    It 'filters WSL entries on non-Windows platforms' {
        $items = @(
            [PSCustomObject]@{ Name = 'remote'; Type = 'ssh' },
            [PSCustomObject]@{ Name = 'wsl-demo'; Type = 'wsl' }
        )

        $filtered = Filter-ProjectLauncherItemsForPlatform -Items $items -Platform 'linux'

        @($filtered).Count | Should -Be 1
        $filtered[0].Name | Should -Be 'remote'
    }

    It 'skips invalid WSL JSON entries before validation on non-Windows platforms' {
        Set-Content -Path $script:SshConfigPath -Encoding utf8NoBOM -Value @'
Host remote
  HostName remote.example
'@
        Set-Content -Path $script:ConfigPath -Encoding utf8NoBOM -Value @'
{
  "entries": [
    {
      "name": "wsl-missing-distro",
      "type": "wsl",
      "workDir": "~/demo",
      "session": "demo"
    },
    {
      "type": "wsl",
      "command": "echo should-be-filtered"
    }
  ]
}
'@

        $config = Read-ProjectLauncherJsonConfig -ConfigPath $script:ConfigPath -BasePath $script:TestRoot
        $sshItems = Get-ProjectLauncherSshItems -SshConfigPath $script:SshConfigPath -IsExplicitPath
        $catalog = New-ProjectLauncherCatalog -SshItems $sshItems -Config $config -Platform 'linux'

        @($catalog).Count | Should -Be 1
        $catalog[0].Name | Should -Be 'remote'
    }

    It 'returns null selected item when interactive selection is cancelled' {
        $items = @(
            [PSCustomObject]@{
                Name           = 'remote'
                Type           = 'ssh'
                DisplayName    = 'remote'
                Target         = 'remote.example'
                CommandSummary = ''
            }
        )

        Mock Select-InteractiveItem { return $null }

        $selected = Resolve-ProjectLauncherItem -Items $items

        $selected | Should -BeNullOrEmpty
        Should -Invoke Select-InteractiveItem -Times 1
    }

    It 'dry-run returns the execution plan without invoking native commands' {
        $item = [PSCustomObject]@{
            Name = 'remote'
            Type = 'ssh'
            DisplayName = 'remote'
            Raw  = [PSCustomObject]@{
                RequestTTY = $null
            }
        }
        $plan = New-ProjectLauncherExecutionPlan -Item $item

        $result = Invoke-ProjectLauncherExecutionPlan -Plan $plan -DryRun

        $result.ExitCode | Should -Be 0
        $result.DryRun | Should -BeTrue
        $result.Detached | Should -BeFalse
        $result.Plan.CommandLine | Should -Be 'ssh -tt remote'
    }

    It 'does not force SSH TTY when RequestTTY is explicitly disabled' {
        $item = [PSCustomObject]@{
            Name = 'remote-no-tty'
            Type = 'ssh'
            Raw  = [PSCustomObject]@{
                RequestTTY = 'no'
            }
        }

        $plan = New-ProjectLauncherExecutionPlan -Item $item

        $plan.Arguments | Should -Be @('remote-no-tty')
        $plan.CommandLine | Should -Be 'ssh remote-no-tty'
    }

    It 'prints the command line before invoking native commands' {
        $plan = [PSCustomObject]@{
            Executable  = 'Write-Output'
            Arguments   = @('native-result')
            CommandLine = 'Write-Output native-result'
        }
        Mock Write-Host {}

        $output = Invoke-ProjectLauncherExecutionPlan -Plan $plan

        Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -eq '启动: Write-Output native-result' }
        $output[0] | Should -Be 'native-result'
        $output[-1].DryRun | Should -BeFalse
        $output[-1].Detached | Should -BeFalse
    }

    It 'opens SSH plans in a new terminal by default on Windows' {
        $item = [PSCustomObject]@{
            Name        = 'remote'
            Type        = 'ssh'
            DisplayName = 'Remote Server'
            Raw         = [PSCustomObject]@{
                RequestTTY = $null
            }
        }
        $plan = New-ProjectLauncherExecutionPlan -Item $item
        Mock Resolve-ProjectLauncherWindowsTerminalPath { 'C:\Users\demo\AppData\Local\Microsoft\WindowsApps\wt.exe' }
        Mock New-ProjectLauncherTerminalScriptFile { 'C:\Temp\project-launcher-demo.ps1' }
        Mock Start-ProjectLauncherNativeProcess { 1234 }
        Mock Write-Host {}

        $result = Invoke-ProjectLauncherExecutionPlan -Plan $plan -Platform 'windows'

        $result.ExitCode | Should -Be 0
        $result.DryRun | Should -BeFalse
        $result.Detached | Should -BeTrue
        $result.TerminalResult.Mode | Should -Be 'windows-terminal'
        $result.TerminalResult.Arguments[0..4] | Should -Be @('-w', '0', 'new-tab', '--title', 'Remote Server')
        $result.TerminalResult.Arguments | Should -Contain '-NoExit'
        $result.TerminalResult.Arguments | Should -Contain '-File'
        $result.TerminalResult.Arguments | Should -Not -Contain '-Command'
        $result.TerminalResult.Arguments[-1] | Should -Be 'C:\Temp\project-launcher-demo.ps1'
        $result.TerminalResult.ScriptPath | Should -Be 'C:\Temp\project-launcher-demo.ps1'
        Should -Invoke Start-ProjectLauncherNativeProcess -Times 1 -ParameterFilter {
            $FilePath -eq 'C:\Users\demo\AppData\Local\Microsoft\WindowsApps\wt.exe' -and
            $ArgumentList[0] -eq '-w' -and
            $ArgumentList[-2] -eq '-File' -and
            $ArgumentList[-1] -eq 'C:\Temp\project-launcher-demo.ps1'
        }
    }

    It 'keeps SSH execution inline when requested' {
        $plan = [PSCustomObject]@{
            Type        = 'ssh'
            Executable  = 'Write-Output'
            Arguments   = @('inline-result')
            CommandLine = 'Write-Output inline-result'
        }
        Mock Start-ProjectLauncherTerminalSession {}
        Mock Write-Host {}

        $output = Invoke-ProjectLauncherExecutionPlan -Plan $plan -Platform 'windows' -Inline

        $output[0] | Should -Be 'inline-result'
        $output[-1].Detached | Should -BeFalse
        Should -Invoke Start-ProjectLauncherTerminalSession -Times 0
    }

    It 'falls back to a PowerShell terminal when Windows Terminal is unavailable' {
        $item = [PSCustomObject]@{
            Name        = 'remote'
            Type        = 'ssh'
            DisplayName = 'remote'
            Raw         = [PSCustomObject]@{
                RequestTTY = $null
            }
        }
        $plan = New-ProjectLauncherExecutionPlan -Item $item
        Mock Resolve-ProjectLauncherWindowsTerminalPath { '' }
        Mock Resolve-ProjectLauncherPowerShellPath { 'C:\Program Files\PowerShell\7\pwsh.exe' }
        Mock New-ProjectLauncherTerminalScriptFile { 'C:\Temp\project-launcher-fallback.ps1' }
        Mock Start-ProjectLauncherNativeProcess { 4321 }

        $result = Start-ProjectLauncherTerminalSession -Plan $plan

        $result.Mode | Should -Be 'powershell'
        $result.FilePath | Should -Be 'C:\Program Files\PowerShell\7\pwsh.exe'
        $result.Arguments | Should -Contain '-NoExit'
        $result.Arguments | Should -Contain '-File'
        $result.Arguments[-1] | Should -Be 'C:\Temp\project-launcher-fallback.ps1'
        $result.ScriptPath | Should -Be 'C:\Temp\project-launcher-fallback.ps1'
        $result.ProcessId | Should -Be 4321
    }

    It 'writes WSL terminal host scripts without exposing commands to wt parsing' {
        $item = [PSCustomObject]@{
            Name        = 'wsl-demo'
            Type        = 'wsl'
            DisplayName = 'WSL Demo'
            Raw         = [PSCustomObject]@{
                Distro  = 'Ubuntu-24.04'
                Command = "cd ~/demo && echo 'hello world'"
            }
        }
        $plan = New-ProjectLauncherExecutionPlan -Item $item

        $script = New-ProjectLauncherTerminalScriptContent -Plan $plan

        $script | Should -BeLike "*& 'wsl.exe' @('-d', 'Ubuntu-24.04', '--', 'bash', '-lc', 'cd ~/demo && echo ''hello world''')*"
        $script | Should -BeLike '*Remove-Item -LiteralPath $PSCommandPath*'
    }

    It 'manifest exposes the directory tool entry' {
        $manifestPath = Join-Path $script:RepoRoot 'scripts/pwsh/devops/project-launcher/tool.psd1'
        $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath

        $manifest.BinName | Should -Be 'Invoke-ProjectLauncher.ps1'
        $manifest.Entry | Should -Be 'main.ps1'
        Test-Path -LiteralPath (Join-Path (Split-Path -Parent $manifestPath) $manifest.Entry) | Should -BeTrue
    }
}
