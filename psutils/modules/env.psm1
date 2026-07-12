<#
.SYNOPSIS
    将 dotenv 文件解析为键值哈希表。
.DESCRIPTION
    读取指定的 .env 文件，忽略空行和注释行，并解析 KEY=VALUE 格式的配置项。
.PARAMETER Path
    要读取的 .env 文件绝对路径或相对路径。
.OUTPUTS
    System.Collections.Hashtable
    返回从 dotenv 文件解析出的键值对。
.EXAMPLE
    Get-Dotenv -Path ".\project\.env"
    读取项目目录中的 .env 文件。
#>
function Get-Dotenv {
    [CmdletBinding()]
    param (
        # dotenv文件路径
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $content = Get-Content $Path
    $pairs = @{}
    foreach ($line in $content) {
        if ($line -match '^\s*([^=]+)=(.*)') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            $pairs[$key] = $value
        }
    }
    return $pairs
}




<#
.SYNOPSIS
    将 dotenv 配置加载到环境变量。
.DESCRIPTION
    读取指定的 .env 文件并写入目标环境变量范围。未指定路径时，依次查找当前目录的 .env.local 和 .env。
.PARAMETER Path
    要加载的 .env 文件路径；省略时使用默认文件查找顺序。
.PARAMETER EnvTarget
    环境变量写入范围，支持 Machine、User 和 Process，默认为 User。
.OUTPUTS
    None
    此函数直接更新环境变量，不返回对象。
.EXAMPLE
    Install-Dotenv -Path ".\project\.env" -EnvTarget User
    将指定文件加载到当前用户环境变量。
#>
function Install-Dotenv {
    [CmdletBinding()]
    param (
        # dotenv文件路径
        # [Parameter(Mandatory = $true)]
        [string]$Path,	

        # Machine: 表示系统级环境变量。对所有用户和进程可见，需要管理员权限。
        # User: 表示用户级环境变量。对当前用户和所有该用户的进程可见。
        # Process: 表示进程级环境变量。仅对当前PowerShell进程可见。
        # 环境变量的类型
        [ValidateSet('Machine', 'User', 'Process')]
        [string]$EnvTarget = 'User'
    )

    $defaultEnvFileList = @('.env.local', '.env')
    Write-Debug "开始查找默认环境变量文件，当前路径: $Path"
    if (-not( Test-Path -LiteralPath $Path)) {
        $foundDefaultFile = $false
        # 判断默认环境变量文件
        Write-Debug "开始检查默认环境变量文件列表: $($defaultEnvFileList -join ', ')"
        foreach ($defaultEnvFilePath in $defaultEnvFileList) {
            Write-Debug "正在检查文件: $defaultEnvFilePath"
            if (Test-Path -LiteralPath $defaultEnvFilePath) {
                $Path = $defaultEnvFilePath
                $foundDefaultFile = $true
                Write-Debug "找到默认环境变量文件: $defaultEnvFilePath"
                break
            }
        }
		
        if (-not $foundDefaultFile) {
            Write-Error "env文件不存在: $Path"
            Write-Debug "未找到任何默认环境变量文件"
            return
        } 

	
    }
    $envTargetMap = @{
        'Machine' = [System.EnvironmentVariableTarget]::Machine
        'User'    = [System.EnvironmentVariableTarget]::User
        'Process' = [System.EnvironmentVariableTarget]::Process
    }

    $envPairs = Get-Dotenv -Path $Path
	
    foreach ($pair in $envPairs.GetEnumerator()) {
        $target = $envTargetMap[$EnvTarget]
        Write-Debug "正在设置环境变量: $($pair.key) = $($pair.value) (目标: $EnvTarget)"
        [System.Environment]::SetEnvironmentVariable($pair.key, $pair.value, $target)
        Write-Verbose "set env $($pair.key) = $($pair.value) to $EnvTarget"
        Write-Debug "成功设置环境变量: $($pair.key)"
    }	
}



<#
.SYNOPSIS
    重新加载当前会话的 PATH。
