

$Env:http_proxy="http://127.0.0.1:7890";$Env:https_proxy="http://127.0.0.1:7890"
function Get-HistoryCommandRank([int]$top=10) {
 $count = 0; Get-Content  $env:USERPROFILE\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt | 
 ForEach-Object { ($_ -split ' ')[0]; $count += 1 } | 
 Group-Object | Sort-Object -Property Count  -Descending  -Top $top |
  Format-Table -Property Name, Count, @{Label = "Percentage"; Expression = { '{0:p2}' -f ($_.Count / $count) } } -AutoSize
}

# 获取脚本执行目录
function Get-ScriptFolder(){
	$currentScriptPath =  $MyInvocation.MyCommand.Definition
	$currentScriptFolder = Split-Path  -Parent   $currentScriptPath 
	return $currentScriptFolder
}


# 重新加载环境变量中的path，这样你在对应目录中新增一个exe就可以不用重启终端就能直接在终端运行了。
function Import-Envpath(){
	$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")
}