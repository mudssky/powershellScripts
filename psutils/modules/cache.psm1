# 模块级别初始化：创建缓存目录
$script:CacheBaseDir = Join-Path $env:LOCALAPPDATA "PowerShellCache"
if (-not (Test-Path $script:CacheBaseDir)) {
    New-Item -ItemType Directory -Path $script:CacheBaseDir | Out-Null
}

# 模块级别变量：缓存统计
$script:CacheStats = @{
    Hits = 0
    Misses = 0
    Writes = 0
    CleanupRuns = 0
    LastCleanup = $null
}

# 模块级别变量：MD5哈希提供程序（重用以提高性能）
$script:MD5Provider = [System.Security.Cryptography.MD5]::Create()

<#
.SYNOPSIS
    清理过期的缓存文件
    扫描缓存目录并删除超过指定时间的缓存文件

.DESCRIPTION
    Clear-ExpiredCache 函数用于清理缓存目录中的过期文件。
    支持按时间清理和强制清理所有缓存文件。
    
.PARAMETER MaxAge
    缓存文件的最大保留时间。超过此时间的文件将被删除。默认为7天。

.PARAMETER Force
    强制删除所有缓存文件，忽略时间限制。

.PARAMETER WhatIf
    显示将要删除的文件，但不实际执行删除操作。

.EXAMPLE
    Clear-ExpiredCache
    清理7天前的过期缓存文件

.EXAMPLE
    Clear-ExpiredCache -MaxAge ([TimeSpan]::FromDays(3))
    清理3天前的过期缓存文件

.EXAMPLE
    Clear-ExpiredCache -Force
    强制清理所有缓存文件

.EXAMPLE
    Clear-ExpiredCache -WhatIf
    预览将要删除的过期缓存文件

.OUTPUTS
    System.Object
    返回清理统计信息
#>
function Clear-ExpiredCache {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [TimeSpan]$MaxAge = [TimeSpan]::FromDays(7),

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $cleanupStats = @{
        TotalFiles = 0
        ExpiredFiles = 0
        DeletedFiles = 0
        FreedSpace = 0
        Errors = @()
    }

    try {
        # 获取所有缓存文件
        $cacheFiles = Get-ChildItem -Path $script:CacheBaseDir -Filter "*.cache.*" -File -ErrorAction SilentlyContinue
        $cleanupStats.TotalFiles = $cacheFiles.Count

        if ($cleanupStats.TotalFiles -eq 0) {
            Write-Verbose "缓存目录中没有找到缓存文件"
            return $cleanupStats
        }

        $cutoffTime = (Get-Date) - $MaxAge
        Write-Verbose "清理截止时间: $cutoffTime"

        foreach ($file in $cacheFiles) {
            $shouldDelete = $false
            
            if ($Force) {
                $shouldDelete = $true
                Write-Verbose "强制删除模式: $($file.Name)"
            }
            elseif ($file.LastWriteTime -lt $cutoffTime) {
                $shouldDelete = $true
                $cleanupStats.ExpiredFiles++
                Write-Verbose "过期文件: $($file.Name) (最后修改: $($file.LastWriteTime))"
            }

            if ($shouldDelete) {
                $fileSize = $file.Length
                
                if ($PSCmdlet.ShouldProcess($file.FullName, "删除过期缓存文件")) {
                    if ($WhatIfPreference) {
                        Write-Host "[WhatIf] 将删除: $($file.FullName) (大小: $([math]::Round($fileSize/1KB, 2)) KB)" -ForegroundColor Yellow
                        $cleanupStats.DeletedFiles++
                        $cleanupStats.FreedSpace += $fileSize
                    }
                    else {
                        try {
                            Remove-Item -Path $file.FullName -Force
                            $cleanupStats.DeletedFiles++
                            $cleanupStats.FreedSpace += $fileSize
                            Write-Verbose "已删除: $($file.Name)"
                        }
                        catch {
                            $errorMsg = "删除文件失败: $($file.Name) - $($_.Exception.Message)"
                            $cleanupStats.Errors += $errorMsg
                            Write-Warning $errorMsg
                        }
                    }
                }
            }
        }

        # 更新统计信息
        $script:CacheStats.CleanupRuns++
        $script:CacheStats.LastCleanup = Get-Date

        # 输出清理结果
        $freedSpaceKB = [math]::Round($cleanupStats.FreedSpace / 1KB, 2)
        $message = if ($WhatIfPreference) {
            "[预览] 将清理 $($cleanupStats.DeletedFiles) 个文件，释放 $freedSpaceKB KB 空间"
        } else {
            "已清理 $($cleanupStats.DeletedFiles) 个文件，释放 $freedSpaceKB KB 空间"
        }
        
        Write-Host $message -ForegroundColor Green
        
        if ($cleanupStats.Errors.Count -gt 0) {
            Write-Warning "清理过程中遇到 $($cleanupStats.Errors.Count) 个错误"
        }

        return $cleanupStats
    }
    catch {
        $errorMsg = "缓存清理失败: $($_.Exception.Message)"
        Write-Error $errorMsg
        $cleanupStats.Errors += $errorMsg
        return $cleanupStats
    }
}

