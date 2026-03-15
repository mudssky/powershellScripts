<#
.SYNOPSIS
    help.psm1 模块的单元测试

.DESCRIPTION
    使用Pester框架测试帮助搜索功能的各种场景
#>

BeforeAll {
    # 导入被测试的模块
    Import-Module "$PSScriptRoot\..\modules\help.psm1" -Force

    # 为搜索类测试构造最小帮助夹具，避免每次断言都递归扫描整个 psutils 目录。
    $script:HelpFixtureRoot = Join-Path $TestDrive 'help-fixtures'
    New-Item -ItemType Directory -Path $script:HelpFixtureRoot -Force | Out-Null

    @'
<#
.SYNOPSIS
    返回测试环境里的操作系统

.DESCRIPTION
    用于帮助搜索测试的最小函数集合。
#>
function Get-OperatingSystem {
    param()
    return 'TestOS'
}

<#
.SYNOPSIS
    install 测试工具

.DESCRIPTION
    用于验证关键词搜索会命中 synopsis 和 description。
#>
function Install-TestTool {
    param()
    return 'ok'
}

function Get-Alpha {
    <#
    .SYNOPSIS
        Alpha 函数
    #>
    param()
}

function Get-Beta {
    param()
}

function Set-Gamma {
    param()
}

function Invoke-Delta {
    param()
}
'@ | Set-Content -Path (Join-Path $script:HelpFixtureRoot 'fixture-help.psm1') -Encoding utf8NoBOM

    @'
<#
.SYNOPSIS
    install script helper
#>
param()

Write-Output 'fixture script'
'@ | Set-Content -Path (Join-Path $script:HelpFixtureRoot 'install-helper.ps1') -Encoding utf8NoBOM
}

Describe "Search-ModuleHelp 函数测试" {
    Context "基本搜索功能" {
        It "应该能够搜索到包含指定关键词的函数" {
            $results = Search-ModuleHelp -SearchTerm "install" -ModulePath $script:HelpFixtureRoot -WarningAction SilentlyContinue
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeGreaterThan 0
            $results.Name | Should -Contain "Install-TestTool"
        }

        It "应该能够精确搜索指定的函数名" {
            $results = Search-ModuleHelp -FunctionName "Get-OperatingSystem" -ModulePath $script:HelpFixtureRoot -WarningAction SilentlyContinue
            if ($results) {
                $results.Name | Should -Be "Get-OperatingSystem"
            }
        }

        It "搜索不存在的函数应该返回空结果" {
            $results = Search-ModuleHelp -FunctionName "NonExistentFunction" -ModulePath $script:HelpFixtureRoot -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
        }

        It "不指定搜索词应该返回所有函数" {
            $results = Search-ModuleHelp -ModulePath $script:HelpFixtureRoot -WarningAction SilentlyContinue
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeGreaterThan 5
        }
    }

    Context "参数验证" {
        It "无效的模块路径应该产生错误" {
            $missingPath = Join-Path $TestDrive 'missing-help-fixture'
            { Search-ModuleHelp -SearchTerm "test" -ModulePath $missingPath -ErrorAction Stop -WarningAction SilentlyContinue } | Should -Throw
        }
    }

    Context "结果格式验证" {
        It "返回的结果应该包含必要的属性" {
            $results = Search-ModuleHelp -SearchTerm "Get" -ModulePath $script:HelpFixtureRoot -WarningAction SilentlyContinue
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

    Context "UseGetHelp模式测试" {
        It "使用UseGetHelp应该不报错" {
            { Search-ModuleHelp -SearchTerm "Get" -ModulePath $script:HelpFixtureRoot -UseGetHelp -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context "IncludeScripts模式测试" {
        It "IncludeScripts应该包含.ps1文件" {
            $results = Search-ModuleHelp -SearchTerm "install" -ModulePath $script:HelpFixtureRoot -IncludeScripts -WarningAction SilentlyContinue
            $results | Should -Not -BeNullOrEmpty
            ($results | Where-Object { $_.Type -eq 'Script' }).Count | Should -BeGreaterThan 0
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

            $result = Convert-HelpBlock -HelpBlock $helpBlock -Name "Test-Function" -FilePath "/tmp/test.psm1" -Type "Function"

            $result.Name | Should -Be "Test-Function"
            $result.Synopsis | Should -Be "测试函数"
            $result.Description | Should -Be "这是一个测试函数的详细描述"
            $result.Parameters.Count | Should -Be 1
            $result.Parameters[0].Name | Should -Be "TestParam"
            $result.Examples.Count | Should -Be 1
        }

        It "应该能够处理空的帮助块" {
            $result = Convert-HelpBlock -HelpBlock "" -Name "Test-Function" -FilePath "/tmp/test.psm1" -Type "Function"

            $result.Name | Should -Be "Test-Function"
            $result.Synopsis | Should -Be "无帮助信息"
            $result.Description | Should -Be "无帮助信息"
        }

        It "应该能够处理只有Synopsis的帮助块" {
            $helpBlock = @"
.SYNOPSIS
    仅有概要信息
"@
            $result = Convert-HelpBlock -HelpBlock $helpBlock -Name "Test-SynopsisOnly" -FilePath "/tmp/test.psm1" -Type "Function"
            $result.Synopsis | Should -Be "仅有概要信息"
            # Description应该回退到Synopsis
            $result.Description | Should -Be "仅有概要信息"
        }

        It "应该能够解析多个参数" {
            $helpBlock = @"
.SYNOPSIS
    多参数测试

.PARAMETER Param1
    第一个参数

.PARAMETER Param2
    第二个参数

.PARAMETER Param3
    第三个参数
"@
            $result = Convert-HelpBlock -HelpBlock $helpBlock -Name "Test-MultiParam" -FilePath "/tmp/test.psm1" -Type "Function"
            $result.Parameters.Count | Should -Be 3
            $result.Parameters[0].Name | Should -Be "Param1"
            $result.Parameters[1].Name | Should -Be "Param2"
            $result.Parameters[2].Name | Should -Be "Param3"
        }

        It "应该能够解析多个示例" {
            $helpBlock = @"
.SYNOPSIS
    多示例测试

.EXAMPLE
    Get-Thing -Name "foo"
    获取foo

.EXAMPLE
    Get-Thing -Name "bar" -Verbose
    获取bar并显示详细信息
"@
            $result = Convert-HelpBlock -HelpBlock $helpBlock -Name "Test-MultiExample" -FilePath "/tmp/test.psm1" -Type "Function"
            $result.Examples.Count | Should -Be 2
        }

        It "应该正确设置FilePath和ModuleName" {
            $result = Convert-HelpBlock -HelpBlock ".SYNOPSIS`n    test" -Name "Test-Path" -FilePath "/tmp/mymod.psm1" -Type "Function"
            $result.FilePath | Should -Be "/tmp/mymod.psm1"
            $result.ModuleName | Should -Be "mymod"
        }

        It "应该正确设置Type属性" {
            $result = Convert-HelpBlock -HelpBlock ".SYNOPSIS`n    test" -Name "Test-Type" -FilePath "/tmp/test.psm1" -Type "Script"
            $result.Type | Should -Be "Script"
        }
    }
}

Describe "InModuleScope 内部函数测试" {
    Context "Search-WithCustomParsing 内部函数" {
        It "应该解析模块文件中的函数" {
            InModuleScope help {
                # 创建一个临时的测试模块文件
                $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "helptest_$(Get-Random)"
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                $tempFile = Join-Path $tempDir "testmod.psm1"
                @"
<#
.SYNOPSIS
    测试函数Synopsis

.DESCRIPTION
    测试函数Description
#>
function Test-InternalFunc {
    param()
    Write-Host "test"
}
"@ | Set-Content -Path $tempFile -Encoding UTF8

                $files = @(Get-Item $tempFile)
                $results = Search-WithCustomParsing -Files $files
                $results | Should -Not -BeNullOrEmpty
                $results[0].Name | Should -Be "Test-InternalFunc"
                $results[0].Synopsis | Should -Match "测试函数Synopsis"

                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "按搜索词过滤结果" {
            InModuleScope help {
                $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "helptest_filter_$(Get-Random)"
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                $tempFile = Join-Path $tempDir "filtermod.psm1"
                @"
<#
.SYNOPSIS
    Alpha函数
#>
function Get-Alpha { }

<#
.SYNOPSIS
    Beta函数
#>
function Get-Beta { }
"@ | Set-Content -Path $tempFile -Encoding UTF8

                $files = @(Get-Item $tempFile)
                $results = Search-WithCustomParsing -Files $files -SearchTerm "Alpha"
                $results.Count | Should -Be 1
                $results[0].Name | Should -Be "Get-Alpha"

                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Search-WithGetHelp 内部函数" {
        It "应该能调用不报错" {
            InModuleScope help {
                $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "helptest_gethelp_$(Get-Random)"
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                $tempFile = Join-Path $tempDir "gethelpmod.psm1"
                @"
function Test-GetHelpFunc {
    <#
    .SYNOPSIS
        GetHelp模式测试函数
    #>
    param()
    Write-Host "test"
}
"@ | Set-Content -Path $tempFile -Encoding UTF8

                $files = @(Get-Item $tempFile)
                { Search-WithGetHelp -Files $files } | Should -Not -Throw

                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "Find-PSUtilsFunction 函数测试" {
    Context "快速搜索功能" {
        It "应该能够搜索psutils模块中的函数" {
            # 这里只验证 wrapper 是否把参数透传给 Search-ModuleHelp；
            # 真实搜索行为已在 Search-ModuleHelp 自己的夹具测试中覆盖。
            InModuleScope help {
                Mock Search-ModuleHelp {
                    @(
                        [PSCustomObject]@{
                            Name = 'Get-OperatingSystem'
                            Synopsis = 'fixture'
                        }
                    )
                }

                $results = Find-PSUtilsFunction "Get"
                $results | Should -Not -BeNullOrEmpty
                $results[0].Name | Should -Be 'Get-OperatingSystem'
                Should -Invoke Search-ModuleHelp -Times 1 -Exactly
            }
        }

        It "无参数调用应该返回所有函数" {
            InModuleScope help {
                Mock Search-ModuleHelp {
                    @(
                        [PSCustomObject]@{ Name = 'Get-One'; Synopsis = 'one' }
                        [PSCustomObject]@{ Name = 'Get-Two'; Synopsis = 'two' }
                    )
                }

                $results = Find-PSUtilsFunction
                $results | Should -Not -BeNullOrEmpty
                $results.Count | Should -Be 2
            }
        }

        It "搜索不存在的函数应返回空" {
            InModuleScope help {
                Mock Search-ModuleHelp { $null }
                $results = Find-PSUtilsFunction "ZZZNonExistentFunctionXYZ"
                $results | Should -BeNullOrEmpty
            }
        }

        It "应该返回包含正确属性的对象" {
            InModuleScope help {
                Mock Search-ModuleHelp {
                    @(
                        [PSCustomObject]@{
                            Name = 'Get-OperatingSystem'
                            Synopsis = 'fixture synopsis'
                        }
                    )
                }

                $results = Find-PSUtilsFunction "Get"
                $results[0].PSObject.Properties.Name | Should -Contain "Name"
                $results[0].PSObject.Properties.Name | Should -Contain "Synopsis"
            }
        }
    }
}

Describe "Get-FunctionHelp 函数测试" {
    Context "函数帮助获取" {
        It "应该能够获取指定函数的帮助信息" {
            InModuleScope help {
                Mock Search-ModuleHelp {
                    [PSCustomObject]@{
                        Name = 'Get-OperatingSystem'
                        Synopsis = 'fixture synopsis'
                    }
                }

                $results = Get-FunctionHelp "Get-OperatingSystem" -ModulePath $script:HelpFixtureRoot
                $results.Name | Should -Be "Get-OperatingSystem"
                Should -Invoke Search-ModuleHelp -Times 1 -Exactly
            }
        }

        It "获取不存在的函数应该返回空" {
            InModuleScope help {
                Mock Search-ModuleHelp { $null }

                $results = Get-FunctionHelp "ZZZNonExistentXYZ" -ModulePath $script:HelpFixtureRoot
                $results | Should -BeNullOrEmpty
            }
        }

        It "应该支持UseGetHelp参数" {
            InModuleScope help {
                Mock Search-ModuleHelp {
                    [PSCustomObject]@{
                        Name = 'Get-OperatingSystem'
                        Synopsis = 'fixture synopsis'
                    }
                }

                { Get-FunctionHelp "Get-OperatingSystem" -ModulePath $script:HelpFixtureRoot -UseGetHelp } | Should -Not -Throw
                Should -Invoke Search-ModuleHelp -Times 1 -Exactly
            }
        }

        It "应该支持IncludeScripts参数" {
            InModuleScope help {
                Mock Search-ModuleHelp {
                    [PSCustomObject]@{
                        Name = 'install-helper'
                        Type = 'Script'
                        Synopsis = 'fixture script'
                    }
                }

                { Get-FunctionHelp "install-helper" -ModulePath $script:HelpFixtureRoot -IncludeScripts } | Should -Not -Throw
                Should -Invoke Search-ModuleHelp -Times 1 -Exactly
            }
        }
    }
}

# 性能比较已迁移到 tests/benchmarks/HelpSearch.Benchmark.ps1，
# 这里保留功能性搜索断言，不再让 full 门禁承担诊断型 benchmark 开销。

AfterAll {
    # 清理测试环境
    Remove-Module "help" -Force -ErrorAction SilentlyContinue
}
