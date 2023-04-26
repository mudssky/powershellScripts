

[CmdletBinding()]
param(
	[switch]$loadProfile
)
# $Env:http_proxy = "http://127.0.0.1:7890"; $Env:https_proxy = "http://127.0.0.1:7890";

# 使用绝对路径导入,这样无论脚本在哪执行,PSScriptRoot都是脚本所在的位置
# Import-Module -Name "$PSScriptRoot\functions.psm1" -Verbose 
Import-Module -Name "$PSScriptRoot\functions.psm1"


# & 运算符是调用运算符，它可以在新的作用域中执行脚本文件或命令，这样脚本文件或命令中定义的变量、函数、别名等都不会影响当前会话。
# . 运算符是点源运算符，它可以在当前会话中执行脚本文件或命令，这样脚本文件或命令中定义的变量、函数、别名等都可以在当前会话中使用。
# 所以应该用.点源运算符
# 这种执行的操作,似乎不能封装到模块里执行.
function Add-CondaEnv() {
	. "$env:USERPROFILE\anaconda3\shell\condabin\conda-hook.ps1"
}

# powershell ise 的别名
Set-Alias -Name ise -Value powershell_ise
Set-Alias -Name ipython -Value Start-Ipython

# powershell控制台编码设为utf8
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding

# cmdlets 的默认参数
$PSDefaultParameterValues["Out-File:Encoding"] = "UTF8"


# 开启基于历史命令的命令补全
Set-PSReadLineOption -PredictionSource History

# 载入conda环境,环境变量中没有conda命令时执行
if (-not (Test-EXEProgram -Name conda)) {
	# Add-CondaEnv
	. "$env:USERPROFILE\anaconda3\shell\condabin\conda-hook.ps1"
}

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

if ($loadProfile) {
	Set-Content -Path $profile  -Value  ". $PSCommandPath"
}