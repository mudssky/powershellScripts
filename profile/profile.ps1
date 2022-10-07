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


# $Env:http_proxy = "http://127.0.0.1:7890"; $Env:https_proxy = "http://127.0.0.1:7890";




# powershell ise 的别名
Set-Alias -Name ise -Value powershell_ise
Set-Alias -Name ipython -Value Start-Ipython

# powershell控制台编码设为utf8
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding

# cmdlets 的默认参数
$PSDefaultParameterValues["Out-File:Encoding"] = "UTF8"


# 开启基于历史命令的命令补全
Set-PSReadLineOption -PredictionSource History


# 配置git,解决中文文件名不能正常显示的问题
# git config --global core.quotepath false

# 提示符
# 开源的自定义提示符starship
# 1.choco install starship
# 2、Invoke-Expression (&starship init powershell)
if (Test-EXEProgram -Name starship) {
	Invoke-Expression (&starship init powershell)
}
else {
	# 不存在starship的时候，提示用户进行安装
	Write-Host -ForegroundColor Green  '未安装startship（一款开源提示符美化），可以运行以下命令进行安装 
	1.choco install starship 
	2.Invoke-Expression (&starship init powershell)'
}

if (Test-EXEProgram -Name sccache) {
	# 设置sccache用于rust编译缓存,提高新启动项目的编译速度
	$Env:RUSTC_WRAPPER = 'sccache';
}
