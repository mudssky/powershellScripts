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
    $script:CacheModulePath = (Resolve-Path (Join-Path $PSScriptRoot ".." "modules" "cache.psm1")).Path
    Import-Module $script:CacheModulePath -Force

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
            Get-TestCacheFiles | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    function Get-TestCacheFiles {
        param(
            [string]$Filter = '*.cache.*'
        )

        return @(Get-ChildItem -Path $script:TestCacheDir -Filter $Filter -File -ErrorAction SilentlyContinue)
    }

    function Invoke-CacheWhatIfChild {
        param(
            [Parameter(Mandatory)]
            [string]$ModulePath,
            [Parameter(Mandatory)]
            [string]$LocalAppDataPath,
            [Parameter(Mandatory)]
            [string]$Key
        )

        # WhatIf 主机提示不会被常规重定向静音，因此这里改用子进程承接提示文本，
        # 父测试进程只断言语义与副作用结果，避免默认门禁日志继续出现残留提示。
        $pwshPath = (Get-Process -Id $PID).Path
        $escapedModulePath = $ModulePath.Replace("'", "''")
        $escapedLocalAppDataPath = $LocalAppDataPath.Replace("'", "''")
        $escapedKey = $Key.Replace("'", "''")
        $childScript = @(
            '$ErrorActionPreference = ''Stop'''
            "`$env:LOCALAPPDATA = '$escapedLocalAppDataPath'"
            "Import-Module '$escapedModulePath' -Force"
            "Invoke-WithCache -Key '$escapedKey' -ScriptBlock { 'test' } -WhatIf"
        ) -join '; '
        $output = & $pwshPath -NoProfile -NoLogo -Command $childScript 2>&1

        return [PSCustomObject]@{
            ExitCode = $LASTEXITCODE
            Output   = @($output | ForEach-Object { $_.ToString() })
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
    BeforeAll {
        # 这些测试关注缓存行为本身，统计与提示输出留给详细模式即可。
        Mock -ModuleName cache Write-Host { }
        Mock -ModuleName cache Write-Warning { }
    }

    BeforeEach {
        # 每个测试前清理缓存
        Clear-TestCache
    }

    Context "基本功能测试" {
        It "应该执行脚本块并创建基础缓存产物" {
            $result = Invoke-WithCache -Key "test-basic" -ScriptBlock { "Hello World" }

            $result | Should -Be "Hello World"
            $script:TestCacheDir | Should -Exist
            $cacheFiles = Get-TestCacheFiles
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
            # 直接回拨缓存文件时间戳，避免真实等待拖慢门禁，同时保持过期语义真实成立。
            (Get-ChildItem $script:TestCacheDir -Filter "*.cache.*" | Select-Object -First 1).LastWriteTime = (Get-Date).AddSeconds(-1)

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
        It "NoCache模式应该跳过缓存且后续正常模式可重新建立缓存" {
            $script:noCacheCounter = 0
            $scriptBlock = { $script:noCacheCounter++; "Result: $($script:noCacheCounter)" }

            # 第一次调用使用NoCache
            $result1 = Invoke-WithCache -Key "test-nocache" -ScriptBlock $scriptBlock -NoCache
            $result1 | Should -Be "Result: 1"

            # 第二次调用使用NoCache，应该重新执行
            $result2 = Invoke-WithCache -Key "test-nocache" -ScriptBlock $scriptBlock -NoCache
            $result2 | Should -Be "Result: 2"

            # 验证没有创建缓存文件
            $cacheFiles = Get-TestCacheFiles
            (@($cacheFiles)).Count | Should -Be 0

            # 正常模式应该创建缓存
            $result3 = Invoke-WithCache -Key "test-nocache" -ScriptBlock $scriptBlock
            $result3 | Should -Be "Result: 3"

            # 第三次调用应该从缓存返回
            $result4 = Invoke-WithCache -Key "test-nocache" -ScriptBlock $scriptBlock
            $result4 | Should -Be "Result: 3"
        }
    }

    Context "复杂数据类型测试" {
        It "应该能够缓存复杂对象和数组" {
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

            $array = @("item1", "item2", "item3")
            $arrayScriptBlock = { $array }

            $arrayResult1 = Invoke-WithCache -Key "test-array" -ScriptBlock $arrayScriptBlock
            $arrayResult2 = Invoke-WithCache -Key "test-array" -ScriptBlock $arrayScriptBlock

            (@($arrayResult1)).Count | Should -Be 3
            (@($arrayResult2)).Count | Should -Be 3
            $arrayResult1[0] | Should -Be "item1"
            $arrayResult2[0] | Should -Be "item1"
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
            $cacheFiles = Get-TestCacheFiles
            (@($cacheFiles)).Count | Should -Be 0
        }
    }

    Context "参数验证测试" {
        It "应该接受自定义MaxAge和常见参数组合" {
            $customMaxAge = [TimeSpan]::FromMinutes(30)
            $maxAgeResult = Invoke-WithCache -Key "test-maxage" -ScriptBlock { "test" } -MaxAge $customMaxAge
            $maxAgeResult | Should -Be "test"

            $result1 = Invoke-WithCache -Key "test-params1" -ScriptBlock { "test1" }
            $result1 | Should -Be "test1"

            $result2 = Invoke-WithCache -Key "test-params2" -ScriptBlock { "test2" } -Force
            $result2 | Should -Be "test2"

            $result3 = Invoke-WithCache -Key "test-params3" -ScriptBlock { "test3" } -NoCache
            $result3 | Should -Be "test3"
        }
    }

    Context "ShouldProcess支持测试" {
        It "应该支持WhatIf参数" {
            $childResult = Invoke-CacheWhatIfChild -ModulePath $script:CacheModulePath -LocalAppDataPath $TestDrive -Key "test-whatif"
            $childResult.ExitCode | Should -Be 0
            ($childResult.Output -join "`n") | Should -Match 'What if: Performing the operation "Invoke-WithCache" on target "Executing script block with key ''test-whatif''"\.'
            # WhatIf模式下不应该执行脚本块或创建缓存
            $cacheFiles = Get-TestCacheFiles
            (@($cacheFiles)).Count | Should -Be 0
        }
    }

    Context "CacheType参数测试" {
        It "应该为 XML 和 Text 缓存生成正确的文件并保留内容" {
            $result = Invoke-WithCache -Key "test-default-xml" -ScriptBlock { "test content" }
            $result | Should -Be "test content"

            # 验证创建了XML格式的缓存文件
            $xmlFiles = Get-TestCacheFiles -Filter '*.cache.xml'
            (@($xmlFiles)).Count | Should -Be 1

            $testContent = "This is test content for text cache"
            $textResult = Invoke-WithCache -Key "test-text-cache" -CacheType Text -ScriptBlock { $testContent }
            $textResult | Should -Be $testContent

            # 验证创建了Text格式的缓存文件
            $textFiles = Get-TestCacheFiles -Filter '*.cache.txt'
            (@($textFiles)).Count | Should -Be 1
 
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

            $numberArray = @(1, 2, 3, 4, 5)
            $textConversionScriptBlock = { $numberArray }

            $textConversionResult = Invoke-WithCache -Key "test-text-conversion" -CacheType Text -ScriptBlock $textConversionScriptBlock

            # Text缓存应该将数组转换为字符串格式
            $textConversionResult | Should -BeOfType [string]
            $textConversionResult | Should -Match "1"
            $textConversionResult | Should -Match "2"

            $testData = "Same content"

            # 使用XML格式缓存
            $xmlTypeResult = Invoke-WithCache -Key "test-different-types" -CacheType XML -ScriptBlock { $testData }

            # 使用Text格式缓存（相同Key但不同CacheType）
            $textTypeResult = Invoke-WithCache -Key "test-different-types" -CacheType Text -ScriptBlock { $testData }

            # 两种格式都应该返回相同内容
            $xmlTypeResult | Should -Be $testData
            $textTypeResult | Should -Be $testData

            # 但应该创建不同的缓存文件
            $allXmlFiles = Get-TestCacheFiles -Filter '*.cache.xml'
            $allTxtFiles = Get-TestCacheFiles -Filter '*.cache.txt'

            (@($allXmlFiles)).Count | Should -BeGreaterThan 0
            (@($allTxtFiles)).Count | Should -BeGreaterThan 0
        }

        It "Text缓存应该支持命中、Force 和 NoCache 语义" {
            $script:textForceCounter = 0
            $scriptBlock = { $script:textForceCounter++; "Force test: $($script:textForceCounter)" }

            # 第一次调用
            $result1 = Invoke-WithCache -Key "test-text-force" -CacheType Text -ScriptBlock $scriptBlock
            $result1 | Should -Be "Force test: 1"

            # 第二次调用应命中缓存
            $result2 = Invoke-WithCache -Key "test-text-force" -CacheType Text -ScriptBlock $scriptBlock
            $result2 | Should -Be "Force test: 1"

            # 使用Force参数强制刷新
            $result3 = Invoke-WithCache -Key "test-text-force" -CacheType Text -ScriptBlock $scriptBlock -Force
            $result3 | Should -Be "Force test: 2"

            $script:textNoCacheCounter = 0
            $noCacheScriptBlock = { $script:textNoCacheCounter++; "NoCache test: $($script:textNoCacheCounter)" }

            # 使用NoCache参数
            $noCacheResult1 = Invoke-WithCache -Key "test-text-nocache" -CacheType Text -ScriptBlock $noCacheScriptBlock -NoCache
            $noCacheResult1 | Should -Be "NoCache test: 1"

            # 第二次使用NoCache参数，应该重新执行
            $noCacheResult2 = Invoke-WithCache -Key "test-text-nocache" -CacheType Text -ScriptBlock $noCacheScriptBlock -NoCache
            $noCacheResult2 | Should -Be "NoCache test: 2"

            # 验证没有创建缓存文件
            $textFiles = Get-TestCacheFiles -Filter '*.cache.txt'
            (@($textFiles | Where-Object { $_.Name -match '\.cache\.txt$' })).Count | Should -Be 1
        }
    }
}

Describe "Clear-ExpiredCache 函数测试" {
    BeforeAll {
        Mock -ModuleName cache Write-Host { }
        Mock -ModuleName cache Write-Warning { }
    }

    BeforeEach {
        # 每个测试前清理缓存
        Clear-TestCache
    }

    Context "基本清理功能" {
        It "没有缓存文件时应该返回空统计结构" {
            $stats = Clear-ExpiredCache -MaxAge ([TimeSpan]::FromDays(7))
            $stats.TotalFiles | Should -Be 0
            $stats.DeletedFiles | Should -Be 0
            $stats.Keys | Should -Contain "TotalFiles"
            $stats.Keys | Should -Contain "ExpiredFiles"
            $stats.Keys | Should -Contain "DeletedFiles"
            $stats.Keys | Should -Contain "FreedSpace"
            $stats.Keys | Should -Contain "Errors"
        }

        It "应该删除过期文件并保留未过期文件" {
            # 创建假的过期缓存文件
            $fakeFile = Join-Path $script:TestCacheDir "fakehash.cache.xml"
            "fake content" | Set-Content -Path $fakeFile -Encoding UTF8
            # 将文件修改时间设为10天前
            $oldDate = (Get-Date).AddDays(-10)
            (Get-Item $fakeFile).LastWriteTime = $oldDate

            $freshFile = Join-Path $script:TestCacheDir "newhash.cache.xml"
            "fresh content" | Set-Content -Path $freshFile -Encoding UTF8

            $stats = Clear-ExpiredCache -MaxAge ([TimeSpan]::FromDays(7))
            $stats.DeletedFiles | Should -Be 1
            Test-Path $fakeFile | Should -Be $false
            Test-Path $freshFile | Should -Be $true
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
        It "应该正确统计总文件数并支持 Force 清理" {
            $file1 = Join-Path $script:TestCacheDir "stat1.cache.xml"
            $file2 = Join-Path $script:TestCacheDir "stat2.cache.txt"
            "c1" | Set-Content -Path $file1 -Encoding UTF8
            "c2" | Set-Content -Path $file2 -Encoding UTF8

            $stats = Clear-ExpiredCache -MaxAge ([TimeSpan]::FromDays(7))
            $stats.TotalFiles | Should -Be 2

            $forceStats = Clear-ExpiredCache -Force
            $forceStats.DeletedFiles | Should -Be 2
            Test-Path $file1 | Should -BeFalse
            Test-Path $file2 | Should -BeFalse
        }
    }
}

Describe "Get-CacheStats 函数测试" {
    BeforeAll {
        Mock -ModuleName cache Write-Host { }
        Mock -ModuleName cache Write-Warning { }
    }

    BeforeEach {
        # 清理缓存
        Clear-TestCache
    }

    It "应该返回基础统计结构并在有文件时聚合数量与时间" {
        $emptyStats = Get-CacheStats

        $emptyStats.Keys | Should -Contain "CacheDirectory"
        $emptyStats.Keys | Should -Contain "RuntimeStats"
        $emptyStats.Keys | Should -Contain "FileStats"
        $emptyStats.Keys | Should -Contain "Performance"
        $emptyStats.CacheDirectory | Should -Not -BeNullOrEmpty
        $emptyStats.RuntimeStats.Keys | Should -Contain "Hits"
        $emptyStats.RuntimeStats.Keys | Should -Contain "Misses"
        $emptyStats.RuntimeStats.Keys | Should -Contain "Writes"
        $emptyStats.RuntimeStats.Keys | Should -Contain "CleanupRuns"
        $emptyStats.Performance.Keys | Should -Contain "HitRate"
        $emptyStats.Performance.Keys | Should -Contain "TotalRequests"

        $file1 = Join-Path $script:TestCacheDir "time1.cache.xml"
        $file2 = Join-Path $script:TestCacheDir "time2.cache.txt"
        "old content" | Set-Content -Path $file1 -Encoding UTF8
        "new content for size test" | Set-Content -Path $file2 -Encoding UTF8
        (Get-Item $file1).LastWriteTime = (Get-Date).AddDays(-5)

        $stats = Get-CacheStats

        $stats.FileStats.TotalFiles | Should -Be 2
        $stats.FileStats.XMLFiles | Should -Be 1
        $stats.FileStats.TextFiles | Should -Be 1
        $stats.FileStats.TotalSize | Should -BeGreaterThan 0
        $stats.FileStats.OldestFile | Should -Be (Get-Item $file1).LastWriteTime
        $stats.FileStats.NewestFile | Should -Be (Get-Item $file2).LastWriteTime
    }

    It "Detailed参数应该正常工作不报错" {
        $file1 = Join-Path $script:TestCacheDir "detail.cache.xml"
        "detail content" | Set-Content -Path $file1 -Encoding UTF8

        { Get-CacheStats -Detailed } | Should -Not -Throw

        Remove-Item $file1 -Force -ErrorAction SilentlyContinue
    }
}

Describe "Invoke-WithFileCache 函数测试" {
    BeforeAll {
        $script:FileCacheBaseDir = Join-Path $TestDrive "filecache_test"
        if (-not (Test-Path $script:FileCacheBaseDir)) {
            New-Item -ItemType Directory -Path $script:FileCacheBaseDir -Force | Out-Null
        }
    }

    BeforeEach {
        Mock -ModuleName cache Write-Host { }
        Mock -ModuleName cache Write-Warning { }
    }

    AfterAll {
        if (Test-Path $script:FileCacheBaseDir) {
            Remove-Item $script:FileCacheBaseDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "基本功能测试" {
        It "应该生成可复用的缓存脚本文件" {
            $result = Invoke-WithFileCache -Key "test-file-cache" -MaxAge ([TimeSpan]::FromDays(7)) -Generator { "echo hello" } -BaseDir $script:FileCacheBaseDir

            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [string]
            Test-Path $result | Should -Be $true
            $result | Should -Match "\.ps1$"
            $content = Get-Content -Path $result -Raw
            $content | Should -Match "echo hello"
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
            # 直接回拨文件时间戳，避免真实等待，同时仍通过真实文件元数据验证过期逻辑。
            (Get-Item $result1).LastWriteTime = (Get-Date).AddSeconds(-1)

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
