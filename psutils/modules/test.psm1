

<#
.SYNOPSIS
    判断环境变量中是否存在可执行程序。

.DESCRIPTION
    此函数用于检查系统环境变量 PATH 中是否存在指定名称的可执行程序（应用程序）。
    它通过尝试获取命令来判断程序是否存在，并返回布尔值。

.PARAMETER Name
    必需参数。要检查的可执行程序的名称。

.INPUTS
    字符串。可以通过管道传递程序名称。

.OUTPUTS
    布尔值。如果找到可执行程序，则返回 $true；否则返回 $false。

.EXAMPLE
    Test-EXEProgram -Name "notepad.exe"
    检查 "notepad.exe" 是否存在于环境变量中。

.EXAMPLE
    "git", "node" | Test-EXEProgram
    通过管道检查 "git" 和 "node" 是否存在。

.NOTES
    此函数使用 Get-Command -CommandType Application 来查找可执行程序。
    它会静默处理错误，因此不会在找不到程序时抛出错误。
    适用于Windows、Linux和macOS等支持PowerShell的平台。

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


<#
.SYNOPSIS
    判断数组是否为非空。

.DESCRIPTION
    此函数用于检查给定的数组是否为 null 且是否包含元素。
    如果数组不为 null 且包含至少一个元素，则返回 $true；否则返回 $false。

.PARAMETER array
    要检查的数组。

.OUTPUTS
    布尔值。如果数组非空，则返回 $true；否则返回 $false。

.EXAMPLE
    Test-ArrayNotNull -array @(1, 2, 3)
    返回 $true。

.EXAMPLE
    Test-ArrayNotNull -array @()
    返回 $false。

.EXAMPLE
    Test-ArrayNotNull -array $null
    返回 $false。

.NOTES
    此函数可以用于在脚本中进行数组有效性检查，避免对空数组进行操作时引发错误。
#>
function Test-ArrayNotNull() {
	param(
		$array
	)
	if ( $null -ne $array -and @($array).count -gt 0 ) {
		return $True
	}
	return $False
}

<#
.SYNOPSIS
    验证指定路径是否存在。

.DESCRIPTION
    此函数用于检查给定的文件系统路径是否存在。如果路径不存在，它将抛出一个错误。
    这对于在脚本中执行文件或目录操作之前进行前置条件检查非常有用。

.PARAMETER Path
    必需参数。要验证的路径。

.OUTPUTS
    无。如果路径存在，函数将正常完成；如果路径不存在，则抛出错误。

.EXAMPLE
    Test-PathMust -Path "C:\Windows"
    如果 C:\Windows 存在，则不执行任何操作。

.EXAMPLE
    Test-PathMust -Path "C:\NonExistentFolder"
    如果 C:\NonExistentFolder 不存在，则抛出错误。

.NOTES
    此函数通过抛出错误来强制执行路径存在性检查，这有助于在脚本早期发现问题。
#>
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
	    判断路径中是否含有可执行文件。

	.DESCRIPTION
	    此函数用于检查指定路径下是否包含可执行文件（如 .exe 或 .ps1 脚本）。
	    如果路径不存在，则直接返回 $false。

	.PARAMETER Path
	    可选参数。要检查的路径。默认为当前目录 '.'。

	.OUTPUTS
	    布尔值。如果路径存在且包含可执行文件，则返回 $true；否则返回 $false。

	.EXAMPLE
	    Test-PathHasExe -Path "C:\Program Files\Git\bin"
	    检查指定 Git 安装路径下是否包含可执行文件。

	.EXAMPLE
	    Test-PathHasExe
	    检查当前目录下是否包含可执行文件。

	.NOTES
	    此函数会遍历指定路径下的所有文件，并根据文件扩展名判断是否为可执行文件。
	    目前支持的扩展名包括 .exe, .com, .bat, .cmd, .ps1。
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
    检测macOS上通过brew cask安装的应用程序是否已安装。

.DESCRIPTION
    此函数用于检查macOS系统上是否已安装通过 Homebrew Cask 管理的应用程序。
    它通过检查 `/Applications` 目录中是否存在对应的应用程序包或使用 `brew list --cask` 命令来判断。

.PARAMETER AppName
    必需参数。要检查的应用程序的名称，例如 "google-chrome" 或 "iterm2"。

.OUTPUTS
    布尔值。如果应用程序已安装，则返回 $true；否则返回 $false。

.EXAMPLE
    Test-MacOSCaskApp -AppName "google-chrome"
    检查 Google Chrome 浏览器是否已安装。

.EXAMPLE
    Test-MacOSCaskApp -AppName "visual-studio-code"
    检查 Visual Studio Code 是否已安装。

.NOTES
    此函数仅适用于 macOS 系统。
    它会尝试通过两种方式检测：首先检查 `/Applications` 目录，然后尝试执行 `brew list --cask` 命令。
    如果系统中未安装 Homebrew 或 brew 命令不可用，则可能无法准确检测通过 Homebrew Cask 安装的应用程序。

    .PARAMETER AppName
    必需参数。要检查的应用程序的名称，例如 "google-chrome" 或 "iterm2"。

