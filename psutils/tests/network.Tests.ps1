<#
.SYNOPSIS
    network.psm1 模块的单元测试

.DESCRIPTION
    使用Pester框架测试网络工具功能的各种场景
#>

Describe "Test-PortOccupation 函数测试" -Tag 'Network' {
    BeforeAll {
        Import-Module "$PSScriptRoot\..\modules\network.psm1" -Force
        $script:listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $script:listener.Start()
        $script:occupiedPort = ([System.Net.IPEndPoint]$script:listener.LocalEndpoint).Port
    }

    AfterAll {
        $script:listener.Stop()
    }

    Context "端口占用检测" {
        It "应该能够检测到已占用的端口" {
            $result = Test-PortOccupation -Port $script:occupiedPort
            $result | Should -Be $true
        }
        
        It "应该能够检测到未占用的端口" {
            $temporaryListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $temporaryListener.Start()
            $unusedPort = ([System.Net.IPEndPoint]$temporaryListener.LocalEndpoint).Port
            $temporaryListener.Stop()
            $result = Test-PortOccupation -Port $unusedPort
            $result | Should -Be $false
        }
        
        It "应该正确处理无效端口号" {
            { Test-PortOccupation -Port 0 } | Should -Throw
            { Test-PortOccupation -Port 65536 } | Should -Throw
        }
    }
}

Describe "Get-PortProcess 函数测试" -Tag 'Network', 'Slow', 'windowsOnly' {
    BeforeAll {
        Import-Module "$PSScriptRoot\..\modules\network.psm1" -Force
        $script:occupiedPort = Get-NetTCPConnection | Where-Object { $_.State -eq "Listen" } | Select-Object -First 1 -ExpandProperty LocalPort
    }

    Context "进程信息获取" {
        It "应该能够获取占用端口的进程信息" {
            if ($script:occupiedPort) {
                $result = Get-PortProcess -Port $script:occupiedPort
                ($result) | Should -Not -Be $null
                $result.Port | Should -Be $script:occupiedPort
                $result.ProcessId | Should -BeGreaterThan 0
                $result.ProcessName | Should -Not -BeNullOrEmpty
            }
            else {
                Set-ItResult -Skipped -Because "没有找到被占用的端口进行测试"
            }
        }
        
        It "应该对未占用的端口返回null" {
            # 使用一个不太可能被占用的高端口号
            $unusedPort = 65431
            $result = Get-PortProcess -Port $unusedPort
            ($result) | Should -Be $null
        }
        
        It "返回的对象应该包含所有必需的属性" {
            if ($script:occupiedPort) {
                $result = Get-PortProcess -Port $script:occupiedPort
                if ($result) {
                    $result.PSObject.Properties.Name | Should -Contain "Port"
                    $result.PSObject.Properties.Name | Should -Contain "ProcessId"
                    $result.PSObject.Properties.Name | Should -Contain "ProcessName"
                    $result.PSObject.Properties.Name | Should -Contain "Path"
                    $result.PSObject.Properties.Name | Should -Contain "CommandLine"
                }
            }
            else {
                Set-ItResult -Skipped -Because "没有找到被占用的端口进行测试"
            }
        }
    }
}

Describe "Get-PortProcess 平台边界" -Tag 'Network' {
    BeforeAll {
        Import-Module "$PSScriptRoot\..\modules\network.psm1" -Force
    }

    It "缺少 Get-NetTCPConnection 时返回明确错误" {
        if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
            Set-ItResult -Skipped -Because "当前平台提供 Get-NetTCPConnection"
            return
        }

        $errors = @()
        $result = Get-PortProcess -Port 8080 -ErrorAction SilentlyContinue -ErrorVariable errors

        $result | Should -BeNullOrEmpty
        ($errors | Out-String) | Should -Match '当前需要 Windows Get-NetTCPConnection'
    }
}

Describe "Wait-ForURL 函数测试" -Tag 'Network', 'Slow' {
    BeforeAll {
        Import-Module "$PSScriptRoot\..\modules\network.psm1" -Force
    }

    Context "URL 可达性测试" {
        It "重试失败时通过 Verbose 提供诊断" {
            $output = Wait-ForURL -DevToolsUrl "http://localhost:99997" -Timeout 1 -Interval 0.5 -Verbose 4>&1

            ($output | Out-String) | Should -Match 'URL 检查失败'
        }

        It "应该返回布尔值类型" {
            # 测试函数返回值类型，使用快速超时和短间隔避免长时间等待
            $result = Wait-ForURL -DevToolsUrl "http://localhost:99999" -Timeout 1 -Interval 0.5
            $result | Should -BeOfType [bool]
        }
        
        It "应该对不可达的URL返回false" {
            # 使用一个不存在的本地地址，快速超时和短间隔
            $result = Wait-ForURL -DevToolsUrl "http://localhost:99999" -Timeout 1 -Interval 0.5
            $result | Should -Be $false
        }
        
        It "应该正确处理超时" {
            # 测试超时功能，使用更短的超时时间和间隔
            $startTime = Get-Date
            $result = Wait-ForURL -DevToolsUrl "http://localhost:99998" -Timeout 1 -Interval 0.5
            $endTime = Get-Date
            $elapsed = ($endTime - $startTime).TotalSeconds
            
            $result | Should -Be $false
            $elapsed | Should -BeGreaterOrEqual 1
            $elapsed | Should -BeLessThan 2  # 允许一些误差
        }
        
        It "应该使用默认参数" {
            # 测试默认参数，使用快速超时
            { Wait-ForURL -Timeout 1 } | Should -Not -Throw
        }
    }
}
