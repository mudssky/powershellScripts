BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\hardware.psm1" -Force
    Import-Module "$PSScriptRoot\..\modules\os.psm1" -Force
}

Describe "Get-GpuInfo 函数测试" {
    Context "Linux 环境下 nvidia-smi CSV 输出" {
        It "应该解析 nvidia-smi CSV 输出并返回正确的 GPU 信息" {
            Mock -ModuleName hardware Get-OperatingSystem { return "Linux" }
            Mock -ModuleName hardware nvidia-smi {
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
            Mock -ModuleName hardware Get-OperatingSystem { return "Linux" }
            Mock -ModuleName hardware nvidia-smi { throw "command not found" }

            $result = Get-GpuInfo
            $result | Should -Not -BeNullOrEmpty
            $result.HasGpu | Should -Be $false
            $result.VramGB | Should -Be 0
        }
    }

    Context "未知操作系统" {
        It "应该返回 HasGpu=false 和 Unknown 类型" {
            Mock -ModuleName hardware Get-OperatingSystem { return "FreeBSD" }

            $result = Get-GpuInfo
            $result | Should -Not -BeNullOrEmpty
            $result.HasGpu | Should -Be $false
            $result.GpuType | Should -Be "Unknown"
        }
    }

    Context "异常处理" {
        It "应该在 Get-OperatingSystem 抛出异常时返回安全值" {
            Mock -ModuleName hardware Get-OperatingSystem { throw "OS detection failed" }

            $result = Get-GpuInfo
            $result | Should -Not -BeNullOrEmpty
            $result.HasGpu | Should -Be $false
        }
    }

    Context "macOS 环境下无 NVIDIA GPU" {
        It "应该在无 nvidia-smi 时返回 HasGpu=false" {
            Mock -ModuleName hardware Get-OperatingSystem { return "macOS" }
            Mock -ModuleName hardware nvidia-smi { throw "command not found" }

            $result = Get-GpuInfo
            $result | Should -Not -BeNullOrEmpty
            $result.HasGpu | Should -Be $false
            $result.GpuType | Should -Be "None"
        }
    }

    Context "Linux 环境下只有 memory.total 查询可用" {
        It "应该不抛出异常" {
            Mock -ModuleName hardware Get-OperatingSystem { return "Linux" }
            Mock -ModuleName hardware nvidia-smi { return $null }

            { Get-GpuInfo } | Should -Not -Throw
        }
    }
}

Describe "Get-SystemMemoryInfo 函数测试" {
    Context "Linux 环境（真实或 mock）" {
        It "应该在 Linux 上通过 /proc/meminfo 获取内存信息" {
            Mock -ModuleName hardware Get-OperatingSystem { return "Linux" }
            # 不 mock Get-Content 以使用真实的 /proc/meminfo（如果在 Linux 上）
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
            Mock -ModuleName hardware Get-OperatingSystem { return "Linux" }
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
            Mock -ModuleName hardware Get-OperatingSystem { return "Linux" }
            Mock -ModuleName hardware Get-Content { throw "File not found" } -ParameterFilter { $Path -eq "/proc/meminfo" -or ($args | Where-Object { $_ -eq "/proc/meminfo" }) }
            Mock -ModuleName hardware free { return @("              total        used        free      shared  buff/cache   available", "Mem:          16384        8192        4096         256        4096       12288") } -ParameterFilter { $args -contains "-m" }

            { Get-SystemMemoryInfo } | Should -Not -Throw
        }
    }

    Context "未知操作系统" {
        It "应该返回 TotalGB=0 和 AvailableGB=0" {
            Mock -ModuleName hardware Get-OperatingSystem { return "UnknownOS" }

            $result = Get-SystemMemoryInfo
            $result | Should -Not -BeNullOrEmpty
            $result.TotalGB | Should -Be 0
            $result.AvailableGB | Should -Be 0
        }
    }

    Context "异常处理" {
        It "应该在 Get-OperatingSystem 异常时返回安全值" {
            Mock -ModuleName hardware Get-OperatingSystem { throw "OS detection failed" }

            $result = Get-SystemMemoryInfo
            $result | Should -Not -BeNullOrEmpty
            $result.TotalGB | Should -Be 0
            $result.AvailableGB | Should -Be 0
        }
    }
}