<#
.SYNOPSIS
    获取缓存统计信息
    显示缓存使用情况和性能统计

.DESCRIPTION
    Get-CacheStats 函数提供缓存系统的详细统计信息，包括：
    - 缓存命中率
    - 缓存文件数量和大小
    - 清理历史
    - 性能指标

.PARAMETER Detailed
    显示详细的缓存文件信息

.EXAMPLE
    Get-CacheStats
    显示基本缓存统计信息

.EXAMPLE
    Get-CacheStats -Detailed
    显示详细的缓存统计信息，包括文件列表

.OUTPUTS
    System.Object
    返回缓存统计信息对象
#>
function Get-CacheStats {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Detailed
    )

    $stats = @{
        CacheDirectory = $script:CacheBaseDir
        RuntimeStats = $script:CacheStats.Clone()
        FileStats = @{
            TotalFiles = 0
            TotalSize = 0
            XMLFiles = 0
            TextFiles = 0
            OldestFile = $null
            NewestFile = $null
        }
        Performance = @{
            HitRate = 0
            TotalRequests = 0
        }
    }

    try {
        # 获取缓存文件信息
        $cacheFiles = Get-ChildItem -Path $script:CacheBaseDir -Filter "*.cache.*" -File -ErrorAction SilentlyContinue
        $stats.FileStats.TotalFiles = $cacheFiles.Count

        if ($cacheFiles.Count -gt 0) {
            $stats.FileStats.TotalSize = ($cacheFiles | Measure-Object -Property Length -Sum).Sum
            $stats.FileStats.XMLFiles = ($cacheFiles | Where-Object { $_.Extension -eq '.xml' }).Count
            $stats.FileStats.TextFiles = ($cacheFiles | Where-Object { $_.Extension -eq '.txt' }).Count
            $stats.FileStats.OldestFile = ($cacheFiles | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime
            $stats.FileStats.NewestFile = ($cacheFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
        }

        # 计算性能指标
        $totalRequests = $script:CacheStats.Hits + $script:CacheStats.Misses
        $stats.Performance.TotalRequests = $totalRequests
        if ($totalRequests -gt 0) {
            $stats.Performance.HitRate = [math]::Round(($script:CacheStats.Hits / $totalRequests) * 100, 2)
        }

        # 显示统计信息
        Write-Host "=== 缓存统计信息 ===" -ForegroundColor Cyan
        Write-Host "缓存目录: $($stats.CacheDirectory)" -ForegroundColor Gray
        Write-Host "文件总数: $($stats.FileStats.TotalFiles) (XML: $($stats.FileStats.XMLFiles), Text: $($stats.FileStats.TextFiles))" -ForegroundColor White
        Write-Host "总大小: $([math]::Round($stats.FileStats.TotalSize / 1KB, 2)) KB" -ForegroundColor White
        Write-Host "缓存命中: $($script:CacheStats.Hits) 次" -ForegroundColor Green
        Write-Host "缓存未命中: $($script:CacheStats.Misses) 次" -ForegroundColor Yellow
        Write-Host "缓存写入: $($script:CacheStats.Writes) 次" -ForegroundColor Blue
        Write-Host "命中率: $($stats.Performance.HitRate)%" -ForegroundColor $(if ($stats.Performance.HitRate -gt 70) { 'Green' } elseif ($stats.Performance.HitRate -gt 40) { 'Yellow' } else { 'Red' })
        Write-Host "清理次数: $($script:CacheStats.CleanupRuns) 次" -ForegroundColor Gray
        
        if ($script:CacheStats.LastCleanup) {
            Write-Host "最后清理: $($script:CacheStats.LastCleanup)" -ForegroundColor Gray
        }

        if ($stats.FileStats.TotalFiles -gt 0) {
            Write-Host "最旧文件: $($stats.FileStats.OldestFile)" -ForegroundColor Gray
            Write-Host "最新文件: $($stats.FileStats.NewestFile)" -ForegroundColor Gray
        }

        if ($Detailed -and $cacheFiles.Count -gt 0) {
            Write-Host "\n=== 详细文件信息 ===" -ForegroundColor Cyan
            $cacheFiles | Sort-Object LastWriteTime -Descending | ForEach-Object {
                $age = (Get-Date) - $_.LastWriteTime
                $sizeKB = [math]::Round($_.Length / 1KB, 2)
                Write-Host "$($_.Name) - $sizeKB KB - $([math]::Round($age.TotalHours, 1)) 小时前" -ForegroundColor Gray
            }
        }

        return $stats
    }
    catch {
        Write-Error "获取缓存统计信息失败: $($_.Exception.Message)"
        return $stats
    }
}

<#
.SYNOPSIS
    PowerShell 缓存模块 - 智能缓存系统 v1.4.0
    提供高性能的函数结果缓存功能，支持自动过期、强制刷新、无缓存模式和多种缓存格式

.DESCRIPTION
    Invoke-WithCache 函数提供了一个强大的缓存系统，可以缓存任何 PowerShell 脚本块的执行结果。
    主要特性：
    - 智能缓存：自动管理缓存的创建、读取和过期
    - 灵活过期：支持自定义缓存过期时间
    - 强制刷新：Force 参数可以强制重新执行并更新缓存
    - 无缓存模式：NoCache 参数可以跳过缓存直接执行
    - 多种缓存格式：支持 XML 和 Text 两种缓存类型
      - XML 格式：适合复杂对象，保持完整的数据类型信息（默认）
      - Text 格式：适合字符串内容，使用纯文本存储，体积更小
    - 错误处理：完善的错误处理和日志记录
    - 性能监控：详细的 Verbose 输出用于性能分析
    
    缓存文件命名规则：
    - XML 格式：{MD5Hash}.cache.xml
    - Text 格式：{MD5Hash}.cache.txt
    
    性能优化：
    - 使用 MD5 哈希算法生成文件名（比 SHA256 更快）
    - 模块级缓存目录创建（避免重复检查）
    - 智能缓存命中检测

.PARAMETER Key
    缓存的唯一标识符。相同的Key将使用相同的缓存文件。

.PARAMETER ScriptBlock
    要执行的脚本块。只有在缓存未命中或过期时才会执行。

.PARAMETER MaxAge
    缓存的最大有效期。默认为1小时。超过此时间的缓存将被视为过期。

.PARAMETER Force
    强制刷新缓存。即使缓存存在且未过期，也会重新执行脚本块并更新缓存。

.PARAMETER NoCache
    跳过缓存机制，直接执行脚本块而不读取或写入缓存文件。适用于调试或一次性执行场景。

.PARAMETER CacheType
    缓存文件的格式类型。可选值：
    - XML: 使用Export-CliXml/Import-CliXml，适用于复杂PowerShell对象，保持完整数据类型（默认）
    - Text: 使用Set-Content/Get-Content，适用于字符串内容，纯文本存储，性能更好但仅支持字符串

.EXAMPLE
    Invoke-WithCache -Key "system-info" -ScriptBlock { Get-ComputerInfo }
    缓存系统信息查询结果，默认使用XML格式缓存1小时

.EXAMPLE
    Invoke-WithCache -Key "network-test" -ScriptBlock { Test-NetConnection google.com } -MaxAge ([TimeSpan]::FromMinutes(30))
    缓存网络连接测试结果，缓存30分钟

.EXAMPLE
    Invoke-WithCache -Key "data-query" -ScriptBlock { Get-Process } -Force
    强制刷新进程列表缓存

.EXAMPLE
    Invoke-WithCache -Key "temp-data" -ScriptBlock { Get-Service } -NoCache
    跳过缓存机制，直接执行并返回结果

.EXAMPLE
    Invoke-WithCache -Key "log-content" -CacheType Text -ScriptBlock { Get-Content "app.log" | Out-String }
    使用Text格式缓存日志文件内容，适用于纯文本数据

.EXAMPLE
    Invoke-WithCache -Key "api-response" -CacheType Text -ScriptBlock { Invoke-RestMethod "https://api.example.com/data" | ConvertTo-Json }
    使用Text格式缓存API响应的JSON字符串

.OUTPUTS
    System.Object
    返回脚本块的执行结果，可能来自缓存或新执行

.NOTES
    作者: mudssky
    版本: 1.4.0
    创建日期: 2025-01-07
    更新日期: 2025-01-07
    
    性能优化 v1.4.0:
    - 重用MD5哈希提供程序，避免重复创建和销毁
    - 优化文件操作，减少重复的文件系统调用
    - 添加缓存统计信息跟踪（命中率、读写次数等）
    - 改进错误处理和恢复机制
    - 添加自动缓存清理功能
    - 添加缓存统计和监控功能
    
    缓存文件位置: $env:LOCALAPPDATA\PowerShellCache
    缓存文件格式: 
    - XML: MD5哈希值.cache.xml (使用Export-CliXml/Import-CliXml)
    - Text: MD5哈希值.cache.txt (使用Set-Content/Get-Content)
    文件命名规则: MD5哈希值.cache.[xml|txt]
#>
function Invoke-WithCache {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [TimeSpan]$MaxAge = [TimeSpan]::FromHours(1),

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$NoCache,

        [Parameter(Mandatory = $false)]
        [ValidateSet('XML', 'Text')]
        [string]$CacheType = 'XML'
    )

    # 1. 将 Key 转换为安全的文件名 (重用MD5提供程序以提高性能)
    $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($Key)
    $hashBytes = $script:MD5Provider.ComputeHash($keyBytes)
    $hashString = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
    
    # 2. 根据缓存类型确定文件扩展名
    $fileExtension = if ($CacheType -eq 'Text') { 'txt' } else { 'xml' }
    $cacheFile = Join-Path $script:CacheBaseDir "$($hashString).cache.$fileExtension"

    # 3. 如果启用NoCache参数，直接执行脚本块
    if ($NoCache) {
        Write-Verbose "NoCache模式：直接执行脚本块，跳过缓存机制 for key: '$Key'"
        if ($PSCmdlet.ShouldProcess("Executing script block with key '$Key' (NoCache mode)")) {
            return & $ScriptBlock
        }
        return
    }

    # 4. 检查缓存是否有效（优化：使用单次文件信息获取）
    $cacheHit = $false
    $fileInfo = $null
    if (-not $Force) {
        try {
            $fileInfo = Get-Item $cacheFile -ErrorAction SilentlyContinue
            if ($fileInfo) {
                $expiryTime = $fileInfo.LastWriteTime + $MaxAge
                if ((Get-Date) -lt $expiryTime) {
                    Write-Verbose "缓存命中 (Cache hit) for key: '$Key'"
                    $cacheHit = $true
                    $script:CacheStats.Hits++
                }
                else {
                    Write-Verbose "缓存已过期 (Cache expired) for key: '$Key'"
                    $script:CacheStats.Misses++
                }
            }
            else {
                $script:CacheStats.Misses++
            }
        }
        catch {
            Write-Verbose "检查缓存文件时出错: $($_.Exception.Message)"
            $script:CacheStats.Misses++
        }
    }
    else {
        $script:CacheStats.Misses++
    }

    # 5. 根据缓存状态执行操作
    if ($cacheHit) {
        # 缓存命中：从文件读取并返回结果
        Write-Verbose "从文件读取缓存: $cacheFile"
        try {
            if ($CacheType -eq 'Text') {
                $content = Get-Content -Path $cacheFile -Raw -Encoding UTF8
                # 确保返回字符串类型，移除可能的换行符
                if ($null -eq $content) {
                    return ""
                }
                return [string]$content.TrimEnd("\r\n")
            }
            else {
                return Import-CliXml -Path $cacheFile
            }
        }
        catch {
            Write-Warning "读取缓存文件失败: $($_.Exception.Message)，将重新执行脚本块"
            $cacheHit = $false
            $script:CacheStats.Hits--
            $script:CacheStats.Misses++
        }
    }
    
    if (-not $cacheHit) {
        # 缓存未命中或强制刷新：执行脚本块
        Write-Verbose "缓存未命中 (Cache miss). 执行脚本块 for key: '$Key'."
        
        if ($PSCmdlet.ShouldProcess("Executing script block with key '$Key'")) {
            try {
                $result = & $ScriptBlock
                
                # 将结果写入缓存文件
                Write-Verbose "正在将结果写入缓存文件: $cacheFile"
                
                # 确保缓存目录存在
                $cacheDir = Split-Path $cacheFile -Parent
                if (-not (Test-Path $cacheDir)) {
                    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
                }
                
                if ($CacheType -eq 'Text') {
                    # Text格式：将结果转换为字符串并写入文本文件
                    $textContent = if ($result -is [string]) { 
                        $result 
                    } else { 
                        ($result | Out-String).Trim() 
                    }
                    Set-Content -Path $cacheFile -Value $textContent -Encoding UTF8 -NoNewline
                    $script:CacheStats.Writes++
                    # Text缓存模式下返回字符串格式
                    return $textContent
                }
                else {
                    # XML格式：使用Export-CliXml保存复杂对象
                    $result | Export-CliXml -Path $cacheFile
                    $script:CacheStats.Writes++
                    # 返回原始结果
                    return $result
                }
            }
            catch {
                Write-Warning "执行脚本块或写入缓存失败: $($_.Exception.Message)"
                # 重新抛出异常以确保错误能够正确传播
                throw
            }
        }
    }
}

# 模块清理：在模块卸载时释放资源
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if ($script:MD5Provider) {
        $script:MD5Provider.Dispose()
    }
}

# 导出模块函数
Export-ModuleMember -Function Invoke-WithCache, Clear-ExpiredCache, Get-CacheStats
