
<#
.SYNOPSIS
    以树状结构显示目录和文件
.DESCRIPTION
    此函数以树状结构显示指定路径下的目录和文件，支持自定义显示深度、文件过滤、
    显示隐藏文件、排除特定文件或目录以及限制显示项目数量等功能。
    输出结果带有颜色区分，目录显示为蓝色，文件显示为白色。
.PARAMETER Path
    要显示的目录路径。默认为当前目录。
.PARAMETER MaxDepth
    最大显示深度。默认为3层。设置为0表示无限制。
.PARAMETER ShowFiles
    是否显示文件。默认为$true。设置为$false时只显示目录。
.PARAMETER ShowHidden
    是否显示隐藏文件和目录。默认为$false。
.PARAMETER Exclude
    要排除的文件或目录模式数组。支持通配符。
.PARAMETER MaxItems
    每个目录中最多显示的项目数量。默认为50。设置为0表示无限制。
.OUTPUTS
    无。直接在控制台输出树状结构。
.EXAMPLE
    Get-Tree
    显示当前目录的树状结构（最大深度3层）。
.EXAMPLE
    Get-Tree -Path "C:\Users" -MaxDepth 2
    显示C:\Users目录的树状结构，最大深度2层。
.EXAMPLE
    Get-Tree -Path "C:\Projects" -ShowFiles $false
    只显示C:\Projects目录下的文件夹，不显示文件。
.EXAMPLE
    Get-Tree -Path "C:\Temp" -ShowHidden $true
    显示C:\Temp目录的树状结构，包括隐藏文件和目录。
.EXAMPLE
    Get-Tree -Path "C:\Source" -Exclude @("*.log", "node_modules", ".git")
    显示C:\Source目录的树状结构，排除.log文件、node_modules和.git目录。
.EXAMPLE
    Get-Tree -Path "C:\Data" -MaxItems 10
    显示C:\Data目录的树状结构，每个目录最多显示10个项目。
.NOTES
    作者: mudssky
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 方便查看目录结构，支持多种自定义选项。
    跨平台兼容：支持Windows、macOS和Linux系统。
#>
function Get-Tree {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [string]$Path = ".",
        
        [Parameter()]
        [int]$MaxDepth = 3,
        
        [Parameter()]
        [bool]$ShowFiles = $true,
        
        [Parameter()]
        [bool]$ShowHidden = $false,
        
        [Parameter()]
        [string[]]$Exclude = @(),
        
        [Parameter()]
        [int]$MaxItems = 50
    )
    
    # 验证路径是否存在
    if (-not (Test-Path $Path)) {
        Write-Error "路径 '$Path' 不存在"
        return
    }
    
    # 获取绝对路径
    $absolutePath = Resolve-Path $Path
    Write-Host $absolutePath -ForegroundColor Cyan
    
    # 开始递归显示
    Show-TreeItem -Path $absolutePath -Prefix "" -IsLast $true -CurrentDepth 0 -MaxDepth $MaxDepth -ShowFiles $ShowFiles -ShowHidden $ShowHidden -Exclude $Exclude -MaxItems $MaxItems
}

<#
.SYNOPSIS
    递归显示树状结构的辅助函数
.DESCRIPTION
    这是Get-Tree函数的内部辅助函数，用于递归显示目录和文件的树状结构。
.PARAMETER Path
    当前处理的路径
.PARAMETER Prefix
    当前行的前缀字符串
.PARAMETER IsLast
    是否为同级最后一个项目
.PARAMETER CurrentDepth
    当前递归深度
.PARAMETER MaxDepth
    最大显示深度
.PARAMETER ShowFiles
    是否显示文件
.PARAMETER ShowHidden
    是否显示隐藏文件
.PARAMETER Exclude
    排除的文件模式
.PARAMETER MaxItems
    每个目录最大显示项目数
