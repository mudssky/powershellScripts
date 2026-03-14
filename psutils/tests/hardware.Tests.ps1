# 为 CI 环境中可能缺失的外部命令创建占位函数，使 Pester Mock 能在发现阶段稳定挂载。
# 这里的占位仅服务测试解析，不代表真实运行环境存在这些命令。
Import-Module "$PSScriptRoot\..\modules\commandDiscovery.psm1" -Force

if (-not (Find-ExecutableCommand -Name 'nvidia-smi' -CacheMisses).Found) {
    function global:nvidia-smi { }
}
if (-not (Find-ExecutableCommand -Name 'free' -CacheMisses).Found) {
    function global:free { }
}

# InModuleScope 在发现阶段就要求模块已加载，因此这里直接导入，而不是延后到 BeforeAll。
Import-Module "$PSScriptRoot\..\modules\hardware.psm1" -Force

AfterAll {
    # 清理测试专用的全局占位函数，避免污染后续会话。
    Remove-Item Function:\nvidia-smi -ErrorAction SilentlyContinue
    Remove-Item Function:\free -ErrorAction SilentlyContinue
}

InModuleScope hardware {
    Describe "Get-GpuInfo 函数测试" {
        BeforeEach {
            # 这些测试主要验证分支与返回值，不需要把 warning 刷到提交门禁日志里。
            Mock Write-Warning { }
        }

        Context "Linux 环境下 nvidia-smi CSV 输出" {
            It "应该解析 nvidia-smi CSV 输出并返回正确的 GPU 信息" {
                Mock Get-HardwareOperatingSystem { return "Linux" }
                Mock nvidia-smi {
                    if ($args -contains "--query-gpu=name, memory.total") {
                        return "NVIDIA GeForce RTX 3090, 24576"
                    }
                    return $null
                } -ParameterFilter { $args -contains "--query-gpu=name, memory.total" }

                { Get-GpuInfo } | Should -Not -Throw
            }
        }

        Context "Linux 环境下无 GPU" {
            It "应该在没有 nvidia-smi 时返回 HasGpu=false" {
                Mock Get-HardwareOperatingSystem { return "Linux" }
                Mock nvidia-smi { throw "command not found" }

                $result = Get-GpuInfo
                $result | Should -Not -BeNullOrEmpty
                $result.HasGpu | Should -Be $false
                $result.VramGB | Should -Be 0
            }
        }

        Context "未知操作系统" {
            It "应该返回 HasGpu=false 和 Unknown 类型" {
                Mock Get-HardwareOperatingSystem { return "FreeBSD" }

                $result = Get-GpuInfo
                $result | Should -Not -BeNullOrEmpty
                $result.HasGpu | Should -Be $false
                $result.GpuType | Should -Be "Unknown"
            }
        }

        Context "异常处理" {
            It "应该在 Get-HardwareOperatingSystem 抛出异常时返回安全值" {
                Mock Get-HardwareOperatingSystem { throw "OS detection failed" }

                $result = Get-GpuInfo
                $result | Should -Not -BeNullOrEmpty
                $result.HasGpu | Should -Be $false
            }
        }

        Context "macOS 环境下无 NVIDIA GPU" {
            It "应该在无 nvidia-smi 时返回 HasGpu=false" {
                Mock Get-HardwareOperatingSystem { return "macOS" }
                Mock nvidia-smi { throw "command not found" }

                $result = Get-GpuInfo
                $result | Should -Not -BeNullOrEmpty
                $result.HasGpu | Should -Be $false
                $result.GpuType | Should -Be "None"
            }
        }

        Context "Linux 环境下只有 memory.total 查询可用" {
            It "应该不抛出异常" {
                Mock Get-HardwareOperatingSystem { return "Linux" }
                Mock nvidia-smi { return $null }

                { Get-GpuInfo } | Should -Not -Throw
            }
        }
    }

    Describe "Get-SystemMemoryInfo 函数测试" {
        BeforeEach {
            # 内存测试同样只关心返回值与降级策略，不需要把 warning 展开到默认日志。
            Mock Write-Warning { }
        }

        Context "Linux 环境（真实或 mock）" {
            It "应该在 Linux 上通过 /proc/meminfo 获取内存信息" {
                Mock Get-HardwareOperatingSystem { return "Linux" }

                # 不 mock Get-Content，以便在 Linux 环境下直接验证真实 /proc/meminfo 解析。
                $hasMeminfo = Test-Path "/proc/meminfo"
                if (-not $hasMeminfo) {
                    Set-ItResult -Skipped -Because "不在 Linux 环境"
                    return
                }

                $result = Get-SystemMemoryInfo
                $result | Should -Not -BeNullOrEmpty
                $result.TotalGB | Should -BeGreaterThan 0
                $result.AvailableGB | Should -BeGreaterOrEqual 0
            }

            It "应该返回哈希表格式" {
                Mock Get-HardwareOperatingSystem { return "Linux" }

                $hasMeminfo = Test-Path "/proc/meminfo"
                if (-not $hasMeminfo) {
                    Set-ItResult -Skipped -Because "不在 Linux 环境"
                    return
                }

                $result = Get-SystemMemoryInfo
                $result | Should -BeOfType [hashtable]
                $result.Keys | Should -Contain 'TotalGB'
                $result.Keys | Should -Contain 'AvailableGB'
            }
        }

        Context "Linux 环境 - /proc/meminfo 备用路径" {
            It "当 Get-Content 失败时应该尝试 free 命令" {
                Mock Get-HardwareOperatingSystem { return "Linux" }
                Mock Get-Content { throw "File not found" } -ParameterFilter { $Path -eq "/proc/meminfo" -or ($args | Where-Object { $_ -eq "/proc/meminfo" }) }
                Mock free { return @("              total        used        free      shared  buff/cache   available", "Mem:          16384        8192        4096         256        4096       12288") } -ParameterFilter { $args -contains "-m" }

                { Get-SystemMemoryInfo } | Should -Not -Throw
            }
        }

        Context "未知操作系统" {
            It "应该返回 TotalGB=0 和 AvailableGB=0" {
                Mock Get-HardwareOperatingSystem { return "UnknownOS" }

                $result = Get-SystemMemoryInfo
                $result | Should -Not -BeNullOrEmpty
                $result.TotalGB | Should -Be 0
                $result.AvailableGB | Should -Be 0
            }
        }

        Context "异常处理" {
            It "应该在 Get-HardwareOperatingSystem 异常时返回安全值" {
                Mock Get-HardwareOperatingSystem { throw "OS detection failed" }

                $result = Get-SystemMemoryInfo
                $result | Should -Not -BeNullOrEmpty
                $result.TotalGB | Should -Be 0
                $result.AvailableGB | Should -Be 0
            }
        }
    }
}