.DESCRIPTION
    从 Machine、User 或 Process 范围读取 PATH；All 模式会按系统级优先的顺序合并并去重。
.PARAMETER EnvTarget
    要读取的 PATH 范围，支持 Machine、User、Process 和 All，默认为 All。
.OUTPUTS
    None
    此函数直接更新当前进程 PATH，不返回对象。
.EXAMPLE
    Import-EnvPath -EnvTarget User
    仅从用户级环境变量重新加载 PATH。
#>
function Import-EnvPath {
    [CmdletBinding()]
    param (
        [ValidateSet('Machine', 'User', 'All', "Process")]
        [string]$EnvTarget = 'All'
    )	

    Write-Debug "开始重新加载PATH，模式: $EnvTarget"
    Write-Debug "当前PATH长度: $($env:Path.Length) 字符"
	
    switch ($EnvTarget) {
        'Machine' {
            $newPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
            Write-Debug "系统级PATH长度: $($newPath.Length) 字符"
            Write-Debug "系统级PATH内容: $newPath"
            $env:Path = $newPath
            Write-Verbose "已重新加载系统级PATH"
        }
        'User' {
            $newPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
            Write-Debug "用户级PATH长度: $($newPath.Length) 字符"
            Write-Debug "用户级PATH内容: $newPath"
            $env:Path = $newPath
            Write-Verbose "已重新加载用户级PATH"
        }
        'Process' {
            # [System.EnvironmentVariableTarget]::Process 获取的是当前这个 PowerShell 进程已经拥有的 Path 变量。所以，$newPath 的值和执行这行代码之前的 $env:Path 的值是完全一样的。
            # 这是一个无用操作
            $newPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Process)
            Write-Debug "进程级PATH长度: $($newPath.Length) 字符"
            Write-Debug "进程级PATH内容: $newPath"
            $env:Path = $newPath
            Write-Verbose "已重新加载进程级PATH"
        }
        'All' {
            # 获取系统级和用户级PATH
            $machinePath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
            $userPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
			
            Write-Debug "系统级PATH长度: $($machinePath.Length) 字符`n"
            Write-Debug "用户级PATH长度: $($userPath.Length) 字符"
            Write-Debug "系统级PATH: $machinePath"
            Write-Debug "用户级PATH: $userPath"
			
            # 合并PATH，系统级在前，用户级在后，并去除重复项
            $allPaths = @()
			
            # 添加系统级PATH
            if ($machinePath) {
                $machinePaths = $machinePath -split ';' | Where-Object { $_.Trim() -ne '' }
                Write-Debug "系统级PATH分割后数量: $($machinePaths.Count)"
                $allPaths += $machinePaths
            }
            # 添加用户级PATH
            if ($userPath) {
                $userPaths = $userPath -split ';' | Where-Object { $_.Trim() -ne '' }
                Write-Debug "用户级PATH分割后数量: $($userPaths.Count)"
                $allPaths += $userPaths
            }
			
            Write-Debug "合并前总PATH数量: $($allPaths.Count)"
			
            # 去除重复项，保持顺序（系统级优先）
            $uniquePaths = @()
            $seenPaths = @{}
            $duplicateCount = 0
			
            foreach ($path in $allPaths) {
                $normalizedPath = $path.Trim().TrimEnd('\').ToLower()
                if (-not $seenPaths.ContainsKey($normalizedPath) -and $normalizedPath -ne '') {
                    $uniquePaths += $path.Trim()
                    $seenPaths[$normalizedPath] = $true
                    Write-Debug "添加唯一路径: $($path.Trim())"
                }
                else {
                    $duplicateCount++
                    Write-Debug "跳过重复路径: $($path.Trim())"
                }
            }
			
            Write-Debug "去重后唯一PATH数量: $($uniquePaths.Count)"
            Write-Debug "跳过的重复PATH数量: $duplicateCount"
			
            $finalPath = $uniquePaths -join ';'
            Write-Debug "最终PATH长度: $($finalPath.Length) 字符"
            $env:Path = $finalPath
            Write-Verbose "已重新加载合并的系统级和用户级PATH，共 $($uniquePaths.Count) 个唯一路径，去除了 $duplicateCount 个重复项"
        }
    }
	
    Write-Debug "PATH重新加载完成，最终长度: $($env:Path.Length) 字符"
    Write-Host "PATH已重新加载" -ForegroundColor Green
}


