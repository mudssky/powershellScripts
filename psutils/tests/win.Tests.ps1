BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\win.psm1" -Force
}

Describe "Add-Startup 函数测试" -Tag 'windowsOnly' {
    It "应该设置默认 LinkName 为文件名" {
        if (-not $IsWindows) {
            Set-ItResult -Skipped -Because "仅 Windows 环境"
            return
        }
        Mock -ModuleName win New-Item { }
        Mock -ModuleName win Write-Host { }

        { Add-Startup -Path "C:\Program Files\Test\app.exe" } | Should -Not -Throw
    }

    It "应该使用自定义 LinkName" {
        if (-not $IsWindows) {
            Set-ItResult -Skipped -Because "仅 Windows 环境"
            return
        }
        Mock -ModuleName win New-Item { }
        Mock -ModuleName win Write-Host { }

        { Add-Startup -Path "C:\Test\app.exe" -LinkName "MyApp" } | Should -Not -Throw
    }
}

Describe "New-Shortcut 函数测试" -Tag 'windowsOnly' {
    It "应该在 Windows 上成功创建快捷方式" {
        if (-not $IsWindows) {
            Set-ItResult -Skipped -Because "仅 Windows 环境"
            return
        }

        # Mock COM 对象以避免 TestDrive 路径上 WScript.Shell 的兼容性问题
        $mockShortcut = [PSCustomObject]@{
            TargetPath       = ''
            Arguments        = ''
            WorkingDirectory = ''
            IconLocation     = ''
        }
        $mockShortcut | Add-Member -MemberType ScriptMethod -Name Save -Value { }
        $mockWshShell = [PSCustomObject]@{}
        $mockWshShell | Add-Member -MemberType ScriptMethod -Name CreateShortcut -Value { param($path) $mockShortcut }

        Mock -ModuleName win New-Object { $mockWshShell } -ParameterFilter { $ComObject -eq 'WScript.Shell' }

        $testTarget = "$TestDrive\target.txt"
        "" | Out-File -FilePath $testTarget -Encoding utf8
        $testShortcut = "$TestDrive\shortcut.lnk"

        { New-Shortcut -TargetPath $testTarget -ShortcutPath $testShortcut } | Should -Not -Throw
    }
}
