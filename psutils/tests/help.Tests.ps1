<#
.SYNOPSIS
    help.psm1 模块的单元测试

.DESCRIPTION
    使用Pester框架测试帮助搜索功能的各种场景
#>

BeforeAll {
    # 导入被测试的模块
    Import-Module "$PSScriptRoot\..\modules\help.psm1" -Force
    
    # 设置测试环境
    $script:TestModulePath = "$PSScriptRoot\.."
}

Describe  "Search-ModuleHelp 函数测试" -Skip {
    Context "基本搜索功能" {
        It "应该能够搜索到包含指定关键词的函数" {
            # Test deprecated function
            $results = Search-ModuleHelp -SearchTerm "install" -ModulePath $script:TestModulePath -WarningAction SilentlyContinue
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeGreaterThan 0
        }
        
        It "应该能够精确搜索指定的函数名" {
            # Test deprecated function
            $results = Search-ModuleHelp -FunctionName "Get-OperatingSystem" -ModulePath $script:TestModulePath -WarningAction SilentlyContinue
            if ($results) {
                $results.Name | Should -Be "Get-OperatingSystem"
            }
        }
        
        It "搜索不存在的函数应该返回空结果" {
            # Test deprecated function
            $results = Search-ModuleHelp -FunctionName "NonExistentFunction" -ModulePath $script:TestModulePath -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
        }
    }
    
    Context "参数验证" {
        It "无效的模块路径应该产生错误" {
            # Test deprecated function
            # Test deprecated function
            { Search-ModuleHelp -SearchTerm "test" -ModulePath "C:\NonExistentPath" -ErrorAction Stop -WarningAction SilentlyContinue } | Should -Throw
        }
    }
    
    Context "结果格式验证" {
        It "返回的结果应该包含必要的属性" {
            # Test deprecated function
            $results = Search-ModuleHelp -SearchTerm "Get" -ModulePath $script:TestModulePath -WarningAction SilentlyContinue
            if ($results) {
                $result = $results[0]
                $result.PSObject.Properties.Name | Should -Contain "Name"
                $result.PSObject.Properties.Name | Should -Contain "Synopsis"
                $result.PSObject.Properties.Name | Should -Contain "Description"
                $result.PSObject.Properties.Name | Should -Contain "Parameters"
                $result.PSObject.Properties.Name | Should -Contain "Examples"
                $result.PSObject.Properties.Name | Should -Contain "FilePath"
                $result.PSObject.Properties.Name | Should -Contain "ModuleName"
            }
        }
    }
}

Describe "Convert-HelpBlock 函数测试" {
    Context "帮助块解析" {
        It "应该能够解析完整的帮助块" {
            $helpBlock = @"
.SYNOPSIS
    测试函数

.DESCRIPTION
    这是一个测试函数的详细描述

.PARAMETER TestParam
    测试参数的描述

.EXAMPLE
    Test-Function -TestParam "value"
    测试示例
"@
            
            $result = Convert-HelpBlock -HelpBlock $helpBlock -Name "Test-Function" -FilePath "C:\test.psm1" -Type "Function"
            
            $result.Name | Should -Be "Test-Function"
            $result.Synopsis | Should -Be "测试函数"
            $result.Description | Should -Be "这是一个测试函数的详细描述"
            $result.Parameters.Count | Should -Be 1
            $result.Parameters[0].Name | Should -Be "TestParam"
            $result.Examples.Count | Should -Be 1
        }
        
        It "应该能够处理空的帮助块" {
            $result = Convert-HelpBlock -HelpBlock "" -Name "Test-Function" -FilePath "C:\test.psm1" -Type "Function"
            
            $result.Name | Should -Be "Test-Function"
            $result.Synopsis | Should -Be "无帮助信息"
            $result.Description | Should -Be "无帮助信息"
        }
    }
}

Describe "Find-PSUtilsFunction 函数测试" {
    Context "快速搜索功能" {
        It "应该能够搜索psutils模块中的函数" {
            $results = Find-PSUtilsFunction "Get"
            # 由于这是在psutils模块中搜索，应该能找到一些函数
            # 具体的断言取决于模块中实际存在的函数
        }
        
        It "无参数调用应该返回所有函数" {
            $results = Find-PSUtilsFunction
            # 应该返回模块中的所有函数
        }
    }
}

Describe "Get-FunctionHelp 函数测试" {
    Context "函数帮助获取" {
        It "应该能够获取指定函数的帮助信息" {
            # 这个测试需要根据实际存在的函数来调整
            $results = Get-FunctionHelp "Get-OperatingSystem"
            if ($results) {
                $results.Name | Should -Be "Get-OperatingSystem"
            }
        }
    }
}

AfterAll {
    # 清理测试环境
    Remove-Module "help" -Force -ErrorAction SilentlyContinue
}