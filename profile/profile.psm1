

# $Env:http_proxy="http://127.0.0.1:7890";$Env:https_proxy="http://127.0.0.1:7890"
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


Export-ModuleMember -Function Get-HistoryCommandRank
Export-ModuleMember -Function Get-ScriptFolder