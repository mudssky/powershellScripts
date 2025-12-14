BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'font.psm1') -Force
}

Describe "Test-Font 函数测试" -Tag 'windows' {
    It "检测已安装字体返回true" {
        if (-not $IsWindows) { Set-ItResult -Skipped -Because 'Windows-only'; return }
        # 假设'Arial'是系统已安装字体
        Test-Font -Name "Arial" | Should -Be $true
    }

    It "检测未安装字体返回false" {
        if (-not $IsWindows) { Set-ItResult -Skipped -Because 'Windows-only'; return }
        Test-Font -Name "NonexistentFont" | Should -Be $false
    }
}
