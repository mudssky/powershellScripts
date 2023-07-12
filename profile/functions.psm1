function Get-HistoryCommandRank([int]$top = 10) {
 $count = 0; Get-Content  $env:USERPROFILE\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt | 
 ForEach-Object { ($_ -split ' ')[0]; $count += 1 } | 
 Group-Object | Sort-Object -Property Count  -Descending  -Top $top |
	Format-Table -Property Name, Count, @{Label = "Percentage"; Expression = { '{0:p2}' -f ($_.Count / $count) } } -AutoSize
}

# 获取脚本执行目录
function Get-ScriptFolder() {
	$currentScriptPath = $MyInvocation.MyCommand.Definition
	$currentScriptFolder = Split-Path  -Parent   $currentScriptPath 
	return $currentScriptFolder
}


# 获取脚本文件的路径
# function Get-ScriptPath() {
# 当前脚本运行的路径
#  $PSScriptRoot
# 这个变量包含运行脚本模块的完全路径,包括文件名
# 所以会获取当前这个psm1文件的路径
# $PSCommandPath
# }




# 重新加载环境变量中的path，这样你在对应目录中新增一个exe就可以不用重启终端就能直接在终端运行了。
function Import-Envpath() {
	$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
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


function Start-Ipython () {
	python -m IPython
}

function Start-PSReadline() {
	# 安装
	Install-Module -Name PSReadLine -AllowClobber -Force
	# 开启基于历史记录的智能提示
	Set-PSReadLineOption -PredictionSource History
}



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
	# get-command  return $null  when cant find command and  SilentlyContinue flag on 
	return ($null -ne (Get-Command -Name $Name  -CommandType Application  -ErrorAction SilentlyContinue ))
}


function New-Shortcut {
	[CmdletBinding()]
	param (
		# 需要创建快捷方式的目标路径
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Path,
		[Parameter(Mandatory = $true, Position = 1)]
		[string]$Destination 
	)
	
	begin {
	
	}
	
	process {
		$shell = New-Object -ComObject "WScript.Shell"
		$link = $shell.CreateShortcut($Destination)
		$link.TargetPath = $Path
		$link.Save()
	}
	
	end {
		
	}
}



$internetSettingPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

function Start-Proxy() {
	param(
	
		[string]$URL = 'http://127.0.0.1:8080',
		[string]$username,
		[SecureString]$password
	)
	
	Set-ItemProperty -Path $internetSettingPath -Name ProxyServer -Value $URL
	if ($username -and $password) {
		Set-ItemProperty -Path $internetSettingPath -Name ProxyUser  -Value $username
		Set-ItemProperty -Path $internetSettingPath -Name ProxyPass  -Value $password
	}

	# 启用代理服务
	Set-ItemProperty -Path $internetSettingPath -Name ProxyEnable -Value 1
	# 重启windows代理自动检测服务，使其生效
	# Restart-Service -Name WinHttpAutoProxySvc
}

function Close-Proxy() {
	# 关闭代理服务
	Set-ItemProperty -Path $internetSettingPath -Name ProxyEnable -Value 0
}

Export-ModuleMember -Function *

