Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:DownloadScriptPath = Join-Path $script:RepoRoot 'scripts/pwsh/download/Install-GitHubCli.ps1'
    $script:OriginalSkipMainFlag = [Environment]::GetEnvironmentVariable('GITHUB_CLI_DOWNLOAD_SKIP_MAIN', 'Process')
    $env:GITHUB_CLI_DOWNLOAD_SKIP_MAIN = '1'
    . $script:DownloadScriptPath
}

AfterAll {
    if ($null -eq $script:OriginalSkipMainFlag) {
        Remove-Item Env:\GITHUB_CLI_DOWNLOAD_SKIP_MAIN -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable('GITHUB_CLI_DOWNLOAD_SKIP_MAIN', $script:OriginalSkipMainFlag, 'Process')
    }

    foreach ($functionName in @(
            'ConvertTo-GitHubCliHashtable',
            'Get-GitHubCliConfigValue',
            'Resolve-GitHubCliDefaultConfigPath',
            'Resolve-GitHubCliEnvPlaceholder',
            'Resolve-GitHubCliPath',
            'New-GitHubCliPlatform',
            'Resolve-GitHubCliPlatformValue',
            'Read-GitHubCliDownloadConfig',
            'Resolve-GitHubCliExecutableName',
            'Resolve-GitHubCliInstallDir',
            'Resolve-GitHubCliDownloadSpecs',
            'New-GitHubCliDownloadArguments',
            'Get-GitHubCliArchiveKind',
            'Get-GitHubCliDownloadedAsset',
            'Expand-GitHubCliArchive',
            'Find-GitHubCliExecutableCandidate',
            'Install-GitHubCliExecutable',
            'Test-GitHubCliDirectoryInPath',
            'Get-GitHubCliPathHint'
        )) {
        Remove-Item -Path ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
    }
}

Describe 'GitHub CLI 下载配置解析' {
    It '能按当前平台生成 betterleaks 安装计划' {
        $configPath = Join-Path $TestDrive 'github-cli.config.json'
        Set-Content -LiteralPath $configPath -Encoding utf8NoBOM -Value @'
{
  "download_dir": ".cache/github-cli",
  "install_dirs": {
    "windows": ".bin/windows",
    "linux": ".bin/linux",
    "macos": ".bin/macos"
  },
  "tools": [
    {
      "name": "betterleaks",
      "repo": "betterleaks/betterleaks",
      "tag": "latest",
      "executable": "betterleaks",
      "asset_patterns": {
        "windows-x64": "betterleaks_*_windows_x64.zip",
        "linux-x64": "betterleaks_*_linux_x64.tar.gz",
        "macos-x64": "betterleaks_*_darwin_x64.tar.gz"
      }
    }
  ]
}
'@
        $config = Read-GitHubCliDownloadConfig -ConfigPath $configPath
        $platform = New-GitHubCliPlatform -OperatingSystem linux -Architecture x64

        $specs = Resolve-GitHubCliDownloadSpecs -Config $config -Platform $platform

        $specs | Should -HaveCount 1
        $specs[0].Name | Should -Be 'betterleaks'
        $specs[0].Repo | Should -Be 'betterleaks/betterleaks'
        $specs[0].Tag | Should -Be 'latest'
        $specs[0].AssetPattern | Should -Be 'betterleaks_*_linux_x64.tar.gz'
        $specs[0].ExecutableName | Should -Be 'betterleaks'
        $specs[0].InstallDirectory | Should -Be (Join-Path $TestDrive '.bin/linux')
        $specs[0].DownloadDirectory | Should -Be (Join-Path $TestDrive '.cache/github-cli')
    }

    It 'Windows 平台会为默认可执行文件名补充 .exe' {
        $tool = @{
            name       = 'betterleaks'
            executable = 'betterleaks'
        }
        $platform = New-GitHubCliPlatform -OperatingSystem windows -Architecture x64

        $name = Resolve-GitHubCliExecutableName -Tool $tool -Platform $platform

        $name | Should -Be 'betterleaks.exe'
    }

    It '命令行 DownloadDir 覆盖 JSON 下载目录' {
        $configPath = Join-Path $TestDrive 'github-cli.config.json'
        Set-Content -LiteralPath $configPath -Encoding utf8NoBOM -Value @'
{
  "download_dir": ".json-cache",
  "tools": [
    {
      "name": "betterleaks",
      "repo": "betterleaks/betterleaks",
      "asset_patterns": {
        "linux-x64": "betterleaks_*_linux_x64.tar.gz"
      }
    }
  ]
}
'@

        $config = Read-GitHubCliDownloadConfig -ConfigPath $configPath -CliParameters @{ DownloadDir = '.cli-cache' }
        $spec = Resolve-GitHubCliDownloadSpecs -Config $config -Platform (New-GitHubCliPlatform -OperatingSystem linux -Architecture x64)

        $spec[0].DownloadDirectory | Should -Be (Join-Path $TestDrive '.cli-cache')
    }

    It '生成 latest release 下载参数时不传 tag' {
        $spec = [pscustomobject]@{
            Repo         = 'betterleaks/betterleaks'
            Tag          = 'latest'
            AssetPattern = 'betterleaks_*_linux_x64.tar.gz'
        }

        $arguments = New-GitHubCliDownloadArguments -Spec $spec -Destination '/tmp/download'

        $arguments | Should -Be @(
            'release',
            'download',
            '--repo',
            'betterleaks/betterleaks',
            '--pattern',
            'betterleaks_*_linux_x64.tar.gz',
            '--dir',
            '/tmp/download',
            '--clobber'
        )
    }
}

