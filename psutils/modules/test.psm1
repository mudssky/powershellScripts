

<#
.Synopsis
	判断环境变量中是否存在可执行程序
.DESCRIPTION
   详细描述
.EXAMPLE
   如何使用此 cmdlet 的示例
.EXAMPLE
   另一个如何使用此 cmdlet 的示例
.INPUTS
   到此 cmdlet 的输入(如果有)
.OUTPUTS
   来自此 cmdlet 的输出(如果有)
.NOTES
   一般注释
.COMPONENT
   此 cmdlet 所属的组件
.ROLE
   此 cmdlet 所属的角色
.FUNCTIONALITY
   最准确描述此 cmdlet 的功能
#>
function Test-EXEProgram() {
	Param
	(	
		[Parameter(Mandatory = $true, 
		 ValueFromPipeline = $true,
		 Position = 0 )]
		[ValidateNotNull()]
		[ValidateNotNullOrEmpty()]
		[string]
		$Name
	)
	process {
		# get-command  return $null  when cant find command and  SilentlyContinue flag on 
		return ($null -ne (Get-Command -Name $Name  -CommandType Application  -ErrorAction SilentlyContinue ))
	}

}


# 判断数组是否为非空
function Test-ArrayNotNull() {
	param(
		$array
	)
	if ( $null -ne $array -and @($array).count -gt 0 ) {
		return $True
	}
	return $False
}

function Test-PathMust() {
	param (
		$Path
	)
	if (-not (Test-Path $Path)) {
		throw "the path $Path is not exist"
	}
}

function Test-PathHasExe {
	<#
	.SYNOPSIS
		判断路径中是否含有exe，或者可执行脚本ps1等。如果路径不存在也返回false
	.DESCRIPTION
		A longer description of the function, its purpose, common use cases, etc.
	.NOTES
		Information or caveats about the function e.g. 'This function is not supported in Linux'
	.LINK
		Specify a URI to a help page, this will show when Get-Help -Online is used.
	.EXAMPLE
		Test-MyTestFunction -Verbose
		Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
	#>
	
	
	param(
		[string]
		$Path = '.'
	)
	
	


	# 1. 检查路径是否存在
	if ( -not (Test-Path -Path $Path)) {
		Write-Debug "the path $Path is not exist"
		return $false
	}
	# 2. 检查路径是否是目录
	# 可以用Test-Path指定PathType来判断，Container是目录
	# Test-Path $Path -PathType Leaf
	$item = Get-Item $Path

	if ($item.PSIsContainer) {
		# 目录的情况
		# 遍历单层文件判断是否有可执行文件
		$exeList = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue | where-object { $_.Extension -in '.exe', '.cmd', '.bat', '.ps1' } 
		if ($exeList.Count -gt 0) {
			Write-Debug "the path $Path has exe file $($_.FullName)"
			return $true
		}

		Write-Debug "the path $Path has no exe file"
		return $false
	}
 else {
		#   非目录的情况，只需判断路径是否是.exe结尾
		Write-Debug "the path $Path is not a directory"
		return $item.Extension -eq '.exe'

	}

  	

}
function Test-MacOSCaskApp {
    <#
    .SYNOPSIS
        检测macOS上通过brew cask安装的应用程序是否已安装
    .DESCRIPTION
        通过检查/Applications目录或使用brew list --cask命令来判断macOS应用程序是否已安装
    .PARAMETER AppName
        要检测的应用程序名称
    .PARAMETER UseBrew
        是否使用brew命令检测，默认为$true。如果为$false则检查/Applications目录
    .EXAMPLE
        Test-MacOSCaskApp -AppName "DockDoor"
        检测DockDoor应用是否已安装
    .EXAMPLE
        Test-MacOSCaskApp -AppName "Visual Studio Code" -UseBrew $false
        通过检查Applications目录来检测VS Code是否已安装
    .OUTPUTS
        [bool] 如果应用已安装返回$true，否则返回$false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        
        [Parameter()]
        [bool]$UseBrew = $true
    )
    
    try {
        if ($UseBrew) {
            # 使用brew命令检测
            if (Test-EXEProgram -Name "brew") {
                $brewList = brew list --cask 2>$null
                if ($LASTEXITCODE -eq 0) {
                    return $brewList -contains $AppName
                }
            }
            # 如果brew命令失败，回退到目录检查
        }
        
        # 检查/Applications目录
        $appPath = "/Applications/$AppName.app"
        return (Test-Path $appPath)
    }
    catch {
        Write-Warning "检测macOS应用 '$AppName' 时发生错误: $_"
        return $false
    }
}

