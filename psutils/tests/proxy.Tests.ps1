<#
.SYNOPSIS
    proxy.psm1 模块的单元测试

.DESCRIPTION
    使用Pester框架测试代理管理功能的各种场景
#>

BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\proxy.psm1" -Force

    # 保存原始代理环境变量，测试结束后恢复
    $script:savedEnvVars = @{}
    $proxyVarNames = @(
        "http_proxy", "https_proxy", "ftp_proxy", "rsync_proxy", "all_proxy", "no_proxy",
        "HTTP_PROXY", "HTTPS_PROXY", "FTP_PROXY", "RSYNC_PROXY", "ALL_PROXY", "NO_PROXY",
        "PROXY_DEFAULT_HOST", "PROXY_DEFAULT_PORT"
    )
    foreach ($varName in $proxyVarNames) {
        $script:savedEnvVars[$varName] = [System.Environment]::GetEnvironmentVariable($varName)
    }
}

AfterAll {
    # 恢复所有代理环境变量
    foreach ($entry in $script:savedEnvVars.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            Remove-Item "env:\$($entry.Key)" -ErrorAction SilentlyContinue
        }
        else {
            Set-Item "env:\$($entry.Key)" -Value $entry.Value
        }
    }
}

Describe "Close-Proxy 函数测试" -Tag 'Proxy', 'windowsOnly' {
    It "应该存在 Close-Proxy 函数" {
        Get-Command Close-Proxy -Module proxy -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe "Start-Proxy 函数测试" -Tag 'Proxy', 'windowsOnly' {
    It "应该存在 Start-Proxy 函数" {
        Get-Command Start-Proxy -Module proxy -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "应该有 URL 参数" {
        $cmd = Get-Command Start-Proxy -Module proxy
        $cmd.Parameters.Keys | Should -Contain 'URL'
    }
}

Describe "Set-Proxy 函数测试" -Tag 'Proxy' {
    BeforeEach {
        # 每个测试前清除代理环境变量，确保干净状态
        $vars = @("http_proxy", "https_proxy", "ftp_proxy", "rsync_proxy", "all_proxy", "no_proxy")
        foreach ($var in $vars) {
            Remove-Item "env:\$var" -ErrorAction SilentlyContinue
            Remove-Item "env:\$($var.ToUpper())" -ErrorAction SilentlyContinue
        }
        # 清除默认值环境变量，确保测试使用硬编码默认值
        Remove-Item "env:\PROXY_DEFAULT_HOST" -ErrorAction SilentlyContinue
        Remove-Item "env:\PROXY_DEFAULT_PORT" -ErrorAction SilentlyContinue
    }

    Context "on 命令 - 开启代理" {
        It "应该设置所有代理环境变量" {
            Mock -ModuleName proxy New-Object {
                $mockTcp = [PSCustomObject]@{}
                $mockAsync = [PSCustomObject]@{
                    AsyncWaitHandle = [PSCustomObject]@{}
                }
                $mockAsync.AsyncWaitHandle | Add-Member -MemberType ScriptMethod -Name WaitOne -Value { param($ms) return $false } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name BeginConnect -Value { param($h, $p, $a, $b) return $mockAsync } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name Close -Value {} -Force
                return $mockTcp
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Set-Proxy -Command "on" -Target "7890" -Verbose

            $env:http_proxy | Should -Be "http://127.0.0.1:7890"
            $env:https_proxy | Should -Be "http://127.0.0.1:7890"
            $env:all_proxy | Should -Be "http://127.0.0.1:7890"
            $env:HTTP_PROXY | Should -Be "http://127.0.0.1:7890"
            $env:HTTPS_PROXY | Should -Be "http://127.0.0.1:7890"
            $env:ALL_PROXY | Should -Be "http://127.0.0.1:7890"
            $env:no_proxy | Should -Not -BeNullOrEmpty
            $env:NO_PROXY | Should -Not -BeNullOrEmpty
        }

        It "使用指定端口时应该设置正确的 URL 格式" {
            Mock -ModuleName proxy New-Object {
                $mockTcp = [PSCustomObject]@{}
                $mockAsync = [PSCustomObject]@{
                    AsyncWaitHandle = [PSCustomObject]@{}
                }
                $mockAsync.AsyncWaitHandle | Add-Member -MemberType ScriptMethod -Name WaitOne -Value { param($ms) return $false } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name BeginConnect -Value { param($h, $p, $a, $b) return $mockAsync } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name Close -Value {} -Force
                return $mockTcp
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Set-Proxy -Command "on" -Target "1080"

            $env:http_proxy | Should -Be "http://127.0.0.1:1080"
            $env:https_proxy | Should -Be "http://127.0.0.1:1080"
        }

        It "使用自定义主机和端口时应该设置正确的 URL" {
            Mock -ModuleName proxy New-Object {
                $mockTcp = [PSCustomObject]@{}
                $mockAsync = [PSCustomObject]@{
                    AsyncWaitHandle = [PSCustomObject]@{}
                }
                $mockAsync.AsyncWaitHandle | Add-Member -MemberType ScriptMethod -Name WaitOne -Value { param($ms) return $false } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name BeginConnect -Value { param($h, $p, $a, $b) return $mockAsync } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name Close -Value {} -Force
                return $mockTcp
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Set-Proxy -Command "on" -Target "192.168.1.100" -Port "1080"

            $env:http_proxy | Should -Be "http://192.168.1.100:1080"
            $env:https_proxy | Should -Be "http://192.168.1.100:1080"
            $env:all_proxy | Should -Be "http://192.168.1.100:1080"
        }

        It "应该同时设置 ftp_proxy 和 rsync_proxy" {
            Mock -ModuleName proxy New-Object {
                $mockTcp = [PSCustomObject]@{}
                $mockAsync = [PSCustomObject]@{
                    AsyncWaitHandle = [PSCustomObject]@{}
                }
                $mockAsync.AsyncWaitHandle | Add-Member -MemberType ScriptMethod -Name WaitOne -Value { param($ms) return $false } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name BeginConnect -Value { param($h, $p, $a, $b) return $mockAsync } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name Close -Value {} -Force
                return $mockTcp
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Set-Proxy -Command "on" -Target "7890"

            $env:ftp_proxy | Should -Be "http://127.0.0.1:7890"
            $env:rsync_proxy | Should -Be "http://127.0.0.1:7890"
            $env:FTP_PROXY | Should -Be "http://127.0.0.1:7890"
            $env:RSYNC_PROXY | Should -Be "http://127.0.0.1:7890"
        }

        It "使用 enable 别名也应该能开启代理" {
            Mock -ModuleName proxy New-Object {
                $mockTcp = [PSCustomObject]@{}
                $mockAsync = [PSCustomObject]@{
                    AsyncWaitHandle = [PSCustomObject]@{}
                }
                $mockAsync.AsyncWaitHandle | Add-Member -MemberType ScriptMethod -Name WaitOne -Value { param($ms) return $false } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name BeginConnect -Value { param($h, $p, $a, $b) return $mockAsync } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name Close -Value {} -Force
                return $mockTcp
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Set-Proxy -Command "enable" -Target "7890"

            $env:http_proxy | Should -Be "http://127.0.0.1:7890"
        }
    }

    Context "off 命令 - 关闭代理" {
        It "应该清除所有代理环境变量" {
            # 先设置环境变量
            $env:http_proxy = "http://127.0.0.1:7890"
            $env:https_proxy = "http://127.0.0.1:7890"
            $env:ftp_proxy = "http://127.0.0.1:7890"
            $env:rsync_proxy = "http://127.0.0.1:7890"
            $env:all_proxy = "http://127.0.0.1:7890"
            $env:no_proxy = "localhost"
            $env:HTTP_PROXY = "http://127.0.0.1:7890"
            $env:HTTPS_PROXY = "http://127.0.0.1:7890"
            $env:FTP_PROXY = "http://127.0.0.1:7890"
            $env:RSYNC_PROXY = "http://127.0.0.1:7890"
            $env:ALL_PROXY = "http://127.0.0.1:7890"
            $env:NO_PROXY = "localhost"

            Set-Proxy -Command "off"

            $env:http_proxy | Should -BeNullOrEmpty
            $env:https_proxy | Should -BeNullOrEmpty
            $env:ftp_proxy | Should -BeNullOrEmpty
            $env:rsync_proxy | Should -BeNullOrEmpty
            $env:all_proxy | Should -BeNullOrEmpty
            $env:no_proxy | Should -BeNullOrEmpty
            $env:HTTP_PROXY | Should -BeNullOrEmpty
            $env:HTTPS_PROXY | Should -BeNullOrEmpty
            $env:FTP_PROXY | Should -BeNullOrEmpty
            $env:RSYNC_PROXY | Should -BeNullOrEmpty
            $env:ALL_PROXY | Should -BeNullOrEmpty
            $env:NO_PROXY | Should -BeNullOrEmpty
        }

        It "使用 disable 别名也应该能关闭代理" {
            $env:http_proxy = "http://127.0.0.1:7890"
            $env:HTTP_PROXY = "http://127.0.0.1:7890"

            Set-Proxy -Command "disable"

            $env:http_proxy | Should -BeNullOrEmpty
            $env:HTTP_PROXY | Should -BeNullOrEmpty
        }

        It "使用 unset 别名也应该能关闭代理" {
            $env:http_proxy = "http://127.0.0.1:7890"
            $env:HTTP_PROXY = "http://127.0.0.1:7890"

            Set-Proxy -Command "unset"

            $env:http_proxy | Should -BeNullOrEmpty
            $env:HTTP_PROXY | Should -BeNullOrEmpty
        }

        It "在没有代理设置时关闭也不应该报错" {
            { Set-Proxy -Command "off" } | Should -Not -Throw
        }
    }

    Context "status 命令 - 查看代理状态" {
        It "未设置代理时不应该抛出异常" {
            { Set-Proxy -Command "status" } | Should -Not -Throw
        }

        It "设置代理后查看状态不应该抛出异常" {
            $env:http_proxy = "http://127.0.0.1:7890"
            $env:no_proxy = "localhost"

            Mock -ModuleName proxy New-Object {
                $mockTcp = [PSCustomObject]@{}
                $mockAsync = [PSCustomObject]@{
                    AsyncWaitHandle = [PSCustomObject]@{}
                }
                $mockAsync.AsyncWaitHandle | Add-Member -MemberType ScriptMethod -Name WaitOne -Value { param($ms) return $false } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name BeginConnect -Value { param($h, $p, $a, $b) return $mockAsync } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name Close -Value {} -Force
                return $mockTcp
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            { Set-Proxy -Command "status" } | Should -Not -Throw
        }

        It "info 和 show 别名也应该能正常工作" {
            { Set-Proxy -Command "info" } | Should -Not -Throw
            { Set-Proxy -Command "show" } | Should -Not -Throw
        }
    }

    Context "test 命令 - 测试代理连接" {
        It "未设置代理时执行 test 不应该抛出异常" {
            Mock -ModuleName proxy Get-Command { return $true }
            # Mock curl 命令以避免实际网络请求
            Mock -ModuleName proxy curl { return "HTTP/1.1 200 OK" }

            { Set-Proxy -Command "test" } | Should -Not -Throw
        }

        It "设置代理后执行 test 不应该抛出异常" {
            $env:http_proxy = "http://127.0.0.1:7890"

            Mock -ModuleName proxy Get-Command { return $true }
            Mock -ModuleName proxy curl { return "HTTP/1.1 200 OK" }

            { Set-Proxy -Command "test" } | Should -Not -Throw
        }
    }

    Context "help 命令" {
        It "执行 help 不应该抛出异常" {
            { Set-Proxy -Command "help" } | Should -Not -Throw
        }
    }

    Context "默认行为" {
        It "不传参数时应该默认执行 status 命令且不抛出异常" {
            { Set-Proxy } | Should -Not -Throw
        }
    }

    Context "环境变量默认值" {
        It "应该使用 PROXY_DEFAULT_HOST 环境变量作为默认主机" {
            $env:PROXY_DEFAULT_HOST = "10.0.0.1"

            Mock -ModuleName proxy New-Object {
                $mockTcp = [PSCustomObject]@{}
                $mockAsync = [PSCustomObject]@{
                    AsyncWaitHandle = [PSCustomObject]@{}
                }
                $mockAsync.AsyncWaitHandle | Add-Member -MemberType ScriptMethod -Name WaitOne -Value { param($ms) return $false } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name BeginConnect -Value { param($h, $p, $a, $b) return $mockAsync } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name Close -Value {} -Force
                return $mockTcp
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Set-Proxy -Command "on"

            $env:http_proxy | Should -Be "http://10.0.0.1:7890"

            # 清理
            Remove-Item "env:\PROXY_DEFAULT_HOST" -ErrorAction SilentlyContinue
        }

        It "应该使用 PROXY_DEFAULT_PORT 环境变量作为默认端口" {
            $env:PROXY_DEFAULT_PORT = "1080"

            Mock -ModuleName proxy New-Object {
                $mockTcp = [PSCustomObject]@{}
                $mockAsync = [PSCustomObject]@{
                    AsyncWaitHandle = [PSCustomObject]@{}
                }
                $mockAsync.AsyncWaitHandle | Add-Member -MemberType ScriptMethod -Name WaitOne -Value { param($ms) return $false } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name BeginConnect -Value { param($h, $p, $a, $b) return $mockAsync } -Force
                $mockTcp | Add-Member -MemberType ScriptMethod -Name Close -Value {} -Force
                return $mockTcp
            } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }

            Set-Proxy -Command "on"

            $env:http_proxy | Should -Be "http://127.0.0.1:1080"

            # 清理
            Remove-Item "env:\PROXY_DEFAULT_PORT" -ErrorAction SilentlyContinue
        }
    }
}
