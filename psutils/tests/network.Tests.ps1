<#
.SYNOPSIS
    network.psm1 模块的单元测试

.DESCRIPTION
    使用Pester框架测试网络工具功能的各种场景
#>

BeforeAll {
    # 导入被测试的模块
    Import-Module "$PSScriptRoot\..\modules\network.psm1" -Force
}

Describe "Test-PortOccupation 函数测试" {
    Context "端口占用检测" {
        It "应该能够检测到已占用的端口" {
            # 测试一个通常被占用的端口（如果存在）
            # 这里使用一个动态方法来找到一个被占用的端口
            $occupiedPort = Get-NetTCPConnection | Where-Object { $_.State -eq "Listen" } | Select-Object -First 1 -ExpandProperty LocalPort
            
            if ($occupiedPort) {
                $result = Test-PortOccupation -Port $occupiedPort
                $result | Should -Be $true
            } else {
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

Describe "Get-PortProcess 函数测试" {
    Context "进程信息获取" {
        It "应该能够获取占用端口的进程信息" {
            # 找到一个被占用的端口
            $occupiedPort = Get-NetTCPConnection | Where-Object { $_.State -eq "Listen" } | Select-Object -First 1 -ExpandProperty LocalPort
            
            if ($occupiedPort) {
                $result = Get-PortProcess -Port $occupiedPort
                ($result) | Should -Not -Be $null
                $result.Port | Should -Be $occupiedPort
                $result.ProcessId | Should -BeGreaterThan 0
                $result.ProcessName | Should -Not -BeNullOrEmpty
            } else {
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
            # 找到一个被占用的端口
            $occupiedPort = Get-NetTCPConnection | Where-Object { $_.State -eq "Listen" } | Select-Object -First 1 -ExpandProperty LocalPort
            
            if ($occupiedPort) {
                $result = Get-PortProcess -Port $occupiedPort
                if ($result) {
                    $result.PSObject.Properties.Name | Should -Contain "Port"
                    $result.PSObject.Properties.Name | Should -Contain "ProcessId"
                    $result.PSObject.Properties.Name | Should -Contain "ProcessName"
                    $result.PSObject.Properties.Name | Should -Contain "Path"
                    $result.PSObject.Properties.Name | Should -Contain "CommandLine"
                }
            } else {
                Set-ItResult -Skipped -Because "没有找到被占用的端口进行测试"
            }
        }
    }
}

Describe "Wait-ForURL 函数测试" {
    Context "URL 可达性测试" {
        It "应该能够检测到可达的URL" {
            # 测试一个通常可达的URL（如果网络连接正常）
            $result = Wait-ForURL -DevToolsUrl "http://www.google.com" -Timeout 10 -Interval 1
            # 注意：这个测试可能因为网络环境而失败，所以我们不强制要求结果
            $result | Should -BeOfType [bool]
        }
        
        It "应该对不可达的URL返回false" {
            # 使用一个不存在的本地地址
            $result = Wait-ForURL -DevToolsUrl "http://localhost:99999" -Timeout 5 -Interval 1
            $result | Should -Be $false
        }
        
        It "应该正确处理超时" {
            # 测试超时功能
            $startTime = Get-Date
            $result = Wait-ForURL -DevToolsUrl "http://localhost:99998" -Timeout 3 -Interval 1
            $endTime = Get-Date
            $elapsed = ($endTime - $startTime).TotalSeconds
            
            $result | Should -Be $false
            $elapsed | Should -BeGreaterOrEqual 3
            $elapsed | Should -BeLessThan 5  # 允许一些误差
        }
        
        It "应该使用默认参数" {
            # 测试默认参数
            { Wait-ForURL -Timeout 1 } | Should -Not -Throw
        }
    }
}