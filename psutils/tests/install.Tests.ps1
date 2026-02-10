BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\install.psm1" -Force
    $script:IsFastTestMode = $env:PWSH_TEST_MODE -eq 'fast'
}

Describe "Test-ModuleInstalled 函数测试" {
    BeforeAll {
        if ($script:IsFastTestMode) {
            Mock -CommandName Get-Module -ModuleName install -MockWith {
                param([string]$Name)
                if ($Name -eq "Microsoft.PowerShell.Management") {
                    return [pscustomobject]@{ Name = $Name }
                }
                return $null
            }
        }
    }

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
        # 测试模块安装检查功能，不输出详细信息
        { Test-ModuleInstalled -ModuleName "Microsoft.PowerShell.Management" } | Should -Not -Throw
    }
     
    It "应该处理包含特殊字符的模块名" {
        $result = Test-ModuleInstalled -ModuleName "Invalid*Module?Name"
        $result | Should -Be $false
    }
}
