

function Get-Dotenv {
    <#
	.SYNOPSIS
		解析dotenv内容为键值对保存到map中
	.DESCRIPTION
		此函数用于读取指定路径的 .env 文件，并将其内容解析为键值对的哈希表。每行格式为 KEY=VALUE 的内容将被解析，空行和注释行（以 # 开头）将被忽略。
	.PARAMETER Path
		.env 文件的绝对或相对路径。
	.OUTPUTS
		System.Collections.Hashtable
		返回一个哈希表，其中包含 .env 文件中解析出的所有键值对。
	.EXAMPLE
		Get-Dotenv -Path ".\project\.env"
		解析当前项目目录下的 .env 文件，并返回其内容。
	.NOTES
		作者: PowerShell Scripts
		版本: 1.0.0
		创建日期: 2025-01-07
		用途: 用于从 .env 文件中读取配置。
	#>
	
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




# 载入.env格式文件到环境变量
function Install-Dotenv {
    <#
	.SYNOPSIS
		加载dotenv文件到环境变量
	.DESCRIPTION
		此函数用于读取指定路径的 .env 文件，并将其内容加载到系统的环境变量中。支持将环境变量设置到机器、用户或当前进程级别。
		如果未指定 Path，函数将尝试在当前目录查找 .env.local 或 .env 文件。
	.PARAMETER Path
		.env 文件的绝对或相对路径。如果未提供，函数将尝试查找默认文件。
	.PARAMETER EnvTarget
		指定环境变量的目标级别：
		- Machine: 系统级环境变量，对所有用户和进程可见，需要管理员权限。
		- User: 用户级环境变量，对当前用户的所有进程可见。
		- Process: 进程级环境变量，仅对当前 PowerShell 进程可见。
		默认为 'User'。
	.OUTPUTS
		此函数没有直接输出。成功执行后，环境变量将被设置。
	.EXAMPLE
		Install-Dotenv -Path ".\project\.env" -EnvTarget User
		将指定 .env 文件的内容加载到当前用户的环境变量中。
	.EXAMPLE
		Install-Dotenv
		在当前目录查找 .env.local 或 .env 文件，并将其内容加载到当前用户的环境变量中。
	.NOTES
		作者: PowerShell Scripts
		版本: 1.0.0
		创建日期: 2025-01-07
		用途: 用于在 PowerShell 会话或系统环境中设置环境变量。
		默认情况下，如果未指定 Path，函数会按顺序查找 .env.local 和 .env 文件。
	#>
	
	
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



function Import-EnvPath {
    <#
	.SYNOPSIS
		重新加载环境变量中的PATH
	.DESCRIPTION
		重新加载环境变量中的PATH，支持三种模式：
		- Machine: 仅加载系统级PATH
		- User: 仅加载用户级PATH  
		- All: 合并系统级和用户级PATH（默认）
		这样你在对应目录中新增一个exe就可以不用重启终端就能直接在终端运行了。
	.PARAMETER EnvTarget
		指定要重新加载的PATH类型：
		- Machine: 仅系统级PATH
		- User: 仅用户级PATH
		- All: 合并系统级和用户级PATH
	.EXAMPLE
		Import-EnvPath
		重新加载合并的系统级和用户级PATH（默认行为）
	.EXAMPLE
		Import-EnvPath -EnvTarget User
		仅重新加载用户级PATH
	.EXAMPLE
		Import-EnvPath -EnvTarget Machine
		仅重新加载系统级PATH
	.NOTES
		合并模式下，系统级PATH优先于用户级PATH
	#>

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


function Set-EnvPath {
    <#
	.SYNOPSIS
		设置环境变量path,直接整个替换
	.DESCRIPTION
		设置环境变量path,直接整个替换，建议先做好备份
	.NOTES
		Information or caveats about the function e.g. 'This function is not supported in Linux'
	.LINK
		Specify a URI to a help page, this will show when Get-Help -Online is used.
	.EXAMPLE
		Test-MyTestFunction -Verbose
		Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines

	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        # 这里是Path的值
        $PathStr,
        [ValidateSet('Machine', 'User', 'Process')]
        [string]$EnvTarget = 'User'
    )
	
    begin {
        Write-Host 	"current env path:$env:Path"
    }
	
    process {
        [Environment]::SetEnvironmentVariable("Path", $PathStr, $EnvTarget)
    }
	
    end {
        # 导入环境变量
        Import-Envpath -EnvTarget User
    }
}


function Add-EnvPath {
    <#
	.SYNOPSIS
		设置环境变量path,增加一个新的path
	.DESCRIPTION
		设置环境变量path，支持user path和system path
	.NOTES
		Information or caveats about the function e.g. 'This function is not supported in Linux'
	.LINK
		Specify a URI to a help page, this will show when Get-Help -Online is used.
	.EXAMPLE
		Get-EnvParam -ParamName 'Path' -EnvTarget User
		获取当前用户的Path环境变量值

	#>
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
        Import-Envpath -EnvTarget User
    }
}

function Get-EnvParam {
    <#
	.SYNOPSIS
	获取环境变量中的参数，ParamName不指定时获取Path。可以指定EnvTarget 'Machine', 'User', 'Process
	.DESCRIPTION
		设置环境变量path，支持user path和system path
	.NOTES
		Information or caveats about the function e.g. 'This function is not supported in Linux'
	.LINK
		Specify a URI to a help page, this will show when Get-Help -Online is used.
	.EXAMPLE
		Test-MyTestFunction -Verbose
		Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines

	#>
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

function Remove-FromEnvPath {
    <#
	.SYNOPSIS
		从环境变量path移除一个path
	.DESCRIPTION
		设置环境变量path，支持user path和system path
	.NOTES
		Information or caveats about the function e.g. 'This function is not supported in Linux'
	.LINK
		Specify a URI to a help page, this will show when Get-Help -Online is used.
	.EXAMPLE
		Test-MyTestFunction -Verbose
		Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines

	#>
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
        Import-Envpath -EnvTarget User
    }
}




function Sync-PathFromBash {
    <#
    .SYNOPSIS
        Compares the PATH from a Bash login shell with the current PowerShell PATH
        and appends any missing paths to the PowerShell session.
    .DESCRIPTION
        This function is designed for running PowerShell on Linux/macOS.
        It invokes a Bash login shell (`bash -l`) to reliably get the fully
        configured PATH environment variable. It then compares this with the
        current PowerShell session's PATH and adds any paths that are present
        in Bash but missing in PowerShell.
    .EXAMPLE
        Sync-PathFromBash -Verbose
        This will run the sync and provide detailed output on which paths were found
        and which were added.
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Information "正在从 Bash 登录 Shell 中获取 PATH..."
        # 使用 'bash -l' 确保加载了 ~/.profile 或 ~/.bash_profile
        # '-c' 表示执行后面的命令
        $bashPathOutput = bash -l -c 'echo $PATH'
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "无法从 Bash 获取 PATH。Bash 可能未安装或存在配置错误。"
            return
        }

        # 获取跨平台的路径分隔符 (Linux/macOS 上是 ':')
        $separator = [System.IO.Path]::PathSeparator

        # 将 Bash 和 PowerShell 的 PATH 字符串拆分为数组，并过滤掉空条目
        $bashPaths = $bashPathOutput.Split($separator, [System.StringSplitOptions]::RemoveEmptyEntries)
        $psPaths = $env:PATH.Split($separator, [System.StringSplitOptions]::RemoveEmptyEntries)

        Write-Information "从 Bash 中找到的路径: $($bashPaths.Count) 个"
        Write-Information "当前 PowerShell 中的路径: $($psPaths.Count) 个"

        # 使用 Compare-Object 找出只存在于 Bash PATH 中的路径
        # ReferenceObject 是基准，DifferenceObject 是要比较的对象
        $missingPaths = Compare-Object -ReferenceObject $psPaths -DifferenceObject $bashPaths -PassThru | Where-Object { $_ -ne $null }

        if ($missingPaths.Count -gt 0) {
            Write-Information "发现 $($missingPaths.Count) 个需要从 Bash 同步的路径。" 

            # 将找到的缺失路径连接成一个字符串
            $pathsToAdd = $missingPaths -join $separator

            # 遍历并显示将要添加的每一个路径
            foreach ($path in $missingPaths) {
                Write-Information "  -> 正在添加: $path" 
            }

            # 将新路径追加到现有的 PowerShell PATH 后面
            $env:PATH = "$($env:PATH)$separator$pathsToAdd"
            Write-Information "PowerShell PATH 已成功更新！" 
        } else {
            Write-Information "Power-Shell 的 PATH 与 Bash 完全同步，无需操作。"
        }
    }
    catch {
        Write-Error "同步 PATH 时发生错误: $_"
    }
}


Export-ModuleMember -Function Get-Dotenv, Install-Dotenv,Import-EnvPath, Set-EnvPath, Add-EnvPath, Get-EnvParam, Remove-FromEnvPath,Sync-PathFromBash