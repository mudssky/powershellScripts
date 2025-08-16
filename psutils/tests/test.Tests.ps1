BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\test.psm1" -Force
}

Describe "Test-EXEProgram 函数测试" {
    It "检测存在的可执行程序返回true" {
        Test-EXEProgram -Name "powershell" | Should -Be $true
    }

    It "检测不存在的可执行程序返回false" {
        Test-EXEProgram -Name "nonexistentprogram" | Should -Be $false
    }
}

Describe "Test-ArrayNotNull 函数测试" {
    It "非空数组返回true" {
        Test-ArrayNotNull -array @(1, 2, 3) | Should -Be $true
    }

    It "空数组返回false" {
        Test-ArrayNotNull -array @() | Should -Be $false
    }

    It "null值返回false" {
        Test-ArrayNotNull -array $null | Should -Be $false
    }
}

Describe "Test-PathHasExe 函数测试" {
    BeforeAll {
        $testDir = "$TestDrive\testdir"
        New-Item -ItemType Directory -Path $testDir
        $testExe = "$testDir\test.exe"
        "" | Out-File -FilePath $testExe -Encoding utf8
    }

    It "路径包含exe文件时返回true" {
        Test-PathHasExe -Path $testDir | Should -Be $true
    }

    It "路径不包含exe文件时返回false" {
        Test-PathHasExe -Path "$TestDrive\nonexistent" | Should -Be $false
    }
}