#>
function Show-TreeItem {
    param (
        [string]$Path,
        [string]$Prefix,
        [bool]$IsLast,
        [int]$CurrentDepth,
        [int]$MaxDepth,
        [bool]$ShowFiles,
        [bool]$ShowHidden,
        [string[]]$Exclude,
        [int]$MaxItems
    )
    
    # 检查深度限制
    if ($MaxDepth -gt 0 -and $CurrentDepth -ge $MaxDepth) {
        return
    }
    
    try {
        # 获取子项目
        $items = Get-ChildItem -Path $Path -Force:$ShowHidden -ErrorAction SilentlyContinue
        
        # 过滤排除项
        if ($Exclude.Count -gt 0) {
            $filteredItems = @()
            foreach ($item in $items) {
                $shouldExclude = $false
                foreach ($pattern in $Exclude) {
                    if ($item.Name -like $pattern -or $item.FullName -like $pattern) {
                        $shouldExclude = $true
                        break
                    }
                }
                if (-not $shouldExclude) {
                    $filteredItems += $item
                }
            }
            $items = $filteredItems
        }
        
        # 根据ShowFiles参数过滤
        if (-not $ShowFiles) {
            $items = $items | Where-Object { $_.PSIsContainer }
        }
        
        # 排序：目录在前，文件在后，然后按名称排序
        $items = $items | Sort-Object @{Expression = { -not $_.PSIsContainer } }, Name
        
        # 限制显示数量
        if ($MaxItems -gt 0 -and $items.Count -gt $MaxItems) {
            $items = $items[0..($MaxItems - 1)]
            $hasMore = $true
        }
        else {
            $hasMore = $false
        }
        
        # 显示每个项目
        for ($i = 0; $i -lt $items.Count; $i++) {
            $item = $items[$i]
            $isLastItem = ($i -eq ($items.Count - 1)) -and (-not $hasMore)
            
            # 构建显示前缀
            if ($isLastItem) {
                $currentPrefix = $Prefix + "└── "
                $nextPrefix = $Prefix + "    "
            }
            else {
                $currentPrefix = $Prefix + "├── "
                $nextPrefix = $Prefix + "│   "
            }
            
            # 显示项目
            $displayName = $item.Name
            if ($item.PSIsContainer) {
                $displayName += "/"
                Write-Host ($currentPrefix + $displayName) -ForegroundColor (Get-ItemColor $item)
                
                # 递归显示子目录
                Show-TreeItem -Path $item.FullName -Prefix $nextPrefix -IsLast $isLastItem -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -ShowFiles $ShowFiles -ShowHidden $ShowHidden -Exclude $Exclude -MaxItems $MaxItems
            }
            else {
                Write-Host ($currentPrefix + $displayName) -ForegroundColor (Get-ItemColor $item)
            }
        }
        
        # 如果有更多项目被截断，显示提示
        if ($hasMore) {
            $moreCount = (Get-ChildItem -Path $Path -Force:$ShowHidden -ErrorAction SilentlyContinue).Count - $MaxItems
            $morePrefix = $Prefix + "└── "
            Write-Host ($morePrefix + "... ($moreCount 个项目被隐藏)") -ForegroundColor DarkGray
        }
        
    }
    catch {
        # 处理访问权限等错误
        $errorPrefix = $Prefix + "└── "
        Write-Host ($errorPrefix + "[访问被拒绝]") -ForegroundColor Red
    }
}

<#
.SYNOPSIS
    获取文件或目录的显示颜色
.DESCRIPTION
    根据文件类型和属性返回相应的控制台颜色。
.PARAMETER Item
    文件或目录对象
.OUTPUTS
    System.ConsoleColor
    返回对应的控制台颜色
#>
function Get-ItemColor {
    param (
        [System.IO.FileSystemInfo]$Item
    )
    
    if ($Item.PSIsContainer) {
        # 目录颜色
        if ($Item.Attributes -band [System.IO.FileAttributes]::Hidden) {
            return [ConsoleColor]::DarkBlue
        }
        else {
            return [ConsoleColor]::Blue
        }
    }
    else {
        # 文件颜色
        if ($Item.Attributes -band [System.IO.FileAttributes]::Hidden) {
            return [ConsoleColor]::DarkGray
        }
        else {
            # 根据文件扩展名设置颜色
            switch ($Item.Extension.ToLower()) {
                { $_ -in @('.exe', '.bat', '.cmd', '.ps1', '.sh') } { return [ConsoleColor]::Green }
                { $_ -in @('.txt', '.md', '.log') } { return [ConsoleColor]::White }
                { $_ -in @('.jpg', '.jpeg', '.png', '.gif', '.bmp') } { return [ConsoleColor]::Magenta }
                { $_ -in @('.mp3', '.wav', '.mp4', '.avi', '.mkv') } { return [ConsoleColor]::Yellow }
                { $_ -in @('.zip', '.rar', '.7z', '.tar', '.gz') } { return [ConsoleColor]::Cyan }
                default { return [ConsoleColor]::White }
            }
        }
    }
}


Export-ModuleMember -Function *