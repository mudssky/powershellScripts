<#
.SYNOPSIS
    硬件信息检测模块

.DESCRIPTION
    提供GPU显存、系统内存等硬件信息检测功能

.NOTES
    支持NVIDIA和AMD显卡检测
    支持Windows系统内存信息获取
#>

<#
.SYNOPSIS
    检测系统GPU信息

.DESCRIPTION
    检测系统是否有可用的GPU以及GPU显存大小

.OUTPUTS
    返回包含GPU信息的哈希表
#>
function Get-GpuInfo {
    try {
        # 尝试使用nvidia-smi检测NVIDIA GPU
        try {
            $nvidiaInfo = nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
            if ($nvidiaInfo -and $nvidiaInfo.Trim() -ne "") {
                $totalVramMB = [int]($nvidiaInfo | Select-Object -First 1)
                $totalVramGB = [math]::Round($totalVramMB / 1024, 1)
                return @{
                    HasGpu = $true
                    VramGB = $totalVramGB
                    GpuType = "NVIDIA"
                }
            }
        }
        catch {
            Write-Verbose "NVIDIA GPU检测失败: $($_.Exception.Message)"
        }
        
        # 尝试检测AMD GPU（通过多种方法）
        $amdGpu = Get-WmiObject -Class Win32_VideoController | Where-Object { 
            $_.Name -like "*AMD*" -or $_.Name -like "*Radeon*" -or $_.Name -like "*RX*" -or $_.Name -like "*Vega*" -or $_.Name -like "*RDNA*"
        }
        
        if ($amdGpu) {
            # 方法1: 尝试使用AdapterRAM属性
            # 检测不到大于4gb的数据
            # $adapterRam = $amdGpu.AdapterRAM
            # if ($adapterRam -and $adapterRam -gt 0) {
            #     $vramGB = [math]::Round($adapterRam / 1GB, 1)
            #     return @{
            #         HasGpu = $true
            #         VramGB = $vramGB
            #         GpuType = "AMD"
            #     }
            # }
            
            # 方法2: 尝试使用VideoMemoryType和AdapterDACType
            # $videoMemory = $amdGpu.VideoMemoryType
            # if ($videoMemory -and $videoMemory -gt 0) {
            #     $vramGB = [math]::Round($videoMemory / 1GB, 1)
            #     return @{
            #         HasGpu = $true
            #         VramGB = $vramGB
            #         GpuType = "AMD"
            #     }
            # }
            
            # 方法3: 尝试通过注册表获取显存信息
            # try {
            #     $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
            #     $gpuKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | Where-Object {
            #         $driverDesc = Get-ItemProperty -Path $_.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue
            #         $driverDesc -and ($driverDesc.DriverDesc -like "*AMD*" -or $driverDesc.DriverDesc -like "*Radeon*")
            #     }
                
            #     foreach ($key in $gpuKeys) {
            #         $memorySize = Get-ItemProperty -Path $key.PSPath -Name "HardwareInformation.MemorySize" -ErrorAction SilentlyContinue
            #         if ($memorySize -and $memorySize."HardwareInformation.MemorySize" -gt 0) {
            #             $vramGB = [math]::Round($memorySize."HardwareInformation.MemorySize" / 1GB, 1)
            #             return @{
            #                 HasGpu = $true
            #                 VramGB = $vramGB
            #                 GpuType = "AMD"
            #             }
            #         }
            #     }
            # }
            # catch {
            #     Write-Verbose "注册表方法检测AMD显存失败: $($_.Exception.Message)"
            # }
            
            # 方法4: 根据GPU型号估算显存（作为最后的备选方案）
            $gpuName = $amdGpu.Name
            $estimatedVram = 0
            
            # 根据常见AMD GPU型号估算显存
            switch -Regex ($gpuName) {
                "RX 7900 XTX|7900XTX" { $estimatedVram = 24 }
                "RX 7900 XT|7900XT" { $estimatedVram = 20 }
                "RX 7900 GRE" { $estimatedVram = 16 }
                "RX 7800 XT|7800XT" { $estimatedVram = 16 }
                "RX 7700 XT|7700XT" { $estimatedVram = 12 }
                "RX 7600|7600 XT" { $estimatedVram = 8 }
                "RX 6950 XT|6950XT" { $estimatedVram = 16 }
                "RX 6900 XT|6900XT" { $estimatedVram = 16 }
                "RX 6800 XT|6800XT" { $estimatedVram = 16 }
                "RX 6800|6800 XT" { $estimatedVram = 16 }
                "RX 6750 XT|6750XT" { $estimatedVram = 12 }
                "RX 6700 XT|6700XT" { $estimatedVram = 12 }
                "RX 6650 XT|6650XT" { $estimatedVram = 8 }
                "RX 6600 XT|6600XT" { $estimatedVram = 8 }
                "RX 6600|6500 XT" { $estimatedVram = 8 }
                "RX 6500 XT|6500XT" { $estimatedVram = 4 }
                "RX 6400" { $estimatedVram = 4 }
                "RX 5700 XT|5700XT" { $estimatedVram = 8 }
                "RX 5700|5600 XT" { $estimatedVram = 8 }
                "RX 5600 XT|5600XT" { $estimatedVram = 6 }
                "RX 5500 XT|5500XT" { $estimatedVram = 8 }
                "RX 580|RX580" { $estimatedVram = 8 }
                "RX 570|RX570" { $estimatedVram = 8 }
                "RX 560|RX560" { $estimatedVram = 4 }
                "Vega 64" { $estimatedVram = 8 }
                "Vega 56" { $estimatedVram = 8 }
                default { $estimatedVram = 4 }  # 默认估算值
            }
            
            if ($estimatedVram -gt 0) {
                Write-Warning "无法准确检测AMD GPU显存，根据型号 '$gpuName' 估算为 ${estimatedVram}GB"
                return @{
                    HasGpu = $true
                    VramGB = $estimatedVram
                    GpuType = $gpuName
                }
            }
        }
        
        # 没有检测到独立GPU
        return @{
            HasGpu = $false
            VramGB = 0
            GpuType = "None"
        }
    }
    catch {
        Write-Warning "GPU检测失败: $($_.Exception.Message)"
        return @{
            HasGpu = $false
            VramGB = 0
            GpuType = "Unknown"
        }
    }
}

