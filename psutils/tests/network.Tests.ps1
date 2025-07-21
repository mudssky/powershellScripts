<#
.SYNOPSIS
    network.psm1 模块的单元测试

.DESCRIPTION
    使用Pester框架测试网络工具功能的各种场景
#>

BeforeAll {
    # 导入被测试的模块
    Import-Module "$PSScriptRoot\..\modules\network.psm1" -Force
    
    # 预先获取一个被占用的端口，避免在每个测试中重复查询
    $script:occupiedPort = Get-NetTCPConnection | Where-Object { $_.State -eq "Listen" } | Select-Object -First 1 -ExpandProperty LocalPort
}

Describe "Test-PortOccupation 函数测试" -Tag 'Network', 'Slow' {
    Context "端口占用检测" {
        It "应该能够检测到已占用的端口" {
            if ($script:occupiedPort) {
                $result = Test-PortOccupation -Port $script:occupiedPort
                $result | Should -Be $true
            }
            else {
                # 如果没有找到被占用的端口，跳过此测试
                Set-ItResult -Skipped -Because "没有找到被占用的端口进行测试"
            }
        }
        
        It "应该能够检测到未占用的端口" {
            # 使用一个不太可能被占用的高端口号
            $unusedPort = 65432
            $result = Test-PortOccupation -Port $unusedPort
            $result | Should -Be $false
        }
        
        It "应该正确处理无效端口号" {
            # 测试边界值
            { Test-PortOccupation -Port 0 } | Should -Not -Throw
            { Test-PortOccupation -Port 65535 } | Should -Not -Throw
        }
    }
}

Describe "Get-PortProcess 函数测试" -Tag 'Network', 'Slow' {
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

Describe "Wait-ForURL 函数测试" -Tag 'Network', 'Slow' {
    Context "URL 可达性测试" {
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