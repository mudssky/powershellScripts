<#
.SYNOPSIS
    Invoke-WithCache 函数的单元测试

.DESCRIPTION
    使用 Pester 框架测试 Invoke-WithCache 函数的各种功能，包括缓存命中、缓存过期、
    强制刷新、NoCache模式、CacheType参数等场景。

.NOTES
    作者: mudssky
    版本: 1.3.0
    创建日期: 2025-01-07
    最后修改: 2024-12-19
    测试框架: Pester 5.x
    新增功能: CacheType参数测试（XML和Text格式）
#>

BeforeAll {
    # 导入被测试的模块
    $ModulePath = Join-Path $PSScriptRoot ".." "modules" "cache.psm1"
    Import-Module $ModulePath -Force
    
    # 定义测试用的缓存目录
    $script:TestCacheDir = Join-Path $env:LOCALAPPDATA "PowerShellCache"
    
    # 清理函数
    function Clear-TestCache {
        if (Test-Path $script:TestCacheDir) {
            Get-ChildItem $script:TestCacheDir -Filter "*.cache.*" | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

AfterAll {
    # 清理测试缓存
    Clear-TestCache
    
    # 移除导入的模块
    Remove-Module cache -Force -ErrorAction SilentlyContinue
}

Describe "Invoke-WithCache" {
    BeforeEach {
        # 每个测试前清理缓存
        Clear-TestCache
    }
    
    Context "基本功能测试" {
        It "应该能够执行脚本块并返回结果" {
            $result = Invoke-WithCache -Key "test-basic" -ScriptBlock { "Hello World" }
            $result | Should -Be "Hello World"
        }
        
        It "应该创建缓存目录" {
            Invoke-WithCache -Key "test-dir" -ScriptBlock { "test" }
            $script:TestCacheDir | Should -Exist
        }
        
        It "应该创建缓存文件" {
            Invoke-WithCache -Key "test-file" -ScriptBlock { "test" }
            $cacheFiles = Get-ChildItem $script:TestCacheDir -Filter "*.cache.*"
            (@($cacheFiles)).Count | Should -BeGreaterThan 0
        }
    }
    
    Context "缓存命中测试" {
        It "第二次调用应该从缓存返回结果" {
            $script:testCounter = 0
            $scriptBlock = { $script:testCounter++; "Result: $($script:testCounter)" }
            
            # 第一次调用
            $result1 = Invoke-WithCache -Key "test-cache-hit" -ScriptBlock $scriptBlock
            $result1 | Should -Be "Result: 1"
            
            # 第二次调用应该从缓存返回
            $result2 = Invoke-WithCache -Key "test-cache-hit" -ScriptBlock $scriptBlock
            $result2 | Should -Be "Result: 1"  # 应该是相同的结果，不是2
        }
        
        It "不同的Key应该产生不同的缓存" {
            $result1 = Invoke-WithCache -Key "key1" -ScriptBlock { "Value1" }
            $result2 = Invoke-WithCache -Key "key2" -ScriptBlock { "Value2" }
            
            $result1 | Should -Be "Value1"
            $result2 | Should -Be "Value2"
        }
    }
    
    Context "缓存过期测试" {
        It "过期的缓存应该重新执行脚本块" {
            $script:expiryCounter = 0
            $scriptBlock = { $script:expiryCounter++; "Result: $($script:expiryCounter)" }
            
            # 第一次调用，设置很短的过期时间
            $result1 = Invoke-WithCache -Key "test-expiry" -ScriptBlock $scriptBlock -MaxAge ([TimeSpan]::FromMilliseconds(100))
            $result1 | Should -Be "Result: 1"
            
            # 等待缓存过期
            Start-Sleep -Milliseconds 200
            
            # 第二次调用应该重新执行
            $result2 = Invoke-WithCache -Key "test-expiry" -ScriptBlock $scriptBlock -MaxAge ([TimeSpan]::FromMilliseconds(100))
            $result2 | Should -Be "Result: 2"
        }
    }
    
    Context "Force参数测试" {
        It "Force参数应该强制刷新缓存" {
            $script:forceCounter = 0
            $scriptBlock = { $script:forceCounter++; "Result: $($script:forceCounter)" }
            
            # 第一次调用
            $result1 = Invoke-WithCache -Key "test-force" -ScriptBlock $scriptBlock
            $result1 | Should -Be "Result: 1"
            
            # 使用Force参数强制刷新
            $result2 = Invoke-WithCache -Key "test-force" -ScriptBlock $scriptBlock -Force
            $result2 | Should -Be "Result: 2"
        }
    }
    
    Context "NoCache参数测试" {
        It "NoCache参数应该跳过缓存机制" {
            $script:noCacheCounter = 0
            $scriptBlock = { $script:noCacheCounter++; "Result: $($script:noCacheCounter)" }
            
            # 第一次调用使用NoCache
            $result1 = Invoke-WithCache -Key "test-nocache" -ScriptBlock $scriptBlock -NoCache
            $result1 | Should -Be "Result: 1"
            
            # 第二次调用使用NoCache，应该重新执行
            $result2 = Invoke-WithCache -Key "test-nocache" -ScriptBlock $scriptBlock -NoCache
            $result2 | Should -Be "Result: 2"
            
            # 验证没有创建缓存文件
            $cacheFiles = Get-ChildItem $script:TestCacheDir -Filter "*.cache.*" -ErrorAction SilentlyContinue
            (@($cacheFiles)).Count | Should -Be 0
        }
        
        It "NoCache模式后正常模式应该重新创建缓存" {
            $script:normalCounter = 0
            $scriptBlock = { $script:normalCounter++; "Result: $($script:normalCounter)" }
            
            # 使用NoCache模式
            $result1 = Invoke-WithCache -Key "test-nocache-normal" -ScriptBlock $scriptBlock -NoCache
            $result1 | Should -Be "Result: 1"
            
            # 正常模式应该创建缓存
            $result2 = Invoke-WithCache -Key "test-nocache-normal" -ScriptBlock $scriptBlock
            $result2 | Should -Be "Result: 2"
            
            # 第三次调用应该从缓存返回
            $result3 = Invoke-WithCache -Key "test-nocache-normal" -ScriptBlock $scriptBlock
            $result3 | Should -Be "Result: 2"
        }
    }
    
    Context "复杂数据类型测试" {
        It "应该能够缓存复杂对象" {
            $complexObject = @{
                Name   = "Test"
                Values = @(1, 2, 3)
                Nested = @{
                    Property = "Value"
                }
            }
            
            $scriptBlock = { $complexObject }
            
            # 第一次调用
            $result1 = Invoke-WithCache -Key "test-complex" -ScriptBlock $scriptBlock
            $result1.Name | Should -Be "Test"
            $result1.Values | Should -Be @(1, 2, 3)
            $result1.Nested.Property | Should -Be "Value"
            
            # 第二次调用应该从缓存返回相同结构
            $result2 = Invoke-WithCache -Key "test-complex" -ScriptBlock $scriptBlock
            $result2.Name | Should -Be "Test"
            $result2.Values | Should -Be @(1, 2, 3)
            $result2.Nested.Property | Should -Be "Value"
        }
        
        It "应该能够缓存数组" {
            $array = @("item1", "item2", "item3")
            $scriptBlock = { $array }
            
            $result1 = Invoke-WithCache -Key "test-array" -ScriptBlock $scriptBlock
            $result2 = Invoke-WithCache -Key "test-array" -ScriptBlock $scriptBlock
            
            (@($result1)).Count | Should -Be 3
            (@($result2)).Count | Should -Be 3
            $result1[0] | Should -Be "item1"
            $result2[0] | Should -Be "item1"
        }
    }
    
    Context "错误处理测试" {
        It "脚本块抛出异常时应该传播异常" {
            $scriptBlock = { throw "Test exception" }
            
            { Invoke-WithCache -Key "test-error" -ScriptBlock $scriptBlock } | Should -Throw "Test exception"
        }
        
        It "异常不应该创建缓存文件" {
            $scriptBlock = { throw "Test exception" }
            
            try {
                Invoke-WithCache -Key "test-error-nocache" -ScriptBlock $scriptBlock
            }
            catch {
                # 忽略异常
            }
            
            # 验证没有创建缓存文件
            $cacheFiles = Get-ChildItem $script:TestCacheDir -Filter "*.cache.*" -ErrorAction SilentlyContinue
            (@($cacheFiles)).Count | Should -Be 0
        }
    }
    
    Context "参数验证测试" {
        It "应该接受自定义MaxAge" {
            $customMaxAge = [TimeSpan]::FromMinutes(30)
            $result = Invoke-WithCache -Key "test-maxage" -ScriptBlock { "test" } -MaxAge $customMaxAge
            $result | Should -Be "test"
        }
        
        It "应该接受所有有效参数组合" {
            # 测试基本参数
            $result1 = Invoke-WithCache -Key "test-params1" -ScriptBlock { "test1" }
            $result1 | Should -Be "test1"
            
            # 测试带Force参数
            $result2 = Invoke-WithCache -Key "test-params2" -ScriptBlock { "test2" } -Force
            $result2 | Should -Be "test2"
            
            # 测试带NoCache参数
            $result3 = Invoke-WithCache -Key "test-params3" -ScriptBlock { "test3" } -NoCache
            $result3 | Should -Be "test3"
        }
    }
    
    Context "ShouldProcess支持测试" {
        It "应该支持WhatIf参数" {
            $result = Invoke-WithCache -Key "test-whatif" -ScriptBlock { "test" } -WhatIf
            # WhatIf模式下不应该执行脚本块或创建缓存
            $cacheFiles = Get-ChildItem $script:TestCacheDir -Filter "*.cache.*" -ErrorAction SilentlyContinue
            (@($cacheFiles)).Count | Should -Be 0
        }
    }
    
    Context "CacheType参数测试" {
        It "默认应该使用XML缓存格式" {
            $result = Invoke-WithCache -Key "test-default-xml" -ScriptBlock { "test content" }
            $result | Should -Be "test content"
            
            # 验证创建了XML格式的缓存文件
            $xmlFiles = Get-ChildItem $script:TestCacheDir -Filter "*.cache.xml"
            (@($xmlFiles)).Count | Should -Be 1
        }
        
        It "应该支持Text缓存格式" {
            $testContent = "This is test content for text cache"
            $result = Invoke-WithCache -Key "test-text-cache" -CacheType Text -ScriptBlock { $testContent }
            $result | Should -Be $testContent
            
            # 验证创建了Text格式的缓存文件
            $textFiles = Get-ChildItem $script:TestCacheDir -Filter "*.cache.txt"
            (@($textFiles)).Count | Should -Be 1
        }
        
        It "Text缓存应该能够缓存字符串内容" {
            $script:textCounter = 0
            $scriptBlock = { $script:textCounter++; "Text result: $($script:textCounter)" }
            
            # 第一次调用
            $result1 = Invoke-WithCache -Key "test-text-hit" -CacheType Text -ScriptBlock $scriptBlock
            $result1 | Should -Be "Text result: 1"
            
            # 第二次调用应该从缓存返回
            $result2 = Invoke-WithCache -Key "test-text-hit" -CacheType Text -ScriptBlock $scriptBlock
            $result2 | Should -Be "Text result: 1"
        }
        
        It "XML缓存应该能够缓存复杂对象" {
            $complexObject = @{
                Name    = "TestObject"
                Numbers = @(1, 2, 3)
                Date    = Get-Date "2024-01-01"
            }
            
            $scriptBlock = { $complexObject }
            
            # 第一次调用
            $result1 = Invoke-WithCache -Key "test-xml-complex" -CacheType XML -ScriptBlock $scriptBlock
            $result1.Name | Should -Be "TestObject"
            $result1.Numbers | Should -Be @(1, 2, 3)
            $result1.Date.Year | Should -Be 2024
            
            # 第二次调用应该从缓存返回相同结构
            $result2 = Invoke-WithCache -Key "test-xml-complex" -CacheType XML -ScriptBlock $scriptBlock
            $result2.Name | Should -Be "TestObject"
            $result2.Numbers | Should -Be @(1, 2, 3)
            $result2.Date.Year | Should -Be 2024
        }
        
        It "Text缓存应该将非字符串对象转换为字符串" {
            $numberArray = @(1, 2, 3, 4, 5)
            $scriptBlock = { $numberArray }
            
            $result = Invoke-WithCache -Key "test-text-conversion" -CacheType Text -ScriptBlock $scriptBlock
            
            # Text缓存应该将数组转换为字符串格式
            $result | Should -BeOfType [string]
            $result | Should -Match "1"
            $result | Should -Match "2"
        }
        
        It "不同CacheType应该创建不同的缓存文件" {
            $testData = "Same content"
            
            # 使用XML格式缓存
            $result1 = Invoke-WithCache -Key "test-different-types" -CacheType XML -ScriptBlock { $testData }
            
            # 使用Text格式缓存（相同Key但不同CacheType）
            $result2 = Invoke-WithCache -Key "test-different-types" -CacheType Text -ScriptBlock { $testData }
            
            # 两种格式都应该返回相同内容
            $result1 | Should -Be $testData
            $result2 | Should -Be $testData
            
            # 但应该创建不同的缓存文件
            $xmlFiles = Get-ChildItem $script:TestCacheDir -Filter "*.cache.xml"
            $txtFiles = Get-ChildItem $script:TestCacheDir -Filter "*.cache.txt"
            
            (@($xmlFiles)).Count | Should -BeGreaterThan 0
            (@($txtFiles)).Count | Should -BeGreaterThan 0
        }
        
        It "Text缓存应该支持Force参数" {
            $script:textForceCounter = 0
            $scriptBlock = { $script:textForceCounter++; "Force test: $($script:textForceCounter)" }
            
            # 第一次调用
            $result1 = Invoke-WithCache -Key "test-text-force" -CacheType Text -ScriptBlock $scriptBlock
            $result1 | Should -Be "Force test: 1"
            
            # 使用Force参数强制刷新
            $result2 = Invoke-WithCache -Key "test-text-force" -CacheType Text -ScriptBlock $scriptBlock -Force
            $result2 | Should -Be "Force test: 2"
        }
        
        It "Text缓存应该支持NoCache参数" {
            $script:textNoCacheCounter = 0
            $scriptBlock = { $script:textNoCacheCounter++; "NoCache test: $($script:textNoCacheCounter)" }
            
            # 使用NoCache参数
            $result1 = Invoke-WithCache -Key "test-text-nocache" -CacheType Text -ScriptBlock $scriptBlock -NoCache
            $result1 | Should -Be "NoCache test: 1"
            
            # 第二次使用NoCache参数，应该重新执行
            $result2 = Invoke-WithCache -Key "test-text-nocache" -CacheType Text -ScriptBlock $scriptBlock -NoCache
            $result2 | Should -Be "NoCache test: 2"
            
            # 验证没有创建缓存文件
            $textFiles = Get-ChildItem $script:TestCacheDir -Filter "*.cache.txt" -ErrorAction SilentlyContinue
            (@($textFiles)).Count | Should -Be 0
        }
    }
}