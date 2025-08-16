
<#
.SYNOPSIS
    以树状结构显示目录和文件
.DESCRIPTION
    此函数以树状结构显示指定路径下的目录和文件，支持自定义显示深度、文件过滤、
    显示隐藏文件、排除特定文件或目录以及限制显示项目数量等功能。
    支持.gitignore文件过滤（默认启用）。
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
.PARAMETER UseGitignore
    是否使用.gitignore文件过滤。默认为$true。
.PARAMETER AsObject
    是否返回目录树对象而不是直接输出到控制台。默认为$false。
.OUTPUTS
    当AsObject为$false时：无。直接在控制台输出树状结构。
    当AsObject为$true时：返回包含目录树结构的PSCustomObject。
.EXAMPLE
    Get-Tree
    显示当前目录的树状结构（最大深度3层），使用.gitignore过滤。
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
.EXAMPLE
    Get-Tree -UseGitignore $false
    显示当前目录的树状结构，不使用.gitignore过滤。
.EXAMPLE
    $tree = Get-Tree -AsObject $true
    获取目录树对象，可用于进一步处理。
.NOTES
    作者: mudssky
    版本: 2.0.0
    创建日期: 2025-01-07
    更新日期: 2025-01-07
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
        [int]$MaxItems = 50,
        
        [Parameter()]
        [bool]$UseGitignore = $true,
        
        [Parameter()]
        [bool]$AsObject = $false
    )
    
    # 验证路径是否存在
    if (-not (Test-Path $Path)) {
        Write-Error "路径 '$Path' 不存在"
        return
    }
    
    # 获取绝对路径
    $absolutePath = Resolve-Path $Path
    
    # 加载gitignore规则
    $gitignoreRules = @()
    if ($UseGitignore) {
        $gitignoreRules = Get-GitignoreRules -Path $absolutePath
    }
    
    if ($AsObject) {
        # 返回目录树对象
        $treeObject = Build-TreeObject -Path $absolutePath -CurrentDepth 0 -MaxDepth $MaxDepth -ShowFiles $ShowFiles -ShowHidden $ShowHidden -Exclude $Exclude -MaxItems $MaxItems -GitignoreRules $gitignoreRules
        return $treeObject
    }
    else {
        # 直接输出到控制台
        Write-Host $absolutePath -ForegroundColor Cyan
        Show-TreeItem -Path $absolutePath -Prefix "" -IsLast $true -CurrentDepth 0 -MaxDepth $MaxDepth -ShowFiles $ShowFiles -ShowHidden $ShowHidden -Exclude $Exclude -MaxItems $MaxItems -GitignoreRules $gitignoreRules
    }
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
        [int]$MaxItems,
        [string[]]$GitignoreRules = @()
    )
    
    # 检查深度限制
    if ($MaxDepth -gt 0 -and $CurrentDepth -ge $MaxDepth) {
        return
    }
    
    try {
        # 获取子项目
        $items = Get-ChildItem -Path $Path -Force:$ShowHidden -ErrorAction SilentlyContinue
        
        # 过滤排除项和gitignore项
        $filteredItems = @()
        foreach ($item in $items) {
            $shouldExclude = $false
            
            # 检查Exclude模式
            foreach ($pattern in $Exclude) {
                if ($item.Name -like $pattern -or $item.FullName -like $pattern) {
                    $shouldExclude = $true
                    break
                }
            }
            
            # 检查gitignore规则
            if (-not $shouldExclude -and $GitignoreRules.Count -gt 0) {
                $shouldExclude = Test-GitignoreMatch -Item $item -GitignoreRules $GitignoreRules -BasePath $Path
            }
            
            if (-not $shouldExclude) {
                $filteredItems += $item
            }
        }
        $items = $filteredItems
        
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
                Show-TreeItem -Path $item.FullName -Prefix $nextPrefix -IsLast $isLastItem -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -ShowFiles $ShowFiles -ShowHidden $ShowHidden -Exclude $Exclude -MaxItems $MaxItems -GitignoreRules $GitignoreRules
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


<#
.SYNOPSIS
    获取.gitignore文件的规则
.DESCRIPTION
    从指定路径开始向上查找.gitignore文件，并解析其中的规则。
.PARAMETER Path
    起始查找路径
.OUTPUTS
    System.String[]
    返回gitignore规则数组
#>
function Get-GitignoreRules {
    param (
        [string]$Path
    )
    
    # 初始化为空数组
    $rules = @()
    $currentPath = $Path
    
    # 向上查找.gitignore文件
    while ($currentPath -and (Test-Path $currentPath)) {
        $gitignorePath = Join-Path $currentPath ".gitignore"
        if (Test-Path $gitignorePath) {
            try {
                $content = Get-Content $gitignorePath -ErrorAction SilentlyContinue
                if ($content) {
                    foreach ($line in $content) {
                        $line = $line.Trim()
                        # 跳过空行和注释
                        if ($line -and -not $line.StartsWith('#')) {
                            $rules += $line
                        }
                    }
                }
            }
            catch {
                Write-Warning "无法读取.gitignore文件: $gitignorePath"
            }
        }
        
        # 移动到父目录
        $parentPath = Split-Path $currentPath -Parent
        if ($parentPath -eq $currentPath) {
            break
        }
        $currentPath = $parentPath
    }
    
    # 确保返回数组
    return , $rules
}

<#
.SYNOPSIS
    测试文件或目录是否匹配gitignore规则
.DESCRIPTION
    根据gitignore规则测试指定的文件或目录是否应该被忽略。
.PARAMETER Item
    要测试的文件或目录对象
.PARAMETER GitignoreRules
    gitignore规则数组
.PARAMETER BasePath
    基础路径，用于计算相对路径
.OUTPUTS
    System.Boolean
    如果应该被忽略返回$true，否则返回$false
#>
function Test-GitignoreMatch {
    param (
        [System.IO.FileSystemInfo]$Item,
        [string[]]$GitignoreRules,
        [string]$BasePath
    )
    
    if ($GitignoreRules.Count -eq 0) {
        return $false
    }
    
    # 计算相对路径
    $relativePath = $Item.FullName.Substring($BasePath.Length).TrimStart([char[]]@('\', '/'))
    $relativePath = $relativePath.Replace('\', '/')
    
    foreach ($rule in $GitignoreRules) {
        $pattern = $rule.Trim().Replace('\\', '/')
        
        # 跳过空规则
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            continue
        }
        
        # 处理否定规则（以!开头）
        if ($pattern.StartsWith('!')) {
            continue  # 简化处理，暂不支持否定规则
        }
        
        # 使用switch语句处理不同的匹配模式
        switch -Regex ($pattern) {
            # 处理以/开头的绝对路径模式
            '^/' {
                $cleanPattern = $pattern.TrimStart('/')
                if ($cleanPattern.EndsWith('/')) {
                    # 目录规则
                    $cleanPattern = $cleanPattern.TrimEnd('/')
                    if ($Item.PSIsContainer -and ($relativePath -eq $cleanPattern -or $relativePath -like "$cleanPattern/*")) {
                        return $true
                    }
                }
                else {
                    # 文件或目录规则
                    if ($relativePath -eq $cleanPattern -or $relativePath -like "$cleanPattern/*" -or $Item.Name -eq $cleanPattern) {
                        return $true
                    }
                }
                break
            }
            # 处理以/结尾的目录模式
            '/$' {
                $cleanPattern = $pattern.TrimEnd('/')
                if ($Item.PSIsContainer) {
                    # 检查目录名匹配
                    if ($Item.Name -eq $cleanPattern -or $relativePath -eq $cleanPattern -or $relativePath -like "*/$cleanPattern" -or $relativePath -like "$cleanPattern/*") {
                        return $true
                    }
                }
                break
            }
            # 处理包含通配符的模式
            '[*?\[\]]' {
                if ($relativePath -like $pattern -or $Item.Name -like $pattern) {
                    return $true
                }
                # 检查路径的任何部分是否匹配
                $pathParts = $relativePath.Split('/')
                foreach ($part in $pathParts) {
                    if ($part -like $pattern) {
                        return $true
                    }
                }
                break
            }
            # 处理普通模式（文件名或目录名）
            default {
                # 直接匹配文件名或目录名
                if ($Item.Name -eq $pattern) {
                    return $true
                }
                # 匹配相对路径
                if ($relativePath -eq $pattern) {
                    return $true
                }
                # 检查是否为路径中的任何部分
                $pathParts = $relativePath.Split('/')
                if ($pathParts -contains $pattern) {
                    return $true
                }
                # 检查是否匹配路径的开始部分
                if ($relativePath -like "$pattern/*") {
                    return $true
                }
                break
            }
        }
    }
    
    return $false
}

<#
.SYNOPSIS
    构建目录树对象
.DESCRIPTION
    递归构建目录树的对象表示，用于返回结构化数据。
.PARAMETER Path
    当前处理的路径
.PARAMETER CurrentDepth
    当前递归深度
.PARAMETER MaxDepth
    最大显示深度
.PARAMETER ShowFiles
    是否包含文件
.PARAMETER ShowHidden
    是否包含隐藏文件
.PARAMETER Exclude
    排除的文件模式
.PARAMETER MaxItems
    每个目录最大项目数
.PARAMETER GitignoreRules
    gitignore规则
.OUTPUTS
    PSCustomObject
    返回目录树对象
#>
function Build-TreeObject {
    param (
        [string]$Path,
        [int]$CurrentDepth,
        [int]$MaxDepth,
        [bool]$ShowFiles,
        [bool]$ShowHidden,
        [string[]]$Exclude,
        [int]$MaxItems,
        [string[]]$GitignoreRules = @()
    )
    
    $item = Get-Item $Path
    $treeNode = [PSCustomObject]@{
        Name           = $item.Name
        FullPath       = $item.FullName
        IsDirectory    = $item.PSIsContainer
        Size           = if ($item.PSIsContainer) { $null } else { $item.Length }
        LastWriteTime  = $item.LastWriteTime
        Children       = @()
        TruncatedCount = 0
    }
    
    # 检查深度限制
    if ($MaxDepth -gt 0 -and $CurrentDepth -ge $MaxDepth) {
        return $treeNode
    }
    
    if ($item.PSIsContainer) {
        try {
            # 获取子项目
            $items = Get-ChildItem -Path $Path -Force:$ShowHidden -ErrorAction SilentlyContinue
            
            # 过滤排除项和gitignore项
            $filteredItems = @()
            foreach ($childItem in $items) {
                $shouldExclude = $false
                
                # 检查Exclude模式
                foreach ($pattern in $Exclude) {
                    if ($childItem.Name -like $pattern -or $childItem.FullName -like $pattern) {
                        $shouldExclude = $true
                        break
                    }
                }
                
                # 检查gitignore规则
                if (-not $shouldExclude -and $GitignoreRules.Count -gt 0) {
                    $shouldExclude = Test-GitignoreMatch -Item $childItem -GitignoreRules $GitignoreRules -BasePath $Path
                }
                
                if (-not $shouldExclude) {
                    $filteredItems += $childItem
                }
            }
            $items = $filteredItems
            
            # 根据ShowFiles参数过滤
            if (-not $ShowFiles) {
                $items = $items | Where-Object { $_.PSIsContainer }
            }
            
            # 排序：目录在前，文件在后，然后按名称排序
            $items = $items | Sort-Object @{Expression = { -not $_.PSIsContainer } }, Name
            
            # 限制显示数量
            if ($MaxItems -gt 0 -and $items.Count -gt $MaxItems) {
                $treeNode.TruncatedCount = $items.Count - $MaxItems
                $items = $items[0..($MaxItems - 1)]
            }
            
            # 递归构建子节点
            foreach ($childItem in $items) {
                $childNode = Build-TreeObject -Path $childItem.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -ShowFiles $ShowFiles -ShowHidden $ShowHidden -Exclude $Exclude -MaxItems $MaxItems -GitignoreRules $GitignoreRules
                $treeNode.Children += $childNode
            }
        }
        catch {
            # 处理访问权限等错误
            $treeNode.Children = @([PSCustomObject]@{
                    Name           = "[访问被拒绝]"
                    FullPath       = $null
                    IsDirectory    = $false
                    Size           = $null
                    LastWriteTime  = $null
                    Children       = @()
                    TruncatedCount = 0
                })
        }
    }
    
    return $treeNode
}

<#
.SYNOPSIS
    获取目录树对象
.DESCRIPTION
    返回指定路径的目录树结构对象，不直接输出到控制台。
.PARAMETER Path
    要分析的目录路径。默认为当前目录。
.PARAMETER MaxDepth
    最大显示深度。默认为3层。设置为0表示无限制。
.PARAMETER ShowFiles
    是否包含文件。默认为$true。设置为$false时只包含目录。
.PARAMETER ShowHidden
    是否包含隐藏文件和目录。默认为$false。
.PARAMETER Exclude
    要排除的文件或目录模式数组。支持通配符。
.PARAMETER MaxItems
    每个目录中最多包含的项目数量。默认为50。设置为0表示无限制。
.PARAMETER UseGitignore
    是否使用.gitignore文件过滤。默认为$true。
.OUTPUTS
    PSCustomObject
    返回包含目录树结构的对象
.EXAMPLE
    $tree = Get-TreeObject
    获取当前目录的树状结构对象。
.EXAMPLE
    $tree = Get-TreeObject -Path "C:\Projects" -MaxDepth 2
    获取C:\Projects目录的树状结构对象，最大深度2层。
.NOTES
    作者: mudssky
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 获取目录结构的对象表示，便于程序化处理。
#>
function Get-TreeObject {
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
        [int]$MaxItems = 50,
        
        [Parameter()]
        [bool]$UseGitignore = $true
    )
    
    return Get-Tree -Path $Path -MaxDepth $MaxDepth -ShowFiles $ShowFiles -ShowHidden $ShowHidden -Exclude $Exclude -MaxItems $MaxItems -UseGitignore $UseGitignore -AsObject $true
}

<#
.SYNOPSIS
    将目录树对象转换为JSON格式
.DESCRIPTION
    将Get-TreeObject或Get-Tree -AsObject返回的目录树对象转换为JSON字符串。
.PARAMETER TreeObject
    目录树对象
.PARAMETER Depth
    JSON序列化深度。默认为10。
.PARAMETER Compress
    是否压缩JSON输出。默认为$false。
.OUTPUTS
    System.String
    返回JSON格式的字符串
.EXAMPLE
    $tree = Get-TreeObject
    $json = ConvertTo-TreeJson -TreeObject $tree
    获取目录树并转换为JSON格式。
.EXAMPLE
    Get-TreeObject | ConvertTo-TreeJson -Compress $true
    获取目录树并转换为压缩的JSON格式。
.NOTES
    作者: mudssky
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 将目录树对象序列化为JSON格式，便于存储和传输。
#>
function ConvertTo-TreeJson {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$TreeObject,
        
        [Parameter()]
        [int]$Depth = 10,
        
        [Parameter()]
        [bool]$Compress = $false
    )
    
    process {
        if ($Compress) {
            return ($TreeObject | ConvertTo-Json -Depth $Depth -Compress)
        }
        else {
            return ($TreeObject | ConvertTo-Json -Depth $Depth)
        }
    }
}

Export-ModuleMember -Function Get-Tree, Show-TreeItem, Get-ItemColor, Get-GitignoreRules, Test-GitignoreMatch, Build-TreeObject, Get-TreeObject, ConvertTo-TreeJson