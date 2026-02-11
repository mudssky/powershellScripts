<#
.SYNOPSIS
    Invoke-WithCache 函数的单元测试

.DESCRIPTION
    使用 Pester 框架测试 Invoke-WithCache 函数的各种功能，包括缓存命中、缓存过期、
    强制刷新、NoCache模式、CacheType参数等场景。
    同时测试 Clear-ExpiredCache、Get-CacheStats、Invoke-WithFileCache 函数。

.NOTES
    作者: mudssky
    版本: 1.4.0
    创建日期: 2025-01-07
    最后修改: 2025-01-07
    测试框架: Pester 5.x
    新增功能: Clear-ExpiredCache、Get-CacheStats、Invoke-WithFileCache 测试
#>

BeforeAll {
    $script:OriginalLocalAppData = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = $TestDrive

    # 导入被测试的模块
    $ModulePath = Join-Path $PSScriptRoot ".." "modules" "cache.psm1"
    Import-Module $ModulePath -Force

    # 定义测试用的缓存目录
    if ($IsWindows) {
        $script:TestCacheDir = Join-Path $env:LOCALAPPDATA "PowerShellCache"
    }
    elseif ($IsMacOS) {
        $homeDir = $env:HOME
        $script:TestCacheDir = Join-Path $homeDir "Library/Caches/PowerShellCache"
    }
    elseif ($IsLinux) {
        $homeDir = $env:HOME
        $xdgCacheHome = $env:XDG_CACHE_HOME
        if ([string]::IsNullOrWhiteSpace($xdgCacheHome)) {
            $script:TestCacheDir = Join-Path $homeDir ".cache/PowerShellCache"
        }
        else {
            $script:TestCacheDir = Join-Path $xdgCacheHome "PowerShellCache"
        }
    }
    else {
        $homeDir = $env:HOME
        if ([string]::IsNullOrWhiteSpace($homeDir)) { $homeDir = $env:USERPROFILE }
        $script:TestCacheDir = Join-Path $homeDir ".powershell-cache"
    }

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

    $env:LOCALAPPDATA = $script:OriginalLocalAppData

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

Describe "Clear-ExpiredCache 函数测试" {
    BeforeEach {
        # 每个测试前清理缓存
        if (Test-Path $script:TestCacheDir) {
            Get-ChildItem $script:TestCacheDir -Filter "*.cache.*" | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    Context "基本清理功能" {
        It "没有缓存文件时应该返回空统计" {
            $stats = Clear-ExpiredCache -MaxAge ([TimeSpan]::FromDays(7))
            $stats.TotalFiles | Should -Be 0
            $stats.DeletedFiles | Should -Be 0
        }

        It "应该删除过期的缓存文件" {
            # 创建假的过期缓存文件
            $fakeFile = Join-Path $script:TestCacheDir "fakehash.cache.xml"
            "fake content" | Set-Content -Path $fakeFile -Encoding UTF8
            # 将文件修改时间设为10天前
            $oldDate = (Get-Date).AddDays(-10)
            (Get-Item $fakeFile).LastWriteTime = $oldDate

            $stats = Clear-ExpiredCache -MaxAge ([TimeSpan]::FromDays(7))
            $stats.DeletedFiles | Should -Be 1
            Test-Path $fakeFile | Should -Be $false
        }

        It "不应该删除未过期的缓存文件" {
            # 创建新缓存文件（未过期）
            $fakeFile = Join-Path $script:TestCacheDir "newhash.cache.xml"
            "fresh content" | Set-Content -Path $fakeFile -Encoding UTF8

            $stats = Clear-ExpiredCache -MaxAge ([TimeSpan]::FromDays(7))
            $stats.DeletedFiles | Should -Be 0
            Test-Path $fakeFile | Should -Be $true
            Remove-Item $fakeFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Force参数测试" {
        It "Force参数应该删除所有缓存文件" {
            # 创建多个缓存文件（新的和旧的）
            $file1 = Join-Path $script:TestCacheDir "hash1.cache.xml"
            $file2 = Join-Path $script:TestCacheDir "hash2.cache.txt"
            "content1" | Set-Content -Path $file1 -Encoding UTF8
            "content2" | Set-Content -Path $file2 -Encoding UTF8

            $stats = Clear-ExpiredCache -Force
            $stats.DeletedFiles | Should -Be 2
            Test-Path $file1 | Should -Be $false
            Test-Path $file2 | Should -Be $false
        }
    }

    Context "自定义MaxAge测试" {
        It "应该按照自定义MaxAge清理" {
            # 创建一个2天前的缓存文件
            $fakeFile = Join-Path $script:TestCacheDir "agehash.cache.xml"
            "age content" | Set-Content -Path $fakeFile -Encoding UTF8
            $oldDate = (Get-Date).AddDays(-2)
            (Get-Item $fakeFile).LastWriteTime = $oldDate

            # 使用1天的MaxAge应该删除2天前的文件
            $stats = Clear-ExpiredCache -MaxAge ([TimeSpan]::FromDays(1))
            $stats.DeletedFiles | Should -Be 1
        }
    }

    Context "统计信息测试" {
        It "应该返回正确的统计信息结构" {
            $stats = Clear-ExpiredCache
            $stats.Keys | Should -Contain "TotalFiles"
            $stats.Keys | Should -Contain "ExpiredFiles"
            $stats.Keys | Should -Contain "DeletedFiles"
            $stats.Keys | Should -Contain "FreedSpace"
            $stats.Keys | Should -Contain "Errors"
        }

        It "应该正确统计总文件数" {
            $file1 = Join-Path $script:TestCacheDir "stat1.cache.xml"
            $file2 = Join-Path $script:TestCacheDir "stat2.cache.txt"
            "c1" | Set-Content -Path $file1 -Encoding UTF8
            "c2" | Set-Content -Path $file2 -Encoding UTF8

            $stats = Clear-ExpiredCache -MaxAge ([TimeSpan]::FromDays(7))
            $stats.TotalFiles | Should -Be 2
            # 清理测试文件
            Remove-Item $file1, $file2 -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Get-CacheStats 函数测试" {
    BeforeEach {
        # 清理缓存
        if (Test-Path $script:TestCacheDir) {
            Get-ChildItem $script:TestCacheDir -Filter "*.cache.*" | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    Context "基本统计功能" {
        It "应该返回包含正确键的统计对象" {
            $stats = Get-CacheStats
            $stats.Keys | Should -Contain "CacheDirectory"
            $stats.Keys | Should -Contain "RuntimeStats"
            $stats.Keys | Should -Contain "FileStats"
            $stats.Keys | Should -Contain "Performance"
        }

        It "CacheDirectory应该是有效路径" {
            $stats = Get-CacheStats
            $stats.CacheDirectory | Should -Not -BeNullOrEmpty
        }

        It "没有缓存文件时FileStats.TotalFiles应该为0" {
            $stats = Get-CacheStats
            $stats.FileStats.TotalFiles | Should -Be 0
        }
    }

    Context "运行时统计测试" {
        It "RuntimeStats应该包含正确的键" {
            $stats = Get-CacheStats
            $stats.RuntimeStats.Keys | Should -Contain "Hits"
            $stats.RuntimeStats.Keys | Should -Contain "Misses"
            $stats.RuntimeStats.Keys | Should -Contain "Writes"
            $stats.RuntimeStats.Keys | Should -Contain "CleanupRuns"
        }
    }

    Context "文件统计测试" {
        It "应该正确统计缓存文件数量" {
            # 创建测试缓存文件
            $file1 = Join-Path $script:TestCacheDir "statstest1.cache.xml"
            $file2 = Join-Path $script:TestCacheDir "statstest2.cache.txt"
            "xml content" | Set-Content -Path $file1 -Encoding UTF8
            "txt content" | Set-Content -Path $file2 -Encoding UTF8

            $stats = Get-CacheStats
            $stats.FileStats.TotalFiles | Should -Be 2
            $stats.FileStats.XMLFiles | Should -Be 1
            $stats.FileStats.TextFiles | Should -Be 1

            # 清理
            Remove-Item $file1, $file2 -Force -ErrorAction SilentlyContinue
        }

        It "应该计算TotalSize" {
            $file1 = Join-Path $script:TestCacheDir "sizetest.cache.xml"
            "some content for size testing" | Set-Content -Path $file1 -Encoding UTF8

            $stats = Get-CacheStats
            $stats.FileStats.TotalSize | Should -BeGreaterThan 0

            Remove-Item $file1 -Force -ErrorAction SilentlyContinue
        }

        It "应该记录最新和最旧文件时间" {
            $file1 = Join-Path $script:TestCacheDir "time1.cache.xml"
            "old" | Set-Content -Path $file1 -Encoding UTF8
            (Get-Item $file1).LastWriteTime = (Get-Date).AddDays(-5)

            $file2 = Join-Path $script:TestCacheDir "time2.cache.xml"
            "new" | Set-Content -Path $file2 -Encoding UTF8

            $stats = Get-CacheStats
            $stats.FileStats.OldestFile | Should -Not -BeNullOrEmpty
            $stats.FileStats.NewestFile | Should -Not -BeNullOrEmpty

            Remove-Item $file1, $file2 -Force -ErrorAction SilentlyContinue
        }
    }

    Context "性能指标测试" {
        It "Performance应该包含HitRate和TotalRequests" {
            $stats = Get-CacheStats
            $stats.Performance.Keys | Should -Contain "HitRate"
            $stats.Performance.Keys | Should -Contain "TotalRequests"
        }
    }

    Context "Detailed参数测试" {
        It "Detailed参数应该正常工作不报错" {
            $file1 = Join-Path $script:TestCacheDir "detail.cache.xml"
            "detail content" | Set-Content -Path $file1 -Encoding UTF8

            { Get-CacheStats -Detailed } | Should -Not -Throw

            Remove-Item $file1 -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Invoke-WithFileCache 函数测试" {
    BeforeAll {
        $script:FileCacheBaseDir = Join-Path $TestDrive "filecache_test"
        if (-not (Test-Path $script:FileCacheBaseDir)) {
            New-Item -ItemType Directory -Path $script:FileCacheBaseDir -Force | Out-Null
        }
    }

    AfterAll {
        if (Test-Path $script:FileCacheBaseDir) {
            Remove-Item $script:FileCacheBaseDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "基本功能测试" {
        It "应该返回缓存文件路径" {
            $result = Invoke-WithFileCache -Key "test-file-cache" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { "echo hello" } -BaseDir $script:FileCacheBaseDir
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [string]
        }

        It "生成的缓存文件应该存在" {
            $result = Invoke-WithFileCache -Key "test-file-exists" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { "echo world" } -BaseDir $script:FileCacheBaseDir
            Test-Path $result | Should -Be $true
        }

        It "缓存文件应该是.ps1扩展名" {
            $result = Invoke-WithFileCache -Key "test-file-ext" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { "echo ext" } -BaseDir $script:FileCacheBaseDir
            $result | Should -Match "\.ps1$"
        }

        It "缓存文件内容应该包含Generator输出" {
            $result = Invoke-WithFileCache -Key "test-file-content" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { "Write-Host 'hello world'" } -BaseDir $script:FileCacheBaseDir
            $content = Get-Content -Path $result -Raw
            $content | Should -Match "hello world"
        }
    }

    Context "缓存复用测试" {
        It "在有效期内应该复用缓存文件" {
            $callCount = 0
            $gen = { $callCount++; "output $callCount" }

            $result1 = Invoke-WithFileCache -Key "test-reuse" -MaxAge ([TimeSpan]::FromDays(7)) -Generator $gen -BaseDir $script:FileCacheBaseDir
            $result2 = Invoke-WithFileCache -Key "test-reuse" -MaxAge ([TimeSpan]::FromDays(7)) -Generator $gen -BaseDir $script:FileCacheBaseDir

            $result1 | Should -Be $result2
        }
    }

    Context "过期测试" {
        It "过期的缓存应该重新生成" {
            $result1 = Invoke-WithFileCache -Key "test-expire-fc" -MaxAge ([TimeSpan]::FromMilliseconds(100)) -Generator { "first" } -BaseDir $script:FileCacheBaseDir

            # 等待过期
            Start-Sleep -Milliseconds 200

            $result2 = Invoke-WithFileCache -Key "test-expire-fc" -MaxAge ([TimeSpan]::FromMilliseconds(100)) -Generator { "second" } -BaseDir $script:FileCacheBaseDir

            # 路径应该相同，但内容已更新
            $result1 | Should -Be $result2
            $content = Get-Content -Path $result2 -Raw
            $content | Should -Match "second"
        }
    }

    Context "自定义BaseDir测试" {
        It "应该在自定义目录创建缓存文件" {
            $customDir = Join-Path $TestDrive "custom_cache_dir"
            $result = Invoke-WithFileCache -Key "test-custom-dir" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { "custom" } -BaseDir $customDir
            Test-Path $customDir | Should -Be $true
            $result | Should -Match ([regex]::Escape($customDir))
            # 清理
            Remove-Item $customDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Key安全性测试" {
        It "Key中的特殊字符应该被替换" {
            $result = Invoke-WithFileCache -Key "test/special:chars" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { "safe" } -BaseDir $script:FileCacheBaseDir
            $fileName = [System.IO.Path]::GetFileName($result)
            $fileName | Should -Not -Match "[/:]"
        }
    }
}