<#
.SYNOPSIS
    设置指定范围的 PATH 环境变量。
.DESCRIPTION
    Windows 的 User 和 Machine 范围使用可扩展字符串写入注册表；Linux 和 macOS 仅支持 Process 范围。
.PARAMETER PathStr
    要写入的完整 PATH 字符串。
.PARAMETER EnvTarget
    PATH 的目标范围，支持 Machine、User 和 Process，默认为 User。
.OUTPUTS
    None
    此函数直接更新环境变量或注册表，不返回对象。
#>
function Set-EnvPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $PathStr,

        [ValidateSet('Machine', 'User', 'Process')]
        [string]$EnvTarget = 'User'
    )

    begin {
        # 获取修改前的长度用于对比
        try {
            $oldPath = [Environment]::GetEnvironmentVariable("Path", $EnvTarget)
            $oldLen = if ($oldPath) { $oldPath.Length } else { 0 }
            Write-Verbose "当前 $EnvTarget Path 长度: $oldLen"
        }
        catch {
            $oldLen = 0
        }
    }

    process {
        # 针对不同目标采用不同策略
        switch ($EnvTarget) {
            'Process' {
                # Process 级别只影响当前会话，直接设置内存即可
                $env:Path = $PathStr
                Write-Verbose "已更新当前进程的 PATH 变量"
            }

            'User' {
                if ($IsLinux -or $IsMacOS) {
                    Write-Warning "Linux/macOS 不支持通过此命令持久化设置 User 环境变量。请手动修改 ~/.bashrc 或 ~/.profile。"
                }
                else {
                    # User 级别：写入 HKCU 注册表，强制类型为 ExpandString
                    Write-Verbose "正在更新用户注册表 (HKCU)..."
                    Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value $PathStr -Type ExpandString
                }
            }

            'Machine' {
                if ($IsLinux -or $IsMacOS) {
                    Write-Warning "Linux/macOS 不支持通过此命令持久化设置 Machine 环境变量。请手动修改 /etc/environment 或 /etc/profile.d/。"
                }
                else {
                    # Machine 级别：写入 HKLM 注册表，强制类型为 ExpandString (需管理员权限)
                    # 检查权限
                    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                    if (-not $isAdmin) {
                        Write-Error "错误：修改系统 (Machine) 环境变量需要管理员权限！"
                        return
                    }
                    
                    Write-Verbose "正在更新系统注册表 (HKLM)..."
                    $sysKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
                    Set-ItemProperty -Path $sysKey -Name 'Path' -Value $PathStr -Type ExpandString
                }
            }
        }
    }

    end {
        $newLen = $PathStr.Length
        Write-Host "✅ Path 设置成功 ($EnvTarget)" -ForegroundColor Green
        Write-Host "   📏 长度变化: $oldLen -> $newLen" -ForegroundColor Cyan
        
        # 如果长度缩短了，给个好评
        if ($newLen -lt $oldLen) {
            Write-Host "   📉 成功瘦身: 减少了 $($oldLen - $newLen) 个字符" -ForegroundColor Green
        }

        # 仅在 Windows 下尝试刷新 User/Machine 环境
        # Linux 下 User/Machine 未变动，Process 已变动
        if (-not ($IsLinux -or $IsMacOS)) {
            # 尝试刷新当前会话（如果定义了 Import-Envpath）
            if (Get-Command 'Import-Envpath' -ErrorAction SilentlyContinue) {
                Write-Verbose "正在调用 Import-Envpath 刷新环境..."
                Import-EnvPath -EnvTarget $EnvTarget
            }
            else {
                # 如果没有那个函数，手动刷新一下 Process 变量以便当前窗口立即生效（仅限 User 模式简单刷新）
                if ($EnvTarget -eq 'User') {
                    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
                }
                Write-Warning "环境变量已更新。请重启终端/VSCode 以确保所有应用读取到最新的 Path (特别是包含 %变量% 的部分)。"
            }
        }
    }
}

