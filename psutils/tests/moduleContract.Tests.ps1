BeforeAll {
    $script:ModuleRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $script:ManifestPath = Join-Path $script:ModuleRoot 'psutils.psd1'
    $script:LegacyEntryPath = Join-Path $script:ModuleRoot 'index.psm1'
    $script:ManifestData = Import-PowerShellDataFile $script:ManifestPath
    $script:PwshPath = (Get-Process -Id $PID).Path
}

Describe 'psutils 模块入口与导出契约' {
    BeforeEach {
        Remove-Module psutils -Force -ErrorAction SilentlyContinue
    }

    It '声明 PowerShell 7.4+ Core 兼容范围' {
        $script:ManifestData.PowerShellVersion.ToString() | Should -Be '7.4'
        @($script:ManifestData.CompatiblePSEditions) | Should -Be @('Core')
    }

    It 'manifest 导出名称唯一且与实际聚合命令一致' {
        $declaredNames = @($script:ManifestData.FunctionsToExport)
        $uniqueNames = @($declaredNames | Sort-Object -Unique)

        $uniqueNames.Count | Should -Be $declaredNames.Count

        Import-Module $script:ManifestPath -Force
        $actualNames = @(
            Get-Command -Module psutils -CommandType Function |
                Select-Object -ExpandProperty Name |
                Sort-Object -Unique
        )
        $difference = @(Compare-Object -ReferenceObject $uniqueNames -DifferenceObject $actualNames)

        $difference | Should -BeNullOrEmpty
    }

    It '通过目录导入时加载规范 manifest' {
        Import-Module $script:ModuleRoot -Force

        (Get-Module psutils).Path | Should -Be $script:ManifestPath
        Get-Command Get-OperatingSystem -Module psutils | Should -Not -BeNullOrEmpty
    }

    It '旧 index 入口提示弃用并在调用方会话暴露公共命令' {
        $escapedEntryPath = $script:LegacyEntryPath.Replace("'", "''")
        $commandText = @"
`$WarningPreference = 'Continue'
`$warnings = @(& { Import-Module '$escapedEntryPath' -Force } 3>&1)
`$warnings | ForEach-Object { `$_.ToString() }
(Get-Command Get-OperatingSystem -ErrorAction Stop).Name
"@
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($commandText))

        $output = @(& $script:PwshPath -NoProfile -EncodedCommand $encodedCommand 2>&1)
        $exitCode = $LASTEXITCODE
        $outputText = $output -join [Environment]::NewLine

        $exitCode | Should -Be 0
        $outputText | Should -Match '已弃用'
        $outputText | Should -Match 'Get-OperatingSystem'
    }

    It '导出配置 source reader 和默认 env 文件发现函数' {
        Import-Module $script:ManifestPath -Force

        Get-Command Read-ConfigEnvFile -Module psutils | Should -Not -BeNullOrEmpty
        Get-Command Resolve-DefaultEnvFiles -Module psutils | Should -Not -BeNullOrEmpty
    }

    It 'New-Shortcut 只保留权威参数并兼容旧参数名' {
        Import-Module $script:ManifestPath -Force
        $command = Get-Command New-Shortcut -Module psutils

        @($command).Count | Should -Be 1
        $command.Parameters['TargetPath'].Aliases | Should -Contain 'Path'
        $command.Parameters['ShortcutPath'].Aliases | Should -Contain 'Destination'
    }
}

AfterAll {
    Remove-Module psutils -Force -ErrorAction SilentlyContinue
}
