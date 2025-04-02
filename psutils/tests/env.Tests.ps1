BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\env.psm1" -Force
}

Describe "Get-Dotenv 函数测试" {
    BeforeAll {
        $testEnvContent = @"
KEY1=value1
KEY2=value2
# 注释行
  KEY3=value3  
"@
        $testEnvPath = "$TestDrive\.env"
        $testEnvContent | Out-File -FilePath $testEnvPath -Encoding utf8
    }

    It "正确解析.env文件内容" {
        $result = Get-Dotenv -Path $testEnvPath
        $result.Count | Should -Be 3
        $result["KEY1"] | Should -Be "value1"
        $result["KEY2"] | Should -Be "value2"
        $result["KEY3"] | Should -Be "value3"
    }

    It "忽略注释行" {
        $result = Get-Dotenv -Path $testEnvPath
        $result.ContainsKey("#") | Should -Be $false
    }

    It "处理键值前后的空格" {
        $result = Get-Dotenv -Path $testEnvPath
        $result["KEY3"] | Should -Be "value3"
    }
}

Describe "Install-Dotenv 函数测试" {
    BeforeAll {
        $originalLocation = Get-Location
        $testEnvContent = @"
TEST_KEY=test_value
"@
        $testEnvPath = "$TestDrive\.env"
        $testEnvContent | Out-File -FilePath $testEnvPath -Encoding utf8
    }
    
    AfterAll {
        # 增加复原工作目录的逻辑
        Set-Location $originalLocation
    }

    It "正确加载环境变量到进程级别" {
        Install-Dotenv -Path $testEnvPath -EnvTarget Process
        $env:TEST_KEY | Should -Be "test_value"
    }

    It "处理默认.env文件" {
        $defaultEnvContent = @"
DEFAULT_KEY=default_value
"@
        $defaultEnvPath = "$TestDrive\.env"
        $defaultEnvContent | Out-File -FilePath $defaultEnvPath -Encoding utf8
        Set-Location $TestDrive
        Install-Dotenv -Path "nonexistent_path" -EnvTarget Process
        $env:DEFAULT_KEY | Should -Be "default_value"
    }
}