<#
.SYNOPSIS
    向 PATH 环境变量追加目录。
.DESCRIPTION
    将目录解析为绝对路径后追加到当前 PATH，并写入指定的环境变量范围。
.PARAMETER Path
    要追加到 PATH 的目录路径。
.PARAMETER EnvTarget
    PATH 的目标范围，支持 Machine、User 和 Process，默认为 User。
.OUTPUTS
    None
    此函数直接更新 PATH，不返回对象。
.EXAMPLE
    Add-EnvPath -Path ".\bin" -EnvTarget User
    将当前目录下的 bin 目录追加到用户 PATH。
#>
function Add-EnvPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $Path,
        [ValidateSet('Machine', 'User', 'Process')]
        [string]$EnvTarget = 'User'
    )
	
    begin {
		
    }
	
    process {
        $absPath = Resolve-Path $Path
        $newPath = $Env:Path + ";$absPath"

        Set-EnvPath -PathStr $newPath -EnvTarget $EnvTarget
    }
	
    end {
        # 导入环境变量
        Import-EnvPath -EnvTarget User
    }
}

<#
.SYNOPSIS
    读取指定范围的环境变量。
.DESCRIPTION
    从 Machine、User 或 Process 范围读取环境变量；默认读取用户级 Path。
.PARAMETER ParamName
    要读取的环境变量名称，默认为 Path。
.PARAMETER EnvTarget
    环境变量范围，支持 Machine、User 和 Process，默认为 User。
.OUTPUTS
    System.String
    返回环境变量值；变量不存在时返回空值并写入警告。
.EXAMPLE
    Get-EnvParam -ParamName 'Path' -EnvTarget User
    获取当前用户的 Path 环境变量。
#>
function Get-EnvParam {
    [CmdletBinding()]
    param (
        [string]
        $ParamName = 'Path',
        [ValidateSet('Machine', 'User', 'Process')]
        [string]$EnvTarget = 'User'
    )
	
    begin {
		
        Write-Debug "current env path: $env:Path"
    }
    process {
        try {
            $value = [Environment]::GetEnvironmentVariable($ParamName, $EnvTarget)
            if ($value -eq $null) {
                Write-Warning "环境变量 $ParamName 未找到或未设置。"
            }
            return $value
        }
        catch {
            Write-Error "获取环境变量 $ParamName 时出错: $_"
        }
    }
	
}

<#
.SYNOPSIS
    从 PATH 环境变量移除目录。
.DESCRIPTION
    将目标目录解析为绝对路径，从当前 PATH 中移除匹配项，并写入指定的环境变量范围。
.PARAMETER Path
    要从 PATH 中移除的目录路径。
.PARAMETER EnvTarget
    PATH 的目标范围，支持 Machine、User 和 Process，默认为 User。
.OUTPUTS
    None
    此函数直接更新 PATH，不返回对象。
.EXAMPLE
    Remove-FromEnvPath -Path ".\bin" -EnvTarget User
    从用户 PATH 中移除当前目录下的 bin 目录。
#>
function Remove-FromEnvPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $Path,
        [ValidateSet('Machine', 'User', 'Process')]
        [string]$EnvTarget = 'User'
    )
	
    begin {
		
    }
	
    process {
        $removePath = Resolve-Path $Path
        $pathList = $env:Path -split ';'
        Write-Host "remove path:$removePath"
        if ($pathList -contains $removePath) {
            $newPathList = $pathList | Where-Object { $_ -ne $removePath }
            $newPath = $newPathList -join ';'
            Set-EnvPath -PathStr $newPath -EnvTarget $EnvTarget
        }
        else {
            Write-Error "path not found in path env"
        }
    }
	
    end {
        # 导入环境变量
        Import-EnvPath -EnvTarget User
    }
}




