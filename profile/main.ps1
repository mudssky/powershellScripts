

$Env:http_proxy = "http://127.0.0.1:7890"; $Env:https_proxy = "http://127.0.0.1:7890";

# powershell ise 的别名
Set-Alias -Name ise -Value powershell_ise
Set-Alias -Name ipython -Value Start-Ipython


# cmdlets 的默认参数
$PSDefaultParameterValues["Out-File:Encoding"] = "UTF8"



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


