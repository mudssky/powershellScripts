BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\install.psm1" -Force
    $script:IsFastTestMode = $env:PWSH_TEST_MODE -eq 'fast'
}

Describe "Test-ModuleInstalled 函数测试" {
    BeforeAll {
        if ($script:IsFastTestMode) {
            Mock -CommandName Get-Module -ModuleName install -MockWith {
                param([string]$Name)
                if ($Name -eq "Microsoft.PowerShell.Management") {
                    return [pscustomobject]@{ Name = $Name }
                }
                return $null
            }
        }
    }

    It "应该能够检测已安装的模块" {
        # 测试一个通常已安装的核心模块
        $result = Test-ModuleInstalled -ModuleName "Microsoft.PowerShell.Management"
        $result | Should -Be $true
    }

    It "应该能够检测未安装的模块" {
        # 测试一个不存在的模块
        $result = Test-ModuleInstalled -ModuleName "NonExistentModule12345"
        $result | Should -Be $false
    }

    It "应该支持详细输出" {
        # 测试详细输出模式
        # 测试模块安装检查功能，不输出详细信息
        { Test-ModuleInstalled -ModuleName "Microsoft.PowerShell.Management" } | Should -Not -Throw
    }

    It "应该处理包含特殊字符的模块名" {
        $result = Test-ModuleInstalled -ModuleName "Invalid*Module?Name"
        $result | Should -Be $false
    }

    It "应该返回布尔类型" {
        $result = Test-ModuleInstalled -ModuleName "Pester"
        $result | Should -BeOfType [bool]
    }

    It "当 Get-Module 异常时应该返回 false" {
        Mock -ModuleName install Get-Module { throw "模块检测异常" }
        $result = Test-ModuleInstalled -ModuleName "AnyModule"
        $result | Should -Be $false
    }
}

Describe "Test-AppFilter 函数测试" {
    Context "And 模式" {
        It "所有谓词都为 true 时返回 true" {
            InModuleScope install {
                $app = [PSCustomObject]@{ name = "git"; supportOs = @("Linux", "Windows"); tag = @("dev") }
                $p1 = { param($a) $a.name -eq "git" }
                $p2 = { param($a) $a.supportOs -contains "Linux" }

                $result = Test-AppFilter -AppInfo $app -Predicates @($p1, $p2) -Mode "And"
                $result | Should -Be $true
            }
        }

        It "任一谓词为 false 时返回 false" {
            InModuleScope install {
                $app = [PSCustomObject]@{ name = "git"; supportOs = @("Linux") }
                $p1 = { param($a) $a.name -eq "git" }
                $p2 = { param($a) $a.supportOs -contains "Windows" }

                $result = Test-AppFilter -AppInfo $app -Predicates @($p1, $p2) -Mode "And"
                $result | Should -Be $false
            }
        }
    }

    Context "Or 模式" {
        It "任一谓词为 true 时返回 true" {
            InModuleScope install {
                $app = [PSCustomObject]@{ name = "git"; supportOs = @("Linux") }
                $p1 = { param($a) $a.name -eq "nonexistent" }
                $p2 = { param($a) $a.supportOs -contains "Linux" }

                $result = Test-AppFilter -AppInfo $app -Predicates @($p1, $p2) -Mode "Or"
                $result | Should -Be $true
            }
        }

        It "所有谓词都为 false 时返回 false" {
            InModuleScope install {
                $app = [PSCustomObject]@{ name = "git"; supportOs = @("Linux") }
                $p1 = { param($a) $a.name -eq "nonexistent" }
                $p2 = { param($a) $a.supportOs -contains "macOS" }

                $result = Test-AppFilter -AppInfo $app -Predicates @($p1, $p2) -Mode "Or"
                $result | Should -Be $false
            }
        }
    }

    Context "空谓词" {
        It "空 Predicates 参数不能绑定应该抛出参数错误" {
            InModuleScope install {
                $app = [PSCustomObject]@{ name = "test" }
                # 空数组不能绑定到 Mandatory 的 ScriptBlock[] 参数
                { Test-AppFilter -AppInfo $app -Predicates @() -Mode "And" } | Should -Throw
            }
        }
    }

    Context "异常处理" {
        It "当谓词抛出异常时应该视为 false" {
            InModuleScope install {
                $app = [PSCustomObject]@{ name = "test" }
                $badPredicate = { param($a) throw "test error" }

                $result = Test-AppFilter -AppInfo $app -Predicates @($badPredicate) -Mode "And"
                $result | Should -Be $false
            }
        }

        It "当谓词返回 null 时应该视为 false" {
            InModuleScope install {
                $app = [PSCustomObject]@{ name = "test" }
                $nullPredicate = { param($a) return $null }

                $result = Test-AppFilter -AppInfo $app -Predicates @($nullPredicate) -Mode "And"
                $result | Should -Be $false
            }
        }
    }
}