<#
.SYNOPSIS
    将 Bash 的 PATH 同步到当前 PowerShell 会话。
.DESCRIPTION
    默认通过非登录 Bash 读取 .bashrc 中的 PATH，并追加当前 PowerShell 缺少的目录；也支持登录模式、缓存和预览。
.PARAMETER Login
    使用登录 Bash 获取 PATH。
.PARAMETER Prepend
    将缺失目录前置到当前 PATH；默认追加到末尾。
.PARAMETER IncludeNonexistent
    保留 Bash PATH 中当前不存在的目录。
.PARAMETER ReturnObject
    是否返回同步统计对象，默认为 true。
.PARAMETER CacheSeconds
    Bash PATH 缓存的有效秒数；设置为 0 可禁用缓存读取和写入。
.PARAMETER ThrowOnFailure
    Bash PATH 获取失败时抛出终止错误；默认仅写入警告或错误。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    ReturnObject 为 true 时返回同步来源、增删目录、耗时和最终 PATH；否则不返回对象。
.EXAMPLE
    Sync-PathFromBash -WhatIf -Verbose
    预览非登录模式下将要追加的目录。
#>
function Sync-PathFromBash {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [switch]$Login,
        [switch]$Prepend,
        [switch]$IncludeNonexistent,
        [bool]$ReturnObject = $true,
        [int]$CacheSeconds = 300,
        [switch]$ThrowOnFailure
    )

    try {
        $start = [DateTime]::UtcNow
        Write-Information "正在从 Bash 登录 Shell 中获取 PATH..."
        $bashPathOutput = ''
        $source = ''
        $mockPath = $env:PWSH_TEST_BASH_PATH
        if (-not [string]::IsNullOrWhiteSpace($mockPath)) {
            $bashPathOutput = [string]$mockPath
            $source = 'mock-env'
        }
        $cacheDir = Join-Path $HOME ".cache/powershellScripts"
        $cacheFile = Join-Path $cacheDir "bash_path.json"
        $useCache = $CacheSeconds -gt 0 -and (Test-Path -LiteralPath $cacheFile)
        if ($useCache) {
            try {
                $cache = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
                $ageSec = ([DateTime]::UtcNow - [DateTime]$cache.timestamp).TotalSeconds
                $isLoginCache = ($cache.source -like 'bash-login*')
                $isNoLoginCache = ($cache.source -like 'bash-nologin*')
                if ($ageSec -le $CacheSeconds -and (($Login -and $isLoginCache) -or ((-not $Login) -and $isNoLoginCache))) {
                    $bashPathOutput = [string]$cache.path
                    $source = [string]$cache.source + '-cache'
                }
            }
            catch { }
        }
        if ([string]::IsNullOrWhiteSpace($bashPathOutput) -and $Login) {
            $bashPathOutput = bash -lc 'echo $PATH'
            $source = 'bash-login'
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($bashPathOutput)) {
                Write-Warning "无法从 Bash 登录 Shell 获取 PATH，尝试回退 /etc/profile。"
                $bashPathOutput = bash -c 'source /etc/profile >/dev/null 2>&1; echo $PATH'
                $source = 'bash-profile-fallback'
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($bashPathOutput)) {
                    $msg = "无法从 Bash 获取 PATH。Bash 可能未安装或存在配置错误。"
                    if ($ThrowOnFailure) { throw $msg } else { Write-Warning $msg; return }
                }
            }
        }
        elseif ([string]::IsNullOrWhiteSpace($bashPathOutput)) {
            $bashPathOutput = bash -ci 'echo $PATH'
            $source = 'bash-nologin-bashrc'
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($bashPathOutput)) {
                Write-Warning "非登录模式获取 PATH 失败，尝试显式加载 ~/.bashrc。"
                $bashPathOutput = bash '--noprofile' '--norc' '-c' 'source ~/.bashrc 2>/dev/null; echo $PATH'
                $source = 'bash-nologin-bashrc-fallback'
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($bashPathOutput)) {
                    $msg = "无法从非登录模式获取 PATH。请检查 Bash 安装或 .bashrc 配置。"
                    if ($ThrowOnFailure) { throw $msg } else { Write-Warning $msg; return }
                }
            }
        }

        $bashPathOutput = $bashPathOutput.Trim()
        if ($CacheSeconds -gt 0 -and -not [string]::IsNullOrWhiteSpace($bashPathOutput) -and -not ($source -like '*-cache')) {
            try {
                if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
                @{ path = $bashPathOutput; source = $source; timestamp = [DateTime]::UtcNow } | ConvertTo-Json | Set-Content -LiteralPath $cacheFile -Encoding UTF8
            }
            catch { }
        }
        $separator = [System.IO.Path]::PathSeparator

        $bashPathsRaw = $bashPathOutput.Split($separator, [System.StringSplitOptions]::RemoveEmptyEntries)
        $psPathsRaw = $env:PATH.Split($separator, [System.StringSplitOptions]::RemoveEmptyEntries)
        $bashSet = [System.Collections.Generic.HashSet[string]]::new()
        $psSetAll = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($x in $bashPathsRaw) { $t = $x.Trim(); if ($t.Length -gt 0) { [void]$bashSet.Add($t) } }
        foreach ($x in $psPathsRaw) { $t = $x.Trim(); if ($t.Length -gt 0) { [void]$psSetAll.Add($t) } }
        $bashPaths = $bashSet.GetEnumerator() | ForEach-Object { $_ }
        $psPaths = $psSetAll.GetEnumerator() | ForEach-Object { $_ }

        Write-Information "从 Bash 中找到的路径: $($bashPaths.Count) 个"
        Write-Information "当前 PowerShell 中的路径: $($psPaths.Count) 个"

        $psSet = $psSetAll
        $missingPaths = [System.Collections.Generic.List[string]]::new()
        foreach ($p in $bashPaths) { if (-not $psSet.Contains($p)) { $missingPaths.Add($p) } }

        if ($missingPaths.Count -gt 0) {
            Write-Information "发现 $($missingPaths.Count) 个需要从 Bash 同步的路径。"
            Write-Verbose ("缺失路径: " + ($missingPaths -join $separator))

            if ($IncludeNonexistent) {
                $pathsToApply = $missingPaths
                $skippedPaths = @()
            }
            else {
                $pathsToApply = [System.Collections.Generic.List[string]]::new()
                $skippedPaths = [System.Collections.Generic.List[string]]::new()
                foreach ($mp in $missingPaths) { if (Test-Path -LiteralPath $mp -PathType Container) { [void]$pathsToApply.Add($mp) } else { [void]$skippedPaths.Add($mp) } }
            }

            if ($pathsToApply.Count -gt 0) {
                foreach ($path in $pathsToApply) { Write-Verbose "将添加: $path" }

                $actionDesc = if ($Prepend) { "Prepend $($pathsToApply.Count) 路径到 PATH" } else { "Append $($pathsToApply.Count) 路径到 PATH" }
                if ($PSCmdlet.ShouldProcess("PATH", $actionDesc)) {
                    $newPath = ($pathsToApply -join $separator)
                    if ($Prepend) {
                        if ($env:PATH) { $env:PATH = "$newPath$separator$($env:PATH)" } else { $env:PATH = $newPath }
                    }
                    else {
                        if ($env:PATH) { $env:PATH = "$(($env:PATH))$separator$newPath" } else { $env:PATH = $newPath }
                    }
                    Write-Information "PowerShell PATH 已成功更新！"
                }
            }
            else {
                Write-Information "无可添加的有效目录。"
            }
        }
        else {
            Write-Information "PowerShell 的 PATH 与 Bash 完全同步，无需操作。"
            $skippedPaths = @()
            $pathsToApply = @()
        }

        $elapsedMs = ([DateTime]::UtcNow - $start).TotalMilliseconds
        if ($ReturnObject) {
            $obj = [PSCustomObject]@{
                SourcePathsCount   = $bashPaths.Count
                CurrentPathsCount  = $psPaths.Count
                AddedPaths         = $pathsToApply
                SkippedPaths       = $skippedPaths
                Source             = $source
                ElapsedMs          = [math]::Round($elapsedMs, 2)
                NewPath            = $env:PATH
                Prepend            = [bool]$Prepend
                IncludeNonexistent = [bool]$IncludeNonexistent
            }
            return $obj
        }
    }
    catch {
        Write-Error "同步 PATH 时发生错误: $_"
    }
}

