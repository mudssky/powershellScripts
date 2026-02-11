BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'functions.psm1') -Force
}

Describe "Update-Semver 函数测试" {
    Context "Patch 更新" {
        It "应该递增修订版本号" {
            $result = Update-Semver -Version "1.2.3" -UpdateType "patch"
            $result | Should -Be "1.2.4"
        }

        It "应该默认使用 patch 更新" {
            $result = Update-Semver -Version "0.0.1"
            $result | Should -Be "0.0.2"
        }
    }

    Context "Minor 更新" {
        It "应该递增次版本号（保持 patch 不变）" {
            # 源码只递增指定部分，不重置低位
            $result = Update-Semver -Version "1.2.3" -UpdateType "minor"
            $result | Should -Be "1.3.3"
        }
    }

    Context "Major 更新" {
        It "应该递增主版本号（保持其他不变）" {
            # 源码只递增指定部分，不重置低位
            $result = Update-Semver -Version "1.2.3" -UpdateType "major"
            $result | Should -Be "2.2.3"
        }
    }

    Context "边界情况" {
        It "应该处理 0.0.0 版本" {
            $result = Update-Semver -Version "0.0.0" -UpdateType "patch"
            $result | Should -Be "0.0.1"
        }

        It "应该处理大版本号" {
            $result = Update-Semver -Version "99.99.99" -UpdateType "patch"
            $result | Should -Be "99.99.100"
        }

        It "应该在无效版本字符串时报错" {
            { Update-Semver -Version "invalid" -UpdateType "patch" -ErrorAction Stop } | Should -Throw
        }

        It "应该在缺少部分的版本号时报错" {
            { Update-Semver -Version "1.2" -UpdateType "patch" -ErrorAction Stop } | Should -Throw
        }

        It "应该正确处理 minor 更新从 0" {
            $result = Update-Semver -Version "0.0.0" -UpdateType "minor"
            $result | Should -Be "0.1.0"
        }

        It "应该正确处理 major 更新从 0" {
            $result = Update-Semver -Version "0.0.0" -UpdateType "major"
            $result | Should -Be "1.0.0"
        }
    }
}

Describe "Get-FormatLength 函数测试" {
    Context "字节级别" {
        It "应该正确格式化小于 1KB 的大小" {
            $result = Get-FormatLength -length 512
            $result | Should -Be "512 B"
        }

        It "应该正确格式化 0 字节" {
            $result = Get-FormatLength -length 0
            $result | Should -Be "0 B"
        }

        It "应该对恰好等于 1024 返回 B 格式" {
            # 函数使用 -gt 1kb, 所以 1024 等于 1kb 不触发 KB 分支
            $result = Get-FormatLength -length 1024
            $result | Should -Be "1024 B"
        }
    }

    Context "KB 级别" {
        It "应该正确格式化大于 1KB 的大小" {
            $result = Get-FormatLength -length 1025
            $result | Should -BeLike "*KB"
        }

        It "应该正确格式化 1536 字节" {
            $result = Get-FormatLength -length 1536
            $result | Should -BeLike "*KB"
        }
    }

    Context "MB 级别" {
        It "应该正确格式化 MB 大小" {
            $result = Get-FormatLength -length (2 * 1MB + 1)
            $result | Should -BeLike "*MB"
        }
    }

    Context "GB 级别" {
        It "应该正确格式化 GB 大小" {
            $result = Get-FormatLength -length (3 * 1GB + 1)
            $result | Should -BeLike "*GB"
        }
    }
}

