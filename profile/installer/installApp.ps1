
<#
.Synopsis
    自动安装开发环境所需的各种命令行工具
.DESCRIPTION
    通过 Chocolatey、Scoop、Cargo 等包管理器自动检测并安装开发工具
.EXAMPLE
    .\installApp.ps1
    执行脚本安装所有配置的工具
.EXAMPLE
    .\installApp.ps1 -WhatIf
    预览将要执行的安装操作
.NOTES
    需要管理员权限安装 Chocolatey，Scoop 需要非管理员权限
#>

[CmdletBinding(SupportsShouldProcess)]
param(
	# [switch]$Confirm
)

$parentFolder = Split-Path -Parent $PSScriptRoot
. $parentFolder/loadModule.ps1



function Initialize-PackageManagers() {
	[CmdletBinding(SupportsShouldProcess)]
	param()
	
	# 检查并安装 Scoop
	if (-not (Test-EXEProgram scoop)) {
		if ($PSCmdlet.ShouldProcess('Scoop', '安装包管理器')) {
			Write-Host '由于scoop禁止管理员权限安装,请先在非管理员环境安装后,再继续执行' -ForegroundColor Yellow
			Write-Host '执行下面的语句安装:' -ForegroundColor Yellow
			Write-Host 'Invoke-WebRequest -useb get.scoop.sh | Invoke-Expression' -ForegroundColor Cyan
			return $false
		}
	}
	
	# 检查并安装 Chocolatey
	if (-not (Test-EXEProgram choco)) {
		if ($PSCmdlet.ShouldProcess('Chocolatey', '安装包管理器')) {
			Write-Host '正在安装 Chocolatey...' -ForegroundColor Yellow
			[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
			Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
		}
	}
	
	# 检查并安装 Go 版本管理器 g
	if (-not (Test-EXEProgram g)) {
		if ($PSCmdlet.ShouldProcess('g', '安装Go版本管理器')) {
			Write-Host '正在安装 Go 版本管理器 g...' -ForegroundColor Yellow
			Invoke-WebRequest https://raw.githubusercontent.com/voidint/g/master/install.ps1 -useb | Invoke-Expression
		}
	}
	
	# 添加 scoop extras bucket
	if (Test-EXEProgram scoop) {
		try {
			scoop bucket add extras 2>$null
		}
		catch {
			# 忽略已存在的错误
		}
	}
	
	return $true
}

function Install-DevelopmentTools() {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[string]$ConfigPath = "$PSScriptRoot/apps-config.json"
	)
	
	# 初始化包管理器
	if (-not (Initialize-PackageManagers)) {
		return
	}
	
	# 安装各类应用
	if (Test-EXEProgram scoop) {
		Install-PackageManagerApps -PackageManager "scoop" -ConfigPath $ConfigPath
	}
	
	if (Test-EXEProgram choco) {
		Install-PackageManagerApps -PackageManager "choco" -ConfigPath $ConfigPath
	}
	
	if (Test-EXEProgram winget) {
		Install-PackageManagerApps -PackageManager "winget" -ConfigPath $ConfigPath
	}
	
	if (Test-EXEProgram cargo) {
		Install-PackageManagerApps -PackageManager "cargo" -ConfigPath $ConfigPath
	}
 else {
		Write-Host "Cargo 未安装，跳过 Rust 工具安装" -ForegroundColor Yellow
	}
	
	Write-Host "所有工具安装完成！" -ForegroundColor Green
}


function installApps() {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[string]$ConfigPath = "$PSScriptRoot/apps-config.json"
	)
	
	Install-DevelopmentTools -ConfigPath $ConfigPath
}


installApps