function Test-DirectoryInPath {
    <#
    .SYNOPSIS
        判断目录是否已经位于 PATH 中。

    .DESCRIPTION
        将目标目录和 PATH 中的条目都规范化为完整路径后比较。Windows 平台默认忽略大小写，
        Linux/macOS 默认区分大小写；调用方也可以显式传入比较方式。

    .PARAMETER Directory
        待检查的目录路径。

    .PARAMETER PathValue
        可选 PATH 字符串；默认读取当前进程 PATH。

    .PARAMETER Comparison
        路径比较方式；未传入时根据平台自动选择。

    .OUTPUTS
        bool
        目录已在 PATH 中时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [AllowNull()]
        [string]$PathValue = $env:PATH,

        [AllowNull()]
        [object]$Comparison = $null
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $false
    }

    [System.StringComparison]$effectiveComparison = if ($null -ne $Comparison) {
        if ($Comparison -is [System.StringComparison]) {
            $Comparison
        }
        else {
            [System.StringComparison]::Parse([System.StringComparison], [string]$Comparison, $true)
        }
    }
    elseif ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }

    $target = [System.IO.Path]::GetFullPath($Directory).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    foreach ($entry in ($PathValue -split [regex]::Escape([System.IO.Path]::PathSeparator))) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }

        try {
            $entryPath = [System.IO.Path]::GetFullPath($entry.Trim()).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        }
        catch {
            continue
        }

        if ([string]::Equals($target, $entryPath, $effectiveComparison)) {
            return $true
        }
    }

    return $false
}