Describe 'GitHub CLI 解压与安装逻辑' {
    It '能从 zip 包解压并安装 CLI' {
        $sourceDir = Join-Path $TestDrive 'source'
        $archivePath = Join-Path $TestDrive 'tool.zip'
        $extractDir = Join-Path $TestDrive 'extract'
        $installDir = Join-Path $TestDrive 'bin'
        New-Item -ItemType Directory -Path (Join-Path $sourceDir 'nested') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sourceDir 'nested/tool') -Encoding utf8NoBOM -Value '#!/bin/sh'
        Compress-Archive -Path (Join-Path $sourceDir '*') -DestinationPath $archivePath

        Expand-GitHubCliArchive -ArchivePath $archivePath -Destination $extractDir
        $candidate = Find-GitHubCliExecutableCandidate -ExtractDirectory $extractDir -ExecutableName 'tool'
        $result = Install-GitHubCliExecutable -SourcePath $candidate -InstallDirectory $installDir -ExecutableName 'tool' -Platform (New-GitHubCliPlatform -OperatingSystem linux -Architecture x64)

        $result.Status | Should -Be 'Installed'
        Test-Path -LiteralPath (Join-Path $installDir 'tool') | Should -BeTrue
    }

    It '指定 NoOverwrite 时跳过已有目标文件' {
        $sourcePath = Join-Path $TestDrive 'new-tool'
        $installDir = Join-Path $TestDrive 'bin'
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Set-Content -LiteralPath $sourcePath -Encoding utf8NoBOM -Value 'new'
        Set-Content -LiteralPath (Join-Path $installDir 'tool') -Encoding utf8NoBOM -Value 'old'

        $result = Install-GitHubCliExecutable `
            -SourcePath $sourcePath `
            -InstallDirectory $installDir `
            -ExecutableName 'tool' `
            -Platform (New-GitHubCliPlatform -OperatingSystem linux -Architecture x64) `
            -NoOverwrite

        $result.Status | Should -Be 'Skipped'
        (Get-Content -LiteralPath (Join-Path $installDir 'tool') -Raw).Trim() | Should -Be 'old'
    }

    It '能检测安装目录是否已经在 PATH 中' {
        $installDir = Join-Path $TestDrive 'bin'
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        $pathValue = (Join-Path $TestDrive 'other') + [IO.Path]::PathSeparator + $installDir

        $inPath = Test-GitHubCliDirectoryInPath `
            -Directory $installDir `
            -Platform (New-GitHubCliPlatform -OperatingSystem linux -Architecture x64) `
            -PathValue $pathValue

        $inPath | Should -BeTrue
    }

    It '按平台输出 PATH 添加提示' {
        $windowsHint = Get-GitHubCliPathHint -InstallDirectory 'C:\Users\me\.local\bin' -Platform (New-GitHubCliPlatform -OperatingSystem windows -Architecture x64)
        $linuxHint = Get-GitHubCliPathHint -InstallDirectory '/home/me/.local/bin' -Platform (New-GitHubCliPlatform -OperatingSystem linux -Architecture x64)
        $macHint = Get-GitHubCliPathHint -InstallDirectory '/Users/me/.local/bin' -Platform (New-GitHubCliPlatform -OperatingSystem macos -Architecture arm64)

        ($windowsHint -join "`n") | Should -Match 'SetEnvironmentVariable'
        ($linuxHint -join "`n") | Should -Match '~/.profile'
        ($macHint -join "`n") | Should -Match '~/.zshrc'
    }
}
