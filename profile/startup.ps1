param(
	[switch]$LoadStartup
)

Import-Module -Name ./functions.psm1 -Verbose -Force

# 开机执行的脚本
# 启动stable-diffusion-webui

# 注意要设置一下ps1脚本的打开方式,用powershell或者pwsh打开,不然脚本无法正常执行.
function Start-SdWebUI() {
	$webuiPath = 'C:\AI\stable-diffusion\stable-diffusion-webui'
	Set-Location $webuiPath
	# 1.激活虚拟环境
	Write-Host '激活虚拟环境'
	& "$webuiPath\venv\Scripts\activate.ps1"
	# 2.运行批处理启动
	Write-Host '运行启动bat'
	& "$webuiPath\webui-user.ps1"
}

Start-SdWebUI

$startupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

if ($LoadStartup) {
	
	$filename = Split-Path -Path $PSCommandPath  -Leaf
	$newpath = Join-Path -Path $startupPath -ChildPath $filename.Replace('.ps1', '.ink')
	New-Item -Path $newpath -ItemType SymbolicLink -Value $PSCommandPath

}


# Read-Host -Prompt "Press Enter to exit"