<#
.SYNOPSIS
	同步配置文件，在两个目录之间
.DESCRIPTION
	A longer description of the function, its purpose, common use cases, etc.
.NOTES
	Information or caveats about the function e.g. 'This function is not supported in Linux'
.LINK
	Specify a URI to a help page, this will show when Get-Help -Online is used.
.EXAMPLE
	Test-MyTestFunction -Verbose
	Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
#>


[CmdletBinding()]
param(
	[ValidateSet('backup', 'restore', 'list')]
	[string]$Mode = 'backup'
	# [string]$configDir = "$env:USERPROFILE/AppData/Local/Programs/PixPin/Config
)


# 这里我们用ps1作为配置文件目录的配置文件
# 这样方便用后缀名来过滤
if ( -not ( Test-Path   __sync.ps1)) {
	Write-Host '__sync.ps1 not found in current path'
	exit 1
}
# 导入变量
. ./__sync.ps1




switch ($Mode) {
	'backup' {
		Copy-Item -Recurse -Force $configDir/*  -Destination ./
	}
	'restore' {
		Copy-Item -Recurse -Force ./*  -Destination $configDir
	}
	'list' {
		Get-ChildItem $configDir
		Get-ChildItem ./
	}
}
