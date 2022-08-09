

$Env:http_proxy = "http://127.0.0.1:7890"; $Env:https_proxy = "http://127.0.0.1:7890";

# powershell ise 的别名
Set-Alias -Name ise -Value powershell_ise
Set-Alias -Name ipython -Value Start-Ipython


# cmdlets 的默认参数
$PSDefaultParameterValues["Out-File:Encoding"] = "UTF8"

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