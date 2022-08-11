
$currentScriptPath = $MyInvocation.MyCommand.Definition
# 当前脚本目录
$currentScriptFolder = Split-Path  -Parent   $currentScriptPath 

# 拼接生成profile脚本
('functions.psm1', 'main.ps1' | ForEach-Object { Get-Content -Path $_ } ) | Out-File -Path 'profile.ps1' -Encoding utf8

if (-not (Test-Path  -Path $profile )) {
	Write-Host ('创建profile文件: {0}' -f $profile) -ForegroundColor Green
	New-Item -Path $profile -Force
}

Set-Content -Path $profile  -Value (Get-Content $currentScriptFolder/profile.ps1)