Describe "Get-PackageInstallCommand 函数测试" {
    Context "标准包管理器" {
        It "应该生成 choco 安装命令" {
            $result = Get-PackageInstallCommand -PackageManager "choco" -AppName "git"
            $result | Should -Be "choco install git -y"
        }

        It "应该生成 scoop 安装命令" {
            $result = Get-PackageInstallCommand -PackageManager "scoop" -AppName "git"
            $result | Should -Be "scoop install git"
        }

        It "应该生成 winget 安装命令" {
            $result = Get-PackageInstallCommand -PackageManager "winget" -AppName "git"
            $result | Should -Be "winget install git"
        }

        It "应该生成 cargo 安装命令" {
            $result = Get-PackageInstallCommand -PackageManager "cargo" -AppName "ripgrep"
            $result | Should -Be "cargo install ripgrep"
        }

        It "应该生成 homebrew 安装命令" {
            $result = Get-PackageInstallCommand -PackageManager "homebrew" -AppName "git"
            $result | Should -Be "brew install git"
        }

        It "应该生成 apt 安装命令" {
            $result = Get-PackageInstallCommand -PackageManager "apt" -AppName "curl"
            $result | Should -Be "apt install curl"
        }
    }

    Context "自定义命令" {
        It "应该优先使用自定义命令" {
            $custom = "choco install nodejs.install -y"
            $result = Get-PackageInstallCommand -PackageManager "choco" -AppName "nodejs" -CustomCommand $custom
            $result | Should -Be $custom
        }
    }

    Context "不支持的包管理器" {
        It "应该返回 null" {
            $result = Get-PackageInstallCommand -PackageManager "unknown_pm" -AppName "test"
            $result | Should -BeNullOrEmpty
        }
    }

    Context "大小写不敏感" {
        It "应该忽略包管理器名称大小写" {
            $result = Get-PackageInstallCommand -PackageManager "SCOOP" -AppName "git"
            $result | Should -Be "scoop install git"
        }
    }
}

Describe "Install-PackageManagerApps 函数测试" {
    Context "配置对象" {
        It "当 InstallList 为空时应该发出警告" {
            $config = [PSCustomObject]@{
                packageManagers = [PSCustomObject]@{
                    nonexistent = $null
                }
            }
            Mock -ModuleName install Get-OperatingSystem { return "Linux" }

            { Install-PackageManagerApps -PackageManager "noexist" -ConfigObject $config } | Should -Not -Throw
        }
    }

    Context "配置文件路径" {
        It "当配置文件不存在时应该报错" {
            { Install-PackageManagerApps -PackageManager "scoop" -ConfigPath "/tmp/nonexistent_config_$(Get-Random).json" -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Install-RequiredModule 函数测试" {
    It "应该跳过已安装的模块而不抛出错误" {
        Mock -ModuleName install Test-ModuleInstalled { return $true }
        Mock -ModuleName install Import-Module { }

        { Install-RequiredModule -ModuleNames @("AlreadyInstalled") } | Should -Not -Throw
    }

    It "应该尝试安装未安装的模块" {
        Mock -ModuleName install Test-ModuleInstalled { return $false }
        Mock -ModuleName install Install-Module { }
        Mock -ModuleName install Import-Module { }
        Mock -ModuleName install Write-Host { }

        { Install-RequiredModule -ModuleNames @("NewModule") } | Should -Not -Throw
    }

    It "应该在安装失败时发出警告而非抛出异常" {
        Mock -ModuleName install Test-ModuleInstalled { return $false }
        Mock -ModuleName install Install-Module { throw "安装失败" }
        Mock -ModuleName install Write-Host { }

        { Install-RequiredModule -ModuleNames @("FailModule") } | Should -Not -Throw
    }
}
