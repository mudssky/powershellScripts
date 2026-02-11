BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\wrapper.psm1" -Force
}

Describe "Set-CustomAlias 函数测试" {
    Context "基本功能" {
        It "应该成功创建别名" {
            $testName = "testAlias_$(Get-Random)"
            { Set-CustomAlias -Name $testName -Value "Get-ChildItem" -Force -Scope "Global" } | Should -Not -Throw

            $alias = Get-Alias -Name $testName -ErrorAction SilentlyContinue
            $alias | Should -Not -BeNullOrEmpty
            $alias.Definition | Should -Be "Get-ChildItem"
        }

        It "应该自动添加默认描述前缀" {
            $testName = "testAlias_prefix_$(Get-Random)"
            Set-CustomAlias -Name $testName -Value "Get-ChildItem" -Force -Scope "Global"

            $alias = Get-Alias -Name $testName
            $alias.Description | Should -Match "\[用户自定义\]"
        }

        It "应该将用户描述附加在前缀后面" {
            $testName = "testAlias_desc_$(Get-Random)"
            Set-CustomAlias -Name $testName -Value "Get-ChildItem" -Description "测试描述" -Force -Scope "Global"

            $alias = Get-Alias -Name $testName
            $alias.Description | Should -Be "$($Global:DefaultAliasDespPrefix)测试描述"
        }

        It "应该支持自定义前缀" {
            $testName = "testAlias_custprefix_$(Get-Random)"
            Set-CustomAlias -Name $testName -Value "Get-ChildItem" -AliasDespPrefix "[自定义] " -Description "hello" -Force -Scope "Global"

            $alias = Get-Alias -Name $testName
            $alias.Description | Should -Be "[自定义] hello"
        }
    }

    Context "错误处理" {
        It "应该在 Name 为空时报错" {
            { Set-CustomAlias -Name "" -Value "Get-ChildItem" -ErrorAction Stop } | Should -Throw
        }

        It "应该在 Value 为空时报错" {
            { Set-CustomAlias -Name "testEmpty_$(Get-Random)" -Value "" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "参数传递" {
        It "应该支持 -Force 参数覆盖只读别名" {
            $testName = "testAlias_force_$(Get-Random)"
            Set-Alias -Name $testName -Value "Get-Item" -Option ReadOnly -Force -Scope Global
            { Set-CustomAlias -Name $testName -Value "Get-ChildItem" -Force -Scope "Global" } | Should -Not -Throw
        }

        It "应该支持 -Scope 参数" {
            $testName = "testAlias_scope_$(Get-Random)"
            { Set-CustomAlias -Name $testName -Value "Get-ChildItem" -Scope "Global" -Force } | Should -Not -Throw
        }
    }
}

Describe "Get-CustomAlias 函数测试" {
    BeforeAll {
        # 设置一些测试用的别名，使用一个简单的无特殊字符前缀
        $script:testPrefix = "TESTPREFIX_"
        $script:testAliasNames = @()
        for ($i = 0; $i -lt 3; $i++) {
            $n = "gca_test_$(Get-Random)"
            Set-CustomAlias -Name $n -Value "Get-ChildItem" -AliasDespPrefix $script:testPrefix -Description "test alias $i" -Force -Scope "Global"
            $script:testAliasNames += $n
        }
    }

    Context "基本功能" {
        It "应该返回带有指定前缀的别名" {
            $result = Get-CustomAlias -AliasDespPrefix $script:testPrefix
            $result | Should -Not -BeNullOrEmpty
            $found = $result | Where-Object { $_.Name -eq $script:testAliasNames[0] }
            $found | Should -Not -BeNullOrEmpty
        }

        It "应该通过 Name 参数过滤" {
            $result = Get-CustomAlias -Name $script:testAliasNames[0] -AliasDespPrefix $script:testPrefix
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be $script:testAliasNames[0]
        }
    }

    Context "前缀筛选" {
        It "应该通过自定义前缀筛选" {
            $prefix = "UNIQUEPREFIX_$(Get-Random)_"
            $n = "gca_prefix_$(Get-Random)"
            Set-CustomAlias -Name $n -Value "Get-ChildItem" -AliasDespPrefix $prefix -Force -Scope "Global"

            $result = Get-CustomAlias -AliasDespPrefix $prefix
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Contain $n
        }
    }

    Context "错误处理" {
        It "不应在调用时抛出异常" {
            { Get-CustomAlias } | Should -Not -Throw
        }
    }
}