function Test-HomebrewFormula {
    <#
    .SYNOPSIS
        检测macOS上通过brew安装的formula是否已安装
    .DESCRIPTION
        通过使用brew list命令来判断macOS Homebrew formula是否已安装
    .PARAMETER AppName
        要检测的formula名称
    .EXAMPLE
        Test-HomebrewFormula -AppName "sevenzip"
        检测sevenzip formula是否已安装
    .OUTPUTS
        [bool] 如果formula已安装返回$true，否则返回$false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName
    )
    
    try {
        if (Test-EXEProgram -Name "brew") {
            $brewList = brew list 2>$null
            if ($LASTEXITCODE -eq 0) {
                return $brewList -contains $AppName
            }
        }
        return $false
    }
    catch {
        Write-Warning "检测Homebrew formula '$AppName' 时发生错误: $_"
        return $false
    }
}

function Test-ApplicationInstalled {
    <#
    .SYNOPSIS
        跨平台应用程序安装检测
    .DESCRIPTION
        整合了跨平台应用安装检测逻辑，支持Windows、macOS和Linux系统。
        在macOS上会同时检测命令行程序和cask应用，在其他系统上使用命令行程序检测。
    .PARAMETER AppName
        要检测的应用程序名称
    .PARAMETER FilterCli
        是否仅检测命令行程序，默认为$false（检测所有类型）
    .EXAMPLE
        Test-ApplicationInstalled -AppName "git"
        检测git是否已安装（包括命令行和应用程序）
    .EXAMPLE
        Test-ApplicationInstalled -AppName "git" -FilterCli $true
        仅检测git命令行工具是否已安装
    .EXAMPLE
        Test-ApplicationInstalled -AppName "dockdoor"
        在macOS上检测DockDoor（会同时检测命令行和cask应用）
    .OUTPUTS
        [bool] 如果应用已安装返回$true，否则返回$false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        
        [Parameter()]
        [bool]$FilterCli = $false
    )
    
    try {
        # 获取当前操作系统
        $os = Get-OperatingSystem
        
        Write-Verbose "当前操作系统: $os"
        Write-Verbose "检测应用: $AppName (FilterCli: $FilterCli)"
        
        switch ($os) {
            "macOS" {
                return Test-MacOSApplicationInstalled -AppName $AppName -FilterCli $FilterCli
            }
            { $_ -in @("Windows", "Linux") } {
                # Windows和Linux使用命令行程序检测
                return Test-EXEProgram -Name $AppName
            }
            default {
                Write-Warning "未知操作系统: $os，使用默认命令行程序检测"
                return Test-EXEProgram -Name $AppName
            }
        }
    }
    catch {
        Write-Error "检测应用程序 '$AppName' 时发生错误: $($_.Exception.Message)"
        return $false
    }
}

function Test-MacOSApplicationInstalled {
    <#
    .SYNOPSIS
        检测macOS上应用程序是否已安装
    .DESCRIPTION
        在macOS上，根据FilterCli参数检测命令行程序、cask应用或Homebrew formula。
    .PARAMETER AppName
        要检测的应用程序名称
    .PARAMETER FilterCli
        是否仅检测命令行程序，默认为$false（检测所有类型）
    .EXAMPLE
        Test-MacOSApplicationInstalled -AppName "git"
        检测git是否已安装（包括命令行和应用程序）
    .EXAMPLE
        Test-MacOSApplicationInstalled -AppName "git" -FilterCli $true
        仅检测git命令行工具是否已安装
    .OUTPUTS
        [bool] 如果应用已安装返回$true，否则返回$false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        
        [Parameter()]
        [bool]$FilterCli = $false
    )

    if ($FilterCli) {
        # 仅检测命令行程序
        return Test-EXEProgram -Name $AppName
    }
    else {
        # 检测所有类型：先检测命令行程序，再检测cask应用和formula
        $cliInstalled = Test-EXEProgram -Name $AppName
        if ($cliInstalled) {
            return $true
        }
        
        # 如果命令行程序未安装，检测cask应用
        $caskInstalled = Test-MacOSCaskApp -AppName $AppName -UseBrew $true
        if ($caskInstalled) {
            return $true
        }

        # 如果cask应用也未安装，检测Homebrew formula
        return Test-HomebrewFormula -AppName $AppName
    }
}

Export-ModuleMember -Function *