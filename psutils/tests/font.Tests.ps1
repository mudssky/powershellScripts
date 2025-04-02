BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\font.psm1" -Force
}

Describe "Test-Font 函数测试" {
    It "检测已安装字体返回true" {
        # 假设'Arial'是系统已安装字体
        Test-Font -Name "Arial" | Should -Be $true
    }

    It "检测未安装字体返回false" {
        Test-Font -Name "NonexistentFont" | Should -Be $false
    }
}