<#
.SYNOPSIS
    获取系统内存信息
.DESCRIPTION
    此函数用于获取当前系统的总物理内存和可用物理内存大小。
    它支持 Windows、macOS 和 Linux 操作系统，并根据不同的操作系统调用相应的命令来获取内存信息。
.OUTPUTS
    System.Collections.Hashtable
    返回一个哈希表，包含以下键值对：
    - TotalGB (System.Double): 系统总内存大小，单位为 GB。
    - AvailableGB (System.Double): 系统可用内存大小，单位为 GB。
.EXAMPLE
    Get-SystemMemoryInfo
    返回类似 @{TotalGB=16.0; AvailableGB=8.5} 的哈希表，表示总内存16GB，可用内存8.5GB。
.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 方便在脚本中获取和显示系统内存使用情况。
    在Linux和macOS系统上，需要确保系统安装了相应的命令行工具（如 `free`, `sysctl`, `vm_stat`）。
#>
function Get-SystemMemoryInfo {
    try {
        # 检测操作系统类型
        $osType = Get-OperatingSystem
        
        switch ($osType) {
            "Windows" {
                # Windows 系统使用 WMI
                $totalMemory = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory
                $availableMemory = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty FreePhysicalMemory
                
                $totalMemoryGB = [math]::Round($totalMemory / 1GB, 1)
                $availableMemoryGB = [math]::Round(($availableMemory * 1KB) / 1GB, 1)
                
                return @{
                    TotalGB = $totalMemoryGB
                    AvailableGB = $availableMemoryGB
                }
            }
            "macOS" {
                # macOS 系统使用 sysctl 和 vm_stat
                try {
                    # 获取总内存（字节）
                    $totalMemoryBytes = sysctl -n hw.memsize
                    $totalMemoryGB = [math]::Round([long]$totalMemoryBytes / 1GB, 1)
                    
                    # 获取可用内存（使用 vm_stat）
                    $vmStat = vm_stat | Where-Object { $_ -match "Pages free:|Pages inactive:|Pages speculative:" }
                    $freePages = 0
                    $inactivePages = 0
                    $speculativePages = 0
                    
                    foreach ($line in $vmStat) {
                        if ($line -match "Pages free:\s+(\d+)") {
                            $freePages = [long]$matches[1]
                        }
                        elseif ($line -match "Pages inactive:\s+(\d+)") {
                            $inactivePages = [long]$matches[1]
                        }
                        elseif ($line -match "Pages speculative:\s+(\d+)") {
                            $speculativePages = [long]$matches[1]
                        }
                    }
                    
                    # 页面大小（通常是 4KB）
                    $pageSize = sysctl -n hw.pagesize
                    $availablePages = $freePages + $inactivePages + $speculativePages
                    $availableMemoryBytes = $availablePages * [long]$pageSize
                    $availableMemoryGB = [math]::Round($availableMemoryBytes / 1GB, 1)
                    
                    return @{
                        TotalGB = $totalMemoryGB
                        AvailableGB = $availableMemoryGB
                    }
                }
                catch {
                    Write-Warning "macOS 内存信息获取失败，尝试备用方法: $($_.Exception.Message)"
                    # 备用方法：只获取总内存
                    $totalMemoryBytes = sysctl -n hw.memsize
                    $totalMemoryGB = [math]::Round([long]$totalMemoryBytes / 1GB, 1)
                    return @{
                        TotalGB = $totalMemoryGB
                        AvailableGB = [math]::Round($totalMemoryGB * 0.7, 1)  # 估算可用内存为总内存的70%
                    }
                }
            }
            "Linux" {
                # Linux 系统使用 /proc/meminfo
                try {
                    $memInfo = Get-Content "/proc/meminfo"
                    $totalMemoryKB = 0
                    $availableMemoryKB = 0
                    $freeMemoryKB = 0
                    $buffersKB = 0
                    $cachedKB = 0
                    
                    foreach ($line in $memInfo) {
                        if ($line -match "^MemTotal:\s+(\d+)\s+kB") {
                            $totalMemoryKB = [long]$matches[1]
                        }
                        elseif ($line -match "^MemAvailable:\s+(\d+)\s+kB") {
                            $availableMemoryKB = [long]$matches[1]
                        }
                        elseif ($line -match "^MemFree:\s+(\d+)\s+kB") {
                            $freeMemoryKB = [long]$matches[1]
                        }
                        elseif ($line -match "^Buffers:\s+(\d+)\s+kB") {
                            $buffersKB = [long]$matches[1]
                        }
                        elseif ($line -match "^Cached:\s+(\d+)\s+kB") {
                            $cachedKB = [long]$matches[1]
                        }
                    }
                    
                    $totalMemoryGB = [math]::Round($totalMemoryKB / 1MB, 1)
                    
                    # 优先使用 MemAvailable，如果不存在则计算 Free + Buffers + Cached
                    if ($availableMemoryKB -gt 0) {
                        $availableMemoryGB = [math]::Round($availableMemoryKB / 1MB, 1)
                    }
                    else {
                        $availableMemoryGB = [math]::Round(($freeMemoryKB + $buffersKB + $cachedKB) / 1MB, 1)
                    }
                    
                    return @{
                        TotalGB = $totalMemoryGB
                        AvailableGB = $availableMemoryGB
                    }
                }
                catch {
                    Write-Warning "Linux 内存信息获取失败，尝试备用方法: $($_.Exception.Message)"
                    # 备用方法：使用 free 命令
                    try {
                        $freeOutput = free -m | Select-String "^Mem:"
                        if ($freeOutput -match "Mem:\s+(\d+)\s+(\d+)\s+(\d+)") {
                            $totalMemoryMB = [long]$matches[1]
                            $availableMemoryMB = [long]$matches[3]
                            
                            return @{
                                TotalGB = [math]::Round($totalMemoryMB / 1KB, 1)
                                AvailableGB = [math]::Round($availableMemoryMB / 1KB, 1)
                            }
                        }
                    }
                    catch {
                        Write-Warning "Linux 备用方法也失败: $($_.Exception.Message)"
                    }
                }
            }
            default {
                Write-Warning "不支持的操作系统: $osType"
                return @{
                    TotalGB = 0
                    AvailableGB = 0
                }
            }
        }
    }
    catch {
        Write-Warning "内存信息获取失败: $($_.Exception.Message)"
        return @{
            TotalGB = 0
            AvailableGB = 0
        }
    }
}



Export-ModuleMember -Function Get-GpuInfo, Get-SystemMemoryInfo