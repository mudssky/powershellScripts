[CmdletBinding()]
param(
	[switch]$loadProfile
)

# 使用绝对路径导入,这样无论脚本在哪执行,PSScriptRoot都是脚本所在的位置
# Import-Module -Name "$PSScriptRoot\functions.psm1" -Verbose 
Import-Module -Name "$PSScriptRoot\functions.psm1"

# 开启基于历史命令的命令补全
Set-PSReadLineOption -PredictionSource History

if (Test-EXEProgram -Name starship) {
	Invoke-Expression (&starship init powershell)
}
else {
	# 不存在starship的时候，提示用户进行安装
	Write-Host -ForegroundColor Green  '未安装startship（一款开源提示符美化），可以运行以下命令进行安装 
	1.choco install starship 
	2.Invoke-Expression (&starship init powershell)'
}



if ($loadProfile) {
	Set-Content -Path $profile  -Value  ". $PSCommandPath"
}