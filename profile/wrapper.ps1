<#
.SYNOPSIS
    Yazi文件管理器包装函数，支持目录切换

.DESCRIPTION
    启动Yazi文件管理器，并在退出时自动切换到选择的目录。
    Windows下会自动配置file.exe路径以支持文件类型检测。

.PARAMETER Arguments
    传递给yazi的参数

.EXAMPLE
    yaz
    启动Yazi文件管理器

.EXAMPLE
    yaz /path/to/directory
    在指定目录启动Yazi

.NOTES
    作者: mudssky
    版本: 1.0
    依赖: yazi, Git for Windows (提供file.exe)
#>
function yaz {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )
    
    # Windows下配置file.exe路径
    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        # 检查是否已设置YAZI_FILE_ONE环境变量
        if (-not $env:YAZI_FILE_ONE) {
            # 尝试找到Git安装目录下的file.exe
            $gitPaths = @(
                "$env:ProgramFiles\Git\usr\bin\file.exe",
                "$env:ProgramFiles(x86)\Git\usr\bin\file.exe",
                "$env:USERPROFILE\scoop\apps\git\current\usr\bin\file.exe",
                "$env:LOCALAPPDATA\Programs\Git\usr\bin\file.exe"
            )
            
            $fileExePath = $gitPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            
            if ($fileExePath) {
                $env:YAZI_FILE_ONE = $fileExePath
                Write-Verbose "已设置YAZI_FILE_ONE环境变量: $fileExePath"
            }
            else {
                Write-Warning "未找到file.exe，请安装Git for Windows或手动设置YAZI_FILE_ONE环境变量"
            }
        }
    }
    
    # 检查yazi是否可用
    if (-not (Test-ExeProgram -Name 'yazi')) {
        Write-Error "未找到yazi命令，请先安装yazi文件管理器"
        return
    }
    
    # 创建临时文件存储目录路径
    $tmp = (New-TemporaryFile).FullName
    
    try {
        # 启动yazi并传递参数
        yazi @Arguments --cwd-file="$tmp"
        
        # 读取退出时的目录路径
        if (Test-Path $tmp) {
            $cwd = Get-Content -Path $tmp -Encoding UTF8 -ErrorAction SilentlyContinue
            if (-not [String]::IsNullOrWhiteSpace($cwd) -and $cwd -ne $PWD.Path) {
                if (Test-Path $cwd) {
                    Set-Location -LiteralPath (Resolve-Path -LiteralPath $cwd).Path
                    Write-Host "已切换到目录: $cwd" -ForegroundColor Green
                }
                else {
                    Write-Warning "目标目录不存在: $cwd"
                }
            }
        }
    }
    catch {
        Write-Error "启动yazi时出错: $($_.Exception.Message)"
    }
    finally {
        # 清理临时文件
        if (Test-Path $tmp) {
            Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}


<#
.SYNOPSIS
    从函数的帮助文档中提取函数包装信息
.DESCRIPTION
    解析指定函数的帮助文档，提取函数名、描述、版本、作者等信息
.PARAMETER FunctionName
    要解析的函数名
#>
function Get-FunctionWrapperInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FunctionName
    )
	
    try {
        # 获取函数的帮助信息
        $help = Get-Help $FunctionName -ErrorAction Stop

        # 从描述中提取基础CLI和功能特性
        $description = $help.Description.Text -join ' '
		
        return [PSCustomObject]@{
            functionName = $FunctionName
            description  = $description
        }
    }
    catch {
        Write-Warning "无法获取函数 $FunctionName 的帮助信息: $($_.Exception.Message)"
        return $null
    }
}





function Get-CustomFunctionWrapperInfos {
    [CmdletBinding()]
    param (
        
    )
    
    begin {
        $customFunctionWrappers = @()
    }
    
    process {
        $wrapperFunctions = @('yaz')  # 可以根据需要添加更多函数名
        
        foreach ($funcName in $wrapperFunctions) {
            if (Get-Command $funcName -ErrorAction SilentlyContinue) {
                $wrapperInfo = Get-FunctionWrapperInfo -FunctionName $funcName
                if ($wrapperInfo) {
                    $customFunctionWrappers += $wrapperInfo
                }
            }
            else {
                Write-Verbose "函数 $funcName 未找到，跳过"
            }
        }
    }
    
    end {
        return $customFunctionWrappers
    }
}




<#
	.SYNOPSIS
		添加Conda环境到当前PowerShell会话
	
	.DESCRIPTION
		检查用户主目录下的Anaconda3安装路径，如果存在conda-hook.ps1文件则加载它，
		以便在当前PowerShell会话中使用conda命令。
	
	.OUTPUTS
		无返回值，加载Conda环境到当前会话
	
	.EXAMPLE
		Add-CondaEnv
		加载Conda环境
	
	.NOTES
		作者: PowerShell Scripts
		版本: 1.0.0
		创建日期: 2025-01-07
		用途: 在PowerShell中启用Conda环境管理
	#>
function Add-CondaEnv {
    $condaPath = "$env:USERPROFILE\anaconda3\shell\condabin\conda-hook.ps1"
    if (Test-Path -Path $condaPath) {
        Write-Verbose "加载Conda环境: $condaPath"
        . $condaPath 
    }
}
