Set-StrictMode -Version Latest

BeforeAll {
    $script:ProfileRootDir = Join-Path $PSScriptRoot '..' 'profile'
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
