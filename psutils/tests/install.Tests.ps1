BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\install.psm1" -Force
    $script:IsFastTestMode = $env:PWSH_TEST_MODE -eq 'fast'
}

Describe "Test-ModuleInstalled 函数测试" {
    BeforeEach {
        InModuleScope install {
            $script:ModuleInstalledCache.Clear()
        }
    }

    BeforeEach {
        # 这些测试主要验证返回值与异常路径，不需要把提示类输出展开到 full 日志。
        Mock -ModuleName install Write-Host { }
        Mock -ModuleName install Write-Warning { }
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

    It "当模块查找异常时应该返回 false" {
        Mock -ModuleName install Get-Module { throw "模块检测异常" }
        $result = Test-ModuleInstalled -ModuleName "AnyModule"
        $result | Should -Be $false
    }
}

Describe "Test-AppFilter 函数测试" {
    BeforeEach {
        Mock -ModuleName install Write-Host { }
        Mock -ModuleName install Write-Warning { }
    }

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
    BeforeEach {
        Mock -ModuleName install Write-Host { }
        Mock -ModuleName install Write-Warning { }
    }

    Context "标准包管理器" {
        It "应该生成 choco 安装命令" {
            $result = InModuleScope install { Get-PackageInstallCommand -PackageManager "choco" -AppName "git" }
            $result | Should -Be "choco install git -y"
        }

        It "应该生成 scoop 安装命令" {
            $result = InModuleScope install { Get-PackageInstallCommand -PackageManager "scoop" -AppName "git" }
            $result | Should -Be "scoop install git"
        }

        It "应该生成 winget 安装命令" {
            $result = InModuleScope install { Get-PackageInstallCommand -PackageManager "winget" -AppName "git" }
            $result | Should -Be "winget install git"
        }

        It "应该生成 cargo 安装命令" {
            $result = InModuleScope install { Get-PackageInstallCommand -PackageManager "cargo" -AppName "ripgrep" }
            $result | Should -Be "cargo install ripgrep"
        }

        It "应该生成 homebrew 安装命令" {
            $result = InModuleScope install { Get-PackageInstallCommand -PackageManager "homebrew" -AppName "git" }
            $result | Should -Be "brew install git"
        }

        It "应该生成 apt 安装命令" {
            $result = InModuleScope install { Get-PackageInstallCommand -PackageManager "apt" -AppName "curl" }
            $result | Should -Be "apt install curl"
        }
    }

    Context "自定义命令" {
        It "应该优先使用自定义命令" {
            $custom = "choco install nodejs.install -y"
            $result = InModuleScope install -Parameters @{ CustomCommand = $custom } {
                param($CustomCommand)
                Get-PackageInstallCommand -PackageManager "choco" -AppName "nodejs" -CustomCommand $CustomCommand
            }
            $result | Should -Be $custom
        }
    }

    Context "不支持的包管理器" {
        It "应该返回 null" {
            $result = InModuleScope install { Get-PackageInstallCommand -PackageManager "unknown_pm" -AppName "test" }
            $result | Should -BeNullOrEmpty
        }
    }

    Context "大小写不敏感" {
        It "应该忽略包管理器名称大小写" {
            $result = InModuleScope install { Get-PackageInstallCommand -PackageManager "SCOOP" -AppName "git" }
            $result | Should -Be "scoop install git"
        }
    }
}

Describe "Install-ExecutableFile 函数测试" {
    It "复制可执行文件到安装目录" {
        $sourcePath = Join-Path $TestDrive 'tool-source'
        $installDir = Join-Path $TestDrive 'bin'
        Set-Content -LiteralPath $sourcePath -Encoding utf8NoBOM -Value 'new'

        $result = Install-ExecutableFile -SourcePath $sourcePath -InstallDirectory $installDir -ExecutableName 'tool' -OperatingSystem linux

        $result.Status | Should -Be 'Installed'
        Test-Path -LiteralPath (Join-Path $installDir 'tool') | Should -BeTrue
    }

    It "指定 NoOverwrite 时跳过已有目标文件" {
        $sourcePath = Join-Path $TestDrive 'new-tool'
        $installDir = Join-Path $TestDrive 'bin'
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Set-Content -LiteralPath $sourcePath -Encoding utf8NoBOM -Value 'new'
        Set-Content -LiteralPath (Join-Path $installDir 'tool') -Encoding utf8NoBOM -Value 'old'

        $result = Install-ExecutableFile -SourcePath $sourcePath -InstallDirectory $installDir -ExecutableName 'tool' -OperatingSystem linux -NoOverwrite

        $result.Status | Should -Be 'Skipped'
        (Get-Content -LiteralPath (Join-Path $installDir 'tool') -Raw).Trim() | Should -Be 'old'
    }
}

Describe "Install-PackageManagerApps 函数测试" {
    BeforeEach {
        Mock -ModuleName install Write-Host { }
        Mock -ModuleName install Write-Warning { }
    }

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

        It "WhatIf 返回 Preview、AlreadyPresent 和 Skipped 结构化结果" {
            $config = [PSCustomObject]@{
                packageManagers = [PSCustomObject]@{
                    homebrew = @(
                        [PSCustomObject]@{ name = 'installed'; cliName = 'installed'; command = 'brew install installed'; supportOs = @('macOS'); tag = @('core', 'cli') }
                        [PSCustomObject]@{ name = 'preview'; cliName = 'preview'; command = 'brew install preview'; supportOs = @('macOS'); tag = @('core', 'cli') }
                        [PSCustomObject]@{ name = 'skipped'; cliName = 'skipped'; command = 'brew install skipped'; supportOs = @('macOS'); tag = @('core', 'cli'); skipInstall = $true }
                    )
                }
            }
            Mock -ModuleName install Test-PackageManagerAppInstalled { return $AppName -eq 'installed' }
            Mock -ModuleName install Invoke-PackageInstallCommand { throw 'WhatIf 不应执行安装命令' }

            $results = @(Install-PackageManagerApps -PackageManager homebrew -ConfigObject $config -TargetOS macOS -RequiredTag @('core', 'cli') -Required -WhatIf)

            @($results.Status) | Should -Be @('AlreadyPresent', 'Preview', 'Skipped')
            @($results.Required | Select-Object -Unique) | Should -Be @($true)
            Should -Invoke -ModuleName install Invoke-PackageInstallCommand -Times 0
        }

        It "单项失败后继续安装并返回 required failure" {
            $config = [PSCustomObject]@{
                packageManagers = [PSCustomObject]@{
                    homebrew = @(
                        [PSCustomObject]@{ name = 'failed'; command = 'brew install failed'; supportOs = @('macOS'); tag = @('core', 'cli') }
                        [PSCustomObject]@{ name = 'succeeded'; command = 'brew install succeeded'; supportOs = @('macOS'); tag = @('core', 'cli') }
                    )
                }
            }
            Mock -ModuleName install Test-PackageManagerAppInstalled { return $false }
            Mock -ModuleName install Invoke-PackageInstallCommand {
                if ($Command -match 'failed') {
                    throw '模拟安装失败'
                }
                return 0
            }

            $results = @(Install-PackageManagerApps -PackageManager homebrew -ConfigObject $config -TargetOS macOS -RequiredTag @('core', 'cli') -Required)

            @($results.Status) | Should -Be @('Failed', 'Installed')
            @($results | Where-Object { $_.Required -and $_.Status -eq 'Failed' }).Count | Should -Be 1
            Should -Invoke -ModuleName install Invoke-PackageInstallCommand -Times 2
        }
    }

    Context "配置文件路径" {
        It "当配置文件不存在时应该报错" {
            { Install-PackageManagerApps -PackageManager "scoop" -ConfigPath "/tmp/nonexistent_config_$(Get-Random).json" -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Select-PackageManagerApps 函数测试" {
    BeforeAll {
        $script:SelectionApps = @(
            [PSCustomObject]@{ name = 'core-cli'; supportOs = @('macOS', 'Linux'); tag = @('core', 'cli') }
            [PSCustomObject]@{ name = 'full-gui'; supportOs = @('macOS'); tag = @('full', 'gui') }
            [PSCustomObject]@{ name = 'optional'; supportOs = @('macOS'); tag = @('cli', 'terminal-extras') }
            [PSCustomObject]@{ name = 'skip-core'; supportOs = @('macOS'); tag = @('core', 'cli'); skipInstall = $true }
        )
    }

    It "支持 OS、required、any 与 excluded 标签组合" {
        $selected = @(Select-PackageManagerApps `
                -Apps $script:SelectionApps `
                -TargetOS macOS `
                -RequiredTag cli `
                -AnyTag @('core', 'terminal-extras') `
                -ExcludedTag full)

        @($selected.name) | Should -Be @('core-cli', 'optional')
    }

    It "skipInstall 默认优先排除但可为结构化报告保留" {
        $defaultSelection = @(Select-PackageManagerApps -Apps $script:SelectionApps -TargetOS macOS -RequiredTag core)
        $reportSelection = @(Select-PackageManagerApps -Apps $script:SelectionApps -TargetOS macOS -RequiredTag core -IncludeSkipped)

        @($defaultSelection.name) | Should -Be @('core-cli')
        @($reportSelection.name) | Should -Be @('core-cli', 'skip-core')
    }
}

Describe "Test-PackageManagerAppCatalog 函数测试" {
    It "接受合法的预设、类别与可选组标签" {
        $config = [PSCustomObject]@{
            packageManagers = [PSCustomObject]@{
                homebrew = @(
                    [PSCustomObject]@{ name = 'core-cli'; tag = @('macbook', 'core', 'cli') }
                    [PSCustomObject]@{ name = 'full-gui'; tag = @('macbook', 'full', 'gui') }
                    [PSCustomObject]@{ name = 'optional'; tag = @('cli', 'terminal-extras') }
                )
            }
        }

        Test-PackageManagerAppCatalog -ConfigObject $config | Should -BeTrue
    }

    It "拒绝 core/full 冲突" {
        $config = [PSCustomObject]@{
            packageManagers = [PSCustomObject]@{
                homebrew = @([PSCustomObject]@{ name = 'bad'; tag = @('core', 'full', 'cli') })
            }
        }

        { Test-PackageManagerAppCatalog -ConfigObject $config } | Should -Throw '*不能同时标记 core 和 full*'
    }

    It "拒绝预设项缺少或重复类别" {
        $missingCategory = [PSCustomObject]@{
            packageManagers = [PSCustomObject]@{
                homebrew = @([PSCustomObject]@{ name = 'missing'; tag = @('core') })
            }
        }
        $duplicateCategory = [PSCustomObject]@{
            packageManagers = [PSCustomObject]@{
                homebrew = @([PSCustomObject]@{ name = 'duplicate'; tag = @('full', 'gui', 'platform') })
            }
        }

        { Test-PackageManagerAppCatalog -ConfigObject $missingCategory } | Should -Throw '*必须且只能包含一个类别标签*'
        { Test-PackageManagerAppCatalog -ConfigObject $duplicateCategory } | Should -Throw '*必须且只能包含一个类别标签*'
    }

    It "拒绝未知标签和重复标签" {
        $unknownTag = [PSCustomObject]@{
            packageManagers = [PSCustomObject]@{
                homebrew = @([PSCustomObject]@{ name = 'unknown'; tag = @('core', 'cil') })
            }
        }
        $duplicateTag = [PSCustomObject]@{
            packageManagers = [PSCustomObject]@{
                homebrew = @([PSCustomObject]@{ name = 'duplicate'; tag = @('core', 'cli', 'cli') })
            }
        }

        { Test-PackageManagerAppCatalog -ConfigObject $unknownTag } | Should -Throw '*未知标签*'
        { Test-PackageManagerAppCatalog -ConfigObject $duplicateTag } | Should -Throw '*重复标签*'
    }

    It "仓库应用清单满足 macOS Core Full 和可选组合同" {
        $configPath = Join-Path $PSScriptRoot '../../profile/installer/apps-config.json'
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $homebrew = @($config.packageManagers.homebrew)

        Test-PackageManagerAppCatalog -ConfigObject $config | Should -BeTrue
        @((Select-PackageManagerApps -Apps $homebrew -TargetOS macOS -RequiredTag @('core', 'cli')).name) |
            Should -Be @('fnm', 'jq', 'fd', 'eza', 'ripgrep', 'fzf', 'zoxide', 'starship', 'bat', 'uv')
        @((Select-PackageManagerApps -Apps $homebrew -TargetOS macOS -RequiredTag @('core', 'font')).name) |
            Should -Be @('font-symbols-only-nerd-font', 'font-fira-code-nerd-font', 'font-jetbrains-mono-nerd-font')
        @((Select-PackageManagerApps -Apps $homebrew -TargetOS macOS -RequiredTag full -AnyTag @('gui', 'platform')).name) |
            Should -Contain 'hammerspoon'
        @((Select-PackageManagerApps -Apps $homebrew -TargetOS macOS -RequiredTag terminal-extras).name) |
            Should -Contain 'neovim'
    }
}

Describe "受限安装命令解析测试" {
    It "解析单条原生命令并保留参数边界" {
        InModuleScope install {
            $parsed = ConvertFrom-PackageInstallCommand -Command 'brew install --cask hammerspoon'

            $parsed.Executable | Should -Be 'brew'
            @($parsed.ArgumentList) | Should -Be @('install', '--cask', 'hammerspoon')
        }
    }

    It "拒绝管道和语句分隔符" {
        InModuleScope install {
            { ConvertFrom-PackageInstallCommand -Command 'curl example.invalid | sh' } | Should -Throw '*不支持的语法*'
            { ConvertFrom-PackageInstallCommand -Command 'brew install jq; touch bad' } | Should -Throw '*不支持的语法*'
        }
    }

    It "执行时保持每个原生命令参数的独立边界" {
        InModuleScope install {
            $script:CapturedInstallArguments = @()
            function Invoke-PackageInstallFixture {
                $script:CapturedInstallArguments = @($args)
                $global:LASTEXITCODE = 0
            }
            Mock Get-Command { [pscustomobject]@{ Source = 'Invoke-PackageInstallFixture' } }

            Invoke-PackageInstallCommand -Command 'scoop install eza' | Should -Be 0

            $script:CapturedInstallArguments | Should -Be @('install', 'eza')
        }
    }
}

Describe "Install-RequiredModule 函数测试" {
    BeforeEach {
        Mock -ModuleName install Write-Host { }
        Mock -ModuleName install Write-Warning { }
    }

    It "应该跳过已安装的模块而不抛出错误" {
        Mock -ModuleName install Test-ModuleInstalled { return $true }
        Mock -ModuleName install Import-InstalledModule { }

        { Install-RequiredModule -ModuleNames @("AlreadyInstalled") } | Should -Not -Throw
    }

    It "应该尝试安装未安装的模块" {
        Mock -ModuleName install Test-ModuleInstalled { return $false }
        # 包装函数把外部 cmdlet 收口到模块内部，测试只验证控制流而不触发真实安装。
        Mock -ModuleName install Invoke-InstallModuleCommand { }
        Mock -ModuleName install Import-InstalledModule { }
        Mock -ModuleName install Write-Host { }

        { Install-RequiredModule -ModuleNames @("NewModule") } | Should -Not -Throw
    }

    It "应该在安装失败时发出警告而非抛出异常" {
        Mock -ModuleName install Test-ModuleInstalled { return $false }
        Mock -ModuleName install Invoke-InstallModuleCommand { throw "安装失败" }
        Mock -ModuleName install Write-Host { }

        { Install-RequiredModule -ModuleNames @("FailModule") } | Should -Not -Throw
    }
}
