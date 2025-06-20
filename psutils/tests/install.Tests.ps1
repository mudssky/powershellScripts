BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\install.psm1" -Force
}

Describe "Test-ModuleInstalled 函数测试" {
    It "应该能够检测已安装的模块" {
        # 测试一个通常已安装的核心模块
        $result = Test-ModuleInstalled -ModuleName "Microsoft.PowerShell.Management"
        $result | Should -Be $true
    }
    
    It "应该能够检测未安装的模块" {
        # 测试一个不存在的模块
        $result = Test-ModuleInstalled -ModuleName "NonExistentModule12345"
        $result | Should -Be $false
    }
    
    It "应该支持详细输出" {
        # 测试详细输出模式
        $VerbosePreference = 'Continue'
        { Test-ModuleInstalled -ModuleName "Microsoft.PowerShell.Management" -Verbose } | Should -Not -Throw
        $VerbosePreference = 'SilentlyContinue'
    }
     
    It "应该处理包含特殊字符的模块名" {
        $result = Test-ModuleInstalled -ModuleName "Invalid*Module?Name"
        $result | Should -Be $false
    }
}