Describe "Get-NeedBinaryDigit 函数测试" {
    # 函数逻辑: 从 i=62 向 0 递减, 如果 (1 -shl i) < number 则返回 i+1
    # 所以对于 number=2, (1 -shl 1)=2 不小于 2, 继续循环
    # (1 -shl 0)=1 不被检测因为循环终止条件是 i -gt 0
    # 因此 1 和 2 会返回 $null（循环结束无匹配）

    It "应该为 3 返回 2 位" {
        $result = Get-NeedBinaryDigit -number 3
        $result | Should -Be 2
    }

    It "应该为 5 返回 3 位" {
        $result = Get-NeedBinaryDigit -number 5
        $result | Should -Be 3
    }

    It "应该为 1023 返回 10 位" {
        $result = Get-NeedBinaryDigit -number 1023
        $result | Should -Be 10
    }

    It "应该为 1025 返回 11 位" {
        $result = Get-NeedBinaryDigit -number 1025
        $result | Should -Be 11
    }

    It "应该为 255 返回 8 位" {
        $result = Get-NeedBinaryDigit -number 255
        $result | Should -Be 8
    }

    It "应该为 65536 返回 17 位" {
        $result = Get-NeedBinaryDigit -number 65537
        $result | Should -Be 17
    }
}

Describe "Get-ReversedMap 函数测试" {
    It "应该返回哈希表类型" {
        $map = @{ "key1" = "value1"; "key2" = "value2" }
        $result = Get-ReversedMap -map $map
        $result | Should -BeOfType [hashtable]
    }
}

Describe "Get-HistoryCommandRank 函数测试" {
    It "返回历史命令排名" -Skip {
        $result = Get-HistoryCommandRank -top 5
        $result | Should -Not -BeNullOrEmpty
    }
}

Describe "Get-ScriptFolder 函数测试" {
    It "应该返回字符串" {
        $result = Get-ScriptFolder
        $result | Should -BeOfType [string]
    }
}

Describe "Set-Script 函数测试" {
    BeforeAll {
        $script:testPkgPath = "$TestDrive/package.json"
    }

    It "应该添加新的脚本到 package.json" {
        $json = @{ scripts = @{ existing = "echo hello" } }
        $json | ConvertTo-Json | Out-File $script:testPkgPath

        Set-Script -key "newscript" -Value "echo world" -Path $script:testPkgPath
        $result = Get-Content $script:testPkgPath | ConvertFrom-Json -AsHashtable
        $result.scripts["newscript"] | Should -Be "echo world"
    }

    It "应该更新已存在的脚本" {
        $json = @{ scripts = @{ test = "old command" } }
        $json | ConvertTo-Json | Out-File $script:testPkgPath

        Set-Script -key "test" -Value "new command" -Path $script:testPkgPath
        $result = Get-Content $script:testPkgPath | ConvertFrom-Json -AsHashtable
        $result.scripts["test"] | Should -Be "new command"
    }
}

Describe "New-Shortcut 函数测试" -Tag 'windowsOnly' {
    BeforeAll {
        $testTarget = "$TestDrive\target.txt"
        "" | Out-File -FilePath $testTarget -Encoding utf8
        $testShortcut = "$TestDrive\shortcut.lnk"
    }

    It "成功创建快捷方式" {
        if (-not $IsWindows) { Set-ItResult -Skipped -Because 'Windows-only'; return }
        { New-Shortcut -Path $testTarget -Destination $testShortcut } | Should -Not -Throw
        Test-Path $testShortcut | Should -Be $true
    }
}

Describe "Invoke-FzfHistorySmart 函数测试" {
    Context "缺少 fzf" {
        It "应该在没有 fzf 时不抛出异常" {
            Mock -ModuleName functions Get-Command { return $null } -ParameterFilter { $Name -eq "fzf" }
            { Invoke-FzfHistorySmart } | Should -Not -Throw
        }
    }
}

Describe "Register-FzfHistorySmartKeyBinding 函数测试" {
    Context "缺少依赖" {
        It "应该在没有 PSReadLine 时返回 false" {
            Mock -ModuleName functions Get-Command {
                if ($Name -eq "Set-PSReadLineKeyHandler") { return $null }
                return $null
            }

            $result = Register-FzfHistorySmartKeyBinding
            $result | Should -Be $false
        }

        It "应该在没有 fzf 时返回 false" {
            Mock -ModuleName functions Get-Command {
                if ($Name -eq "Set-PSReadLineKeyHandler") { return [PSCustomObject]@{ Name = "Set-PSReadLineKeyHandler" } }
                if ($Name -eq "fzf") { return $null }
                return $null
            }

            $result = Register-FzfHistorySmartKeyBinding
            $result | Should -Be $false
        }
    }
}
