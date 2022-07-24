# Import-Module './profile.psm1'
$currentScriptPath =  $MyInvocation.MyCommand.Definition
$currentScriptFolder = Split-Path  -Parent   $currentScriptPath 

if (-not (Test-Path  -Path $profile )){
	Write-Host ('创建profile文件: {0}' -f $profile) -ForegroundColor Green
	New-Item -Path $profile -Force
}

Set-Content -Path $profile  -Value (Get-Content $currentScriptFolder/profile.ps1)