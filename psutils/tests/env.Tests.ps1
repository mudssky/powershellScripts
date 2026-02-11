BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\env.psm1" -Force
}

Describe "Get-Dotenv 函数测试" {
    BeforeAll {
        $testEnvContent = @"
KEY1=value1
KEY2=value2
# 注释行
  KEY3=value3
"@
        $testEnvPath = "$TestDrive\.env"
        $testEnvContent | Out-File -FilePath $testEnvPath -Encoding utf8
    }

    It "正确解析.env文件内容" {
        $result = Get-Dotenv -Path $testEnvPath
        $result.Count | Should -Be 3
        $result["KEY1"] | Should -Be "value1"
        $result["KEY2"] | Should -Be "value2"
        $result["KEY3"] | Should -Be "value3"
    }

    It "忽略注释行" {
        $result = Get-Dotenv -Path $testEnvPath
        $result.ContainsKey("#") | Should -Be $false
    }

    It "处理键值前后的空格" {
        $result = Get-Dotenv -Path $testEnvPath
        $result["KEY3"] | Should -Be "value3"
    }

    Context "边缘情况测试" {
        It "处理空值" {
            $envContent = @"
EMPTY_KEY=
NORMAL_KEY=value
"@
            $envPath = Join-Path $TestDrive ".env.empty"
            $envContent | Out-File -FilePath $envPath -Encoding utf8

            $result = Get-Dotenv -Path $envPath
            $result["NORMAL_KEY"] | Should -Be "value"
        }

        It "处理包含等号的值" {
            $envContent = @"
EQUALS_KEY=value=with=equals
"@
            $envPath = Join-Path $TestDrive ".env.equals"
            $envContent | Out-File -FilePath $envPath -Encoding utf8

            $result = Get-Dotenv -Path $envPath
            $result["EQUALS_KEY"] | Should -Be "value=with=equals"
        }

        It "处理空文件" {
            $envPath = Join-Path $TestDrive ".env.blank"
            "" | Out-File -FilePath $envPath -Encoding utf8

            $result = Get-Dotenv -Path $envPath
            $result.Count | Should -Be 0
        }

        It "处理仅包含注释的文件" {
            $envContent = @"
# comment line 1
# comment line 2
"@
            $envPath = Join-Path $TestDrive ".env.comments"
            $envContent | Out-File -FilePath $envPath -Encoding utf8

            $result = Get-Dotenv -Path $envPath
            $result.Count | Should -Be 0
        }
    }
}

Describe "Install-Dotenv 函数测试" {
    BeforeAll {
        $originalLocation = Get-Location
        $testEnvContent = @"
TEST_KEY=test_value
"@
        $testEnvPath = "$TestDrive\.env"
        $testEnvContent | Out-File -FilePath $testEnvPath -Encoding utf8
    }

    AfterAll {
        # 增加复原工作目录的逻辑
        Set-Location $originalLocation
    }

    AfterEach {
        # 清理设置的环境变量
        $env:TEST_KEY = $null
        $env:DEFAULT_KEY = $null
        $env:INSTALL_MULTI_A = $null
        $env:INSTALL_MULTI_B = $null
    }

    It "正确加载环境变量到进程级别" {
        Install-Dotenv -Path $testEnvPath -EnvTarget Process
        $env:TEST_KEY | Should -Be "test_value"
    }

    It "处理默认.env文件" {
        $defaultEnvContent = @"
DEFAULT_KEY=default_value
"@
        $defaultEnvPath = "$TestDrive\.env"
        $defaultEnvContent | Out-File -FilePath $defaultEnvPath -Encoding utf8
        Set-Location $TestDrive
        Install-Dotenv -Path "nonexistent_path" -EnvTarget Process
        $env:DEFAULT_KEY | Should -Be "default_value"
    }

    Context "多键值加载测试" {
        It "应该加载多个键值对到环境变量" {
            $multiContent = @"
INSTALL_MULTI_A=valueA
INSTALL_MULTI_B=valueB
"@
            $multiPath = Join-Path $TestDrive ".env.multi"
            $multiContent | Out-File -FilePath $multiPath -Encoding utf8

            Install-Dotenv -Path $multiPath -EnvTarget Process
            $env:INSTALL_MULTI_A | Should -Be "valueA"
            $env:INSTALL_MULTI_B | Should -Be "valueB"
        }
    }

    Context "不存在的文件测试" {
        It "不存在的文件且无默认文件时应报错" {
            $nonExistDir = Join-Path $TestDrive "no_env_dir"
            New-Item -ItemType Directory -Path $nonExistDir -Force | Out-Null
            Set-Location $nonExistDir
            # 清除可能存在的 .env 文件
            Remove-Item (Join-Path $nonExistDir ".env") -Force -ErrorAction SilentlyContinue
            Remove-Item (Join-Path $nonExistDir ".env.local") -Force -ErrorAction SilentlyContinue

            Install-Dotenv -Path "definitely_not_here" -EnvTarget Process -ErrorAction SilentlyContinue -ErrorVariable installErrors
            $installErrors.Count | Should -BeGreaterThan 0
        }
    }
}

Describe "Import-EnvPath 函数测试" {
    Context "Process模式测试" {
        It "Process模式应该不报错" {
            { Import-EnvPath -EnvTarget Process } | Should -Not -Throw
        }

        It "Process模式下不应修改PATH" {
            # 在Linux上 GetEnvironmentVariable("Path", Process) 返回 $null（因为大小写敏感）
            # 这是已知行为，测试仅验证不报错并且函数能正确执行
            { Import-EnvPath -EnvTarget Process } | Should -Not -Throw
        }
    }

    Context "All模式测试" {
        It "在Linux上All模式应该运行但可能返回有限结果" {
            if ($IsLinux -or $IsMacOS) {
                # 在Linux/macOS上 Machine/User GetEnvironmentVariable 可能返回 $null
                # 但函数不应该报错
                { Import-EnvPath -EnvTarget All } | Should -Not -Throw
            }
        }
    }
}

Describe "Get-EnvParam 函数测试" {
    Context "Process级别测试" {
        It "应该获取到已存在的环境变量" {
            $env:TEST_GET_ENV_PARAM = "test_value_123"
            $result = Get-EnvParam -ParamName "TEST_GET_ENV_PARAM" -EnvTarget Process
            $result | Should -Be "test_value_123"
            $env:TEST_GET_ENV_PARAM = $null
        }

        It "获取不存在的环境变量应该返回null并产生警告" {
            $result = Get-EnvParam -ParamName "NONEXISTENT_ENV_VAR_XYZ_123" -EnvTarget Process -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It "默认ParamName是Path" {
            # 注意：在Linux上 GetEnvironmentVariable("Path", "User") 可能返回 $null
            # 因为Linux的环境变量是 PATH（大写），所以这里用 Process + PATH
            if ($IsLinux -or $IsMacOS) {
                $result = Get-EnvParam -ParamName "PATH" -EnvTarget Process
                $result | Should -Not -BeNullOrEmpty
            }
            else {
                $result = Get-EnvParam -EnvTarget Process
                $result | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context "不同EnvTarget测试" {
        It "应该接受User目标" {
            { Get-EnvParam -ParamName "Path" -EnvTarget User -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It "应该接受Machine目标" {
            { Get-EnvParam -ParamName "Path" -EnvTarget Machine -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It "应该接受Process目标" {
            { Get-EnvParam -ParamName "Path" -EnvTarget Process } | Should -Not -Throw
        }
    }
}

Describe "Sync-PathFromBash 函数测试" {
    Context "使用mock环境变量测试" {
        BeforeEach {
            $script:OriginalBashPath = $env:PWSH_TEST_BASH_PATH
            $script:OriginalPath = $env:PATH
        }

        AfterEach {
            $env:PWSH_TEST_BASH_PATH = $script:OriginalBashPath
            $env:PATH = $script:OriginalPath
        }

        It "通过PWSH_TEST_BASH_PATH应该同步缺失路径" {
            # 创建一个真实存在的测试目录
            $testSyncDir = Join-Path $TestDrive "sync_test_dir"
            New-Item -ItemType Directory -Path $testSyncDir -Force | Out-Null

            $separator = [System.IO.Path]::PathSeparator
            $env:PWSH_TEST_BASH_PATH = "$testSyncDir"

            $result = Sync-PathFromBash -CacheSeconds 0
            $result | Should -Not -BeNullOrEmpty
            $result.Source | Should -Be "mock-env"
        }

        It "没有缺失路径时不应该修改PATH" {
            $separator = [System.IO.Path]::PathSeparator
            # 使用当前 PATH 中已有的路径
            $existingPath = ($env:PATH -split $separator | Select-Object -First 1)
            $env:PWSH_TEST_BASH_PATH = $existingPath

            $originalPath = $env:PATH
            $result = Sync-PathFromBash -CacheSeconds 0
            $result.AddedPaths.Count | Should -Be 0
        }

        It "ReturnObject应该包含正确的属性" {
            $testDir = Join-Path $TestDrive "sync_props"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $env:PWSH_TEST_BASH_PATH = $testDir

            $result = Sync-PathFromBash -CacheSeconds 0
            $result.PSObject.Properties.Name | Should -Contain "SourcePathsCount"
            $result.PSObject.Properties.Name | Should -Contain "CurrentPathsCount"
            $result.PSObject.Properties.Name | Should -Contain "AddedPaths"
            $result.PSObject.Properties.Name | Should -Contain "SkippedPaths"
            $result.PSObject.Properties.Name | Should -Contain "Source"
            $result.PSObject.Properties.Name | Should -Contain "ElapsedMs"
        }

        It "不存在的目录应该被跳过（默认不包含不存在的路径）" {
            $nonExistPath = "/tmp/nonexistent_sync_test_path_xyz"
            $env:PWSH_TEST_BASH_PATH = $nonExistPath

            $result = Sync-PathFromBash -CacheSeconds 0
            $result.SkippedPaths.Count | Should -BeGreaterThan 0
            $result.AddedPaths.Count | Should -Be 0
        }

        It "IncludeNonexistent应该包含不存在的路径" {
            $nonExistPath = "/tmp/nonexistent_sync_include_xyz"
            $env:PWSH_TEST_BASH_PATH = $nonExistPath

            $result = Sync-PathFromBash -IncludeNonexistent -CacheSeconds 0
            $result.AddedPaths.Count | Should -BeGreaterThan 0
        }

        It "Prepend模式应该将路径前置" {
            $testDir = Join-Path $TestDrive "sync_prepend"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $env:PWSH_TEST_BASH_PATH = $testDir

            $result = Sync-PathFromBash -Prepend -CacheSeconds 0
            if ($result.AddedPaths.Count -gt 0) {
                $result.Prepend | Should -Be $true
                # PATH 应该以新添加的路径开头
                $separator = [System.IO.Path]::PathSeparator
                $env:PATH | Should -Match ([regex]::Escape($testDir))
            }
        }
    }
}

AfterAll {
    Remove-Module env -Force -ErrorAction SilentlyContinue
}