function Get-PathAddHint {
    <#
    .SYNOPSIS
        生成平台化 PATH 添加提示。

    .DESCRIPTION
        根据平台输出适合展示给用户的 PATH 添加命令或操作方法。该函数只生成文本，
        不修改环境变量。

    .PARAMETER Directory
        需要加入 PATH 的目录。

    .PARAMETER OperatingSystem
        目标操作系统，支持 `windows`、`linux`、`macos`。

    .OUTPUTS
        string[]
        返回多行提示文本。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [ValidateSet('windows', 'linux', 'macos')]
        [string]$OperatingSystem = $(if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' })
    )

    $escapedForSingleQuote = $Directory -replace "'", "''"
    switch ($OperatingSystem) {
        'windows' {
            return @(
                '安装目录尚未在 PATH 中。可在 PowerShell 中执行：',
                "[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User') + ';$escapedForSingleQuote', 'User')",
                '然后重新打开终端。'
            )
        }
        'macos' {
            return @(
                '安装目录尚未在 PATH 中。zsh 用户可执行：',
                "mkdir -p '$escapedForSingleQuote'",
                ('echo ''export PATH="{0}:$PATH"'' >> ~/.zshrc' -f $escapedForSingleQuote),
                '然后执行 source ~/.zshrc 或重新打开终端。'
            )
        }
        default {
            return @(
                '安装目录尚未在 PATH 中。bash/zsh 用户可执行：',
                "mkdir -p '$escapedForSingleQuote'",
                ('echo ''export PATH="{0}:$PATH"'' >> ~/.profile' -f $escapedForSingleQuote),
                '然后执行 source ~/.profile 或重新打开终端。'
            )
        }
    }
}

Export-ModuleMember -Function Get-Dotenv, Install-Dotenv, Import-EnvPath, Set-EnvPath, Add-EnvPath, Get-EnvParam, Remove-FromEnvPath, Sync-PathFromBash, Test-DirectoryInPath, Get-PathAddHint