.PARAMETER UseBrew
    可选参数。是否使用 `brew` 命令检测。默认为 `$true`。如果设置为 `$false`，则仅检查 `/Applications` 目录。

.OUTPUTS
    布尔值。如果应用程序已安装，则返回 $true；否则返回 $false。

.EXAMPLE
    Test-MacOSCaskApp -AppName "google-chrome"
    检查 Google Chrome 浏览器是否已安装。

.EXAMPLE
    Test-MacOSCaskApp -AppName "visual-studio-code" -UseBrew $false
    通过检查 `/Applications` 目录来检测 Visual Studio Code 是否已安装。

.NOTES
    此函数仅适用于 macOS 系统。
    它会尝试通过两种方式检测：首先检查 `/Applications` 目录，然后尝试执行 `brew list --cask` 命令。
    如果系统中未安装 Homebrew 或 `brew` 命令不可用，则可能无法准确检测通过 Homebrew Cask 安装的应用程序。

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
    检测macOS上通过 Homebrew 安装的 formula 是否已安装。

.DESCRIPTION
    此函数用于检查macOS系统上是否已安装通过 Homebrew 管理的 formula（命令行工具或库）。
    它通过执行 `brew list` 命令并检查输出中是否包含指定的 formula 名称来判断。

.PARAMETER AppName
    必需参数。要检查的 Homebrew formula 的名称，例如 "sevenzip" 或 "node"。

.OUTPUTS
    布尔值。如果 formula 已安装，则返回 $true；否则返回 $false。

.EXAMPLE
    Test-HomebrewFormula -AppName "sevenzip"
    检查 "sevenzip" formula 是否已安装。

.EXAMPLE
    Test-HomebrewFormula -AppName "node"
    检查 "node" formula 是否已安装。

.NOTES
    此函数仅适用于 macOS 系统。
    它依赖于 Homebrew 的正确安装和 `brew` 命令的可用性。
    如果系统中未安装 Homebrew 或 `brew` 命令不可用，则可能无法准确检测 formula 的安装状态。

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
    跨平台应用程序安装检测。

.DESCRIPTION
    此函数整合了跨平台应用程序安装检测逻辑，支持 Windows、macOS 和 Linux 系统。
    在 macOS 上，它会同时检测命令行程序和通过 Homebrew Cask 安装的应用程序；
    在其他系统上，主要使用命令行程序检测。

.PARAMETER AppName
    必需参数。要检测的应用程序名称。

.PARAMETER FilterCli
    可选参数。是否仅检测命令行程序。默认为 `$false`（检测所有类型）。

.OUTPUTS
    布尔值。如果应用程序已安装，则返回 $true；否则返回 $false。

.EXAMPLE
    Test-ApplicationInstalled -AppName "git"
    检测 "git" 是否已安装（包括命令行和应用程序）。

.EXAMPLE
    Test-ApplicationInstalled -AppName "git" -FilterCli $true
    仅检测 "git" 命令行工具是否已安装。

.EXAMPLE
    Test-ApplicationInstalled -AppName "dockdoor"
    在 macOS 上检测 "DockDoor"（会同时检测命令行和 cask 应用）。

.NOTES
    此函数会根据当前操作系统类型调用相应的检测子函数。
    在 Windows 和 Linux 上，它主要依赖于 `Test-EXEProgram` 来检测命令行工具。
    在 macOS 上，它会同时使用 `Test-EXEProgram` 和 `Test-MacOSCaskApp` 进行检测。

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
    检测 macOS 上应用程序是否已安装。

.DESCRIPTION
    此函数在 macOS 上，根据 `FilterCli` 参数检测命令行程序、Homebrew Cask 应用或 Homebrew Formula。

.PARAMETER AppName
    必需参数。要检测的应用程序名称。

.PARAMETER FilterCli
    可选参数。是否仅检测命令行程序。默认为 `$false`（检测所有类型）。

.OUTPUTS
    布尔值。如果应用程序已安装，则返回 $true；否则返回 $false。

.EXAMPLE
    Test-MacOSApplicationInstalled -AppName "git"
    检测 "git" 是否已安装（包括命令行和应用程序）。

.EXAMPLE
    Test-MacOSApplicationInstalled -AppName "git" -FilterCli $true
    仅检测 "git" 命令行工具是否已安装。

.NOTES
    此函数会首先尝试检测命令行程序，如果未安装，则继续检测 Homebrew Cask 应用和 Homebrew Formula。
    它依赖于 `Test-EXEProgram`、`Test-MacOSCaskApp` 和 `Test-HomebrewFormula` 函数进行实际检测。

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

Export-ModuleMember -Function Test-ModuleFunction,Test-ExeProgram,Test-ArrayNotNull,Test-PathHasExe