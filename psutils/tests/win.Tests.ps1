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
        $testTarget = "$TestDrive\target.txt"
        "" | Out-File -FilePath $testTarget -Encoding utf8
        $testShortcut = "$TestDrive\shortcut.lnk"

        { New-Shortcut -TargetPath $testTarget -ShortcutPath $testShortcut } | Should -Not -Throw
    }
}
