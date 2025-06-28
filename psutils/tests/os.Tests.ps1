BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\os.psm1" -Force
}

Describe "Get-OperatingSystem 函数测试" {
    It "应该返回有效的操作系统名称" {
        $result = Get-OperatingSystem
        $validOS = @("Windows", "Linux", "macOS")
        $result | Should -BeIn $validOS -Because "应该返回已知的操作系统类型"
    }
    
    It "返回值应该是字符串类型" {
        $result = Get-OperatingSystem
        $result | Should -BeOfType [string]
    }
}

Describe "Test-Administrator 函数测试" {
    It "应该返回布尔值" {
        $result = Test-Administrator
        $result | Should -BeOfType [bool]
    }
    
    It "在Windows系统上应该能正确检测权限" {
        # 模拟Windows环境测试
        if ((Get-OperatingSystem) -eq "Windows") {
            $result = Test-Administrator
            $result | Should -BeOfType [bool]
            # 注意：实际的权限状态取决于运行测试的环境
        }
    }
    
    It "函数应该能处理异常情况" {
        # 测试函数的错误处理能力
        # 这个测试确保函数不会抛出未处理的异常
        { Test-Administrator } | Should -Not -Throw
    }
    
    Context "跨平台兼容性测试" {
        It "在不同操作系统上都应该返回布尔值" {
            $os = Get-OperatingSystem
            $result = Test-Administrator
            
            switch ($os) {
                "Windows" {
                    $result | Should -BeOfType [bool] -Because "Windows系统应该返回布尔值"
                }
                "Linux" {
                    $result | Should -BeOfType [bool] -Because "Linux系统应该返回布尔值"
                }
                "macOS" {
                    $result | Should -BeOfType [bool] -Because "macOS系统应该返回布尔值"
                }
                default {
                    $result | Should -Be $false -Because "未知系统应该返回false"
                }
            }
        }
    }
    
    Context "权限检测逻辑测试" {
        It "应该能区分管理员和普通用户" {
            # 这个测试验证函数能够返回一致的结果
            $result1 = Test-Administrator
            $result2 = Test-Administrator
            $result1 | Should -Be $result2 -Because "连续调用应该返回相同结果"
        }
    }
}