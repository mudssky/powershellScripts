BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\test.psm1" -Force
    # Also import os.psm1 since Test-ApplicationInstalled depends on Get-OperatingSystem
    Import-Module "$PSScriptRoot\..\modules\os.psm1" -Force
    $script:IsFastTestMode = $env:PWSH_TEST_MODE -eq 'fast'
}

Describe "Test-EXEProgram 函数测试" {
    BeforeAll {
        if ($script:IsFastTestMode) {
            Mock -CommandName Get-Command -ModuleName test -MockWith {
                param([string]$Name)
                if ($Name -eq "pwsh") {
                    return [pscustomobject]@{ Name = $Name }
                }
                return $null
            }
        }
    }

    It "检测存在的可执行程序返回true" {
        Test-EXEProgram -Name "pwsh" | Should -Be $true
    }

    It "检测不存在的可执行程序返回false" {
        Test-EXEProgram -Name "nonexistentprogram" | Should -Be $false
    }

    Context "NoCache参数测试" {
        It "使用NoCache参数应该跳过缓存" {
            # 第一次调用缓存结果
            $result1 = Test-EXEProgram -Name "pwsh"
            $result1 | Should -Be $true

            # 使用NoCache应该重新检查
            $result2 = Test-EXEProgram -Name "pwsh" -NoCache
            $result2 | Should -Be $true
        }

        It "NoCache对不存在的程序也应该跳过缓存" {
            $result = Test-EXEProgram -Name "nonexistentprogram_nocache_xyz" -NoCache
            $result | Should -Be $false
        }
    }

    Context "缓存机制测试" {
        It "相同程序的重复调用应该使用缓存" {
            # 先清除缓存
            Clear-EXEProgramCache

            # 第一次调用
            $result1 = Test-EXEProgram -Name "pwsh"
            $result1 | Should -Be $true

            # 第二次调用应该从缓存获取
            $result2 = Test-EXEProgram -Name "pwsh"
            $result2 | Should -Be $true
        }

        It "不存在的程序不应该被缓存" {
            Clear-EXEProgramCache

            # 不存在的程序返回false，不缓存
            $result = Test-EXEProgram -Name "definitely_not_a_program_xyz"
            $result | Should -Be $false

            # 再次调用应该重新检查（因为未缓存）
            $result2 = Test-EXEProgram -Name "definitely_not_a_program_xyz"
            $result2 | Should -Be $false
        }
    }

    Context "管道输入测试" {
        It "应该接受管道输入" {
            $results = @("pwsh") | Test-EXEProgram
            $results | Should -Be $true
        }
    }
}

Describe "Clear-EXEProgramCache 函数测试" {
    BeforeEach {
        # 确保缓存中有数据
        Clear-EXEProgramCache
        Test-EXEProgram -Name "pwsh" | Out-Null
    }

    Context "清除所有缓存" {
        It "清除所有缓存不应报错" {
            { Clear-EXEProgramCache } | Should -Not -Throw
        }

        It "清除后重新检查应该绕过缓存" {
            Clear-EXEProgramCache
            # 这应该不报错且返回正确结果
            $result = Test-EXEProgram -Name "pwsh"
            $result | Should -Be $true
        }
    }

    Context "清除特定程序缓存" {
        It "应该能够清除特定程序的缓存" {
            { Clear-EXEProgramCache -ProgramName "pwsh" } | Should -Not -Throw
        }

        It "清除不在缓存中的程序不应报错" {
            { Clear-EXEProgramCache -ProgramName "not_cached_program_xyz" } | Should -Not -Throw
        }
    }
}

Describe "Test-ArrayNotNull 函数测试" {
    It "非空数组返回true" {
        Test-ArrayNotNull -array @(1, 2, 3) | Should -Be $true
    }

    It "空数组返回false" {
        Test-ArrayNotNull -array @() | Should -Be $false
    }

    It "null值返回false" {
        Test-ArrayNotNull -array $null | Should -Be $false
    }

    Context "更多边缘情况" {
        It "单元素数组返回true" {
            Test-ArrayNotNull -array @("single") | Should -Be $true
        }

        It "包含null元素的数组返回true" {
            Test-ArrayNotNull -array @($null) | Should -Be $true
        }

        It "字符串值返回true" {
            Test-ArrayNotNull -array "hello" | Should -Be $true
        }

        It "数字值返回true" {
            Test-ArrayNotNull -array 42 | Should -Be $true
        }

        It "布尔值返回true" {
            Test-ArrayNotNull -array $true | Should -Be $true
        }

        It "包含多种类型的数组返回true" {
            Test-ArrayNotNull -array @(1, "two", $null, $true) | Should -Be $true
        }
    }
}

Describe "Test-PathHasExe 函数测试" {
    BeforeAll {
        $testDir = Join-Path $TestDrive "testdir"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        $testExe = Join-Path $testDir "test.exe"
        "" | Out-File -FilePath $testExe -Encoding utf8
    }

    It "路径包含exe文件时返回true" {
        Test-PathHasExe -Path $testDir | Should -Be $true
    }

    It "路径不包含exe文件时返回false" {
        Test-PathHasExe -Path (Join-Path $TestDrive "nonexistent") | Should -Be $false
    }

    Context "不同文件类型测试" {
        It "路径包含.ps1文件时返回true" {
            $psDir = Join-Path $TestDrive "psdir"
            New-Item -ItemType Directory -Path $psDir -Force | Out-Null
            "" | Out-File -FilePath (Join-Path $psDir "script.ps1") -Encoding utf8

            Test-PathHasExe -Path $psDir | Should -Be $true
        }

        It "路径包含.cmd文件时返回true" {
            $cmdDir = Join-Path $TestDrive "cmddir"
            New-Item -ItemType Directory -Path $cmdDir -Force | Out-Null
            "" | Out-File -FilePath (Join-Path $cmdDir "script.cmd") -Encoding utf8

            Test-PathHasExe -Path $cmdDir | Should -Be $true
        }

        It "路径包含.bat文件时返回true" {
            $batDir = Join-Path $TestDrive "batdir"
            New-Item -ItemType Directory -Path $batDir -Force | Out-Null
            "" | Out-File -FilePath (Join-Path $batDir "script.bat") -Encoding utf8

            Test-PathHasExe -Path $batDir | Should -Be $true
        }

        It "路径仅包含非可执行文件时返回false" {
            $txtDir = Join-Path $TestDrive "txtdir"
            New-Item -ItemType Directory -Path $txtDir -Force | Out-Null
            "" | Out-File -FilePath (Join-Path $txtDir "readme.txt") -Encoding utf8
            "" | Out-File -FilePath (Join-Path $txtDir "data.json") -Encoding utf8

            Test-PathHasExe -Path $txtDir | Should -Be $false
        }

        It "空目录返回false" {
            $emptyDir = Join-Path $TestDrive "emptydir"
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null

            Test-PathHasExe -Path $emptyDir | Should -Be $false
        }
    }

    Context "文件路径测试（非目录）" {
        It "直接传入.exe文件路径应该返回true" {
            $exeFile = Join-Path $TestDrive "direct.exe"
            "" | Out-File -FilePath $exeFile -Encoding utf8

            Test-PathHasExe -Path $exeFile | Should -Be $true
        }

        It "直接传入非.exe文件路径应该返回false" {
            $txtFile = Join-Path $TestDrive "direct.txt"
            "" | Out-File -FilePath $txtFile -Encoding utf8

            Test-PathHasExe -Path $txtFile | Should -Be $false
        }
    }
}

Describe "Test-PathMust 内部函数测试" {
    It "存在的路径不应该抛出异常" {
        InModuleScope test {
            { Test-PathMust -Path $TestDrive } | Should -Not -Throw
        }
    }

    It "不存在的路径应该抛出异常" {
        InModuleScope test {
            { Test-PathMust -Path "/tmp/definitely_not_exists_xyz_$(Get-Random)" } | Should -Throw
        }
    }
}

Describe "Test-ApplicationInstalled 函数测试" {
    Context "基本功能测试" {
        It "检测存在的程序应该返回true" {
            $result = Test-ApplicationInstalled -AppName "pwsh"
            $result | Should -Be $true
        }

        It "检测不存在的程序应该返回false" {
            $result = Test-ApplicationInstalled -AppName "definitely_not_installed_xyz_123"
            $result | Should -Be $false
        }

        It "函数不应该抛出异常" {
            { Test-ApplicationInstalled -AppName "pwsh" } | Should -Not -Throw
        }
    }
}

Describe "Test-MacOSCaskApp 函数测试" {
    Context "基本功能测试" {
        It "在非macOS系统上检测应该返回false（无brew）" {
            if (-not $IsMacOS) {
                # 在非 macOS 上 brew 通常不存在，且 /Applications 路径不存在
                $result = Test-MacOSCaskApp -AppName "google-chrome"
                $result | Should -Be $false
            }
        }

        It "UseBrew为false时应该检查文件路径" {
            # /Applications 在 Linux 上不存在
            $result = Test-MacOSCaskApp -AppName "nonexistent-app-xyz" -UseBrew $false
            $result | Should -Be $false
        }
    }
}

Describe "Test-HomebrewFormula 函数测试" {
    Context "基本功能测试" {
        It "在没有brew的系统上应该返回false" {
            if (-not (Get-Command "brew" -ErrorAction SilentlyContinue)) {
                $result = Test-HomebrewFormula -AppName "nonexistent-formula"
                $result | Should -Be $false
            }
        }

        It "函数不应该抛出异常" {
            { Test-HomebrewFormula -AppName "some-formula" } | Should -Not -Throw
        }
    }
}

Describe "Test-MacOSApplicationInstalled 函数测试" {
    Context "基本功能测试" {
        It "FilterCli为true时应该只检测命令行程序" {
            $result = Test-MacOSApplicationInstalled -AppName "pwsh" -FilterCli $true
            $result | Should -Be $true
        }

        It "检测不存在的程序应该返回false" {
            $result = Test-MacOSApplicationInstalled -AppName "definitely_not_installed_xyz_456"
            $result | Should -Be $false
        }
    }
}

AfterAll {
    Remove-Module test -Force -ErrorAction SilentlyContinue
    Remove-Module os -Force -ErrorAction SilentlyContinue
}
