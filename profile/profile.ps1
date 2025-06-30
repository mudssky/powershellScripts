

[CmdletBinding()]
param(
	[switch]$loadProfile
)


. $PSScriptRoot/loadModule.ps1

function Init-Environment {
	<#
	.SYNOPSIS
		初始化PowerShell环境配置
	.DESCRIPTION
		初始化PowerShell环境配置，包括代理设置、编码配置、别名设置、工具初始化等。
		这个函数封装了所有对环境变量有影响的配置，便于重复调用。
	.PARAMETER ScriptRoot
		脚本根目录路径，默认为当前脚本所在目录
	.PARAMETER EnableProxy
		是否启用代理设置，默认根据enableProxy文件存在性决定
	.PARAMETER ProxyUrl
		代理服务器地址，默认为 http://127.0.0.1:7890
	.EXAMPLE
		Init-Environment
		使用默认配置初始化环境
	.EXAMPLE
		Init-Environment -EnableProxy $false
		初始化环境但不启用代理
	.EXAMPLE
		Init-Environment -ProxyUrl "http://127.0.0.1:8080"
		使用自定义代理地址初始化环境
	.NOTES
		此函数会影响当前PowerShell会话的环境变量和配置
	#>
	
	[CmdletBinding()]
	param (
		[string]$ScriptRoot = $PSScriptRoot,
		[bool]$EnableProxy = (Test-Path -Path "$PSScriptRoot\enableProxy"),
		[string]$ProxyUrl = "http://127.0.0.1:7890"
	)
	
	Write-Verbose "开始初始化PowerShell环境配置"
	
	# 设置代理环境变量
	if ($EnableProxy) {
		Write-Verbose "启用代理设置: $ProxyUrl"
		$Env:http_proxy = $ProxyUrl
		$Env:https_proxy = $ProxyUrl
		Write-Debug "已设置代理: $ProxyUrl" 
	}
 else {
		Write-Verbose "跳过代理设置"
	}
	
	# 加载自定义环境变量脚本
	if (Test-Path -Path "$ScriptRoot/env.ps1") {
		Write-Verbose "加载自定义环境变量脚本: $ScriptRoot/env.ps1"
		. "$ScriptRoot/env.ps1"
	}
	
	# 内部函数：添加Conda环境
	function Add-CondaEnv {
		$condaPath = "$env:USERPROFILE\anaconda3\shell\condabin\conda-hook.ps1"
		if (Test-Path -Path $condaPath) {
			Write-Verbose "加载Conda环境: $condaPath"
			. $condaPath 
		}
	}
	
	# 设置PowerShell别名
	Write-Verbose "设置PowerShell别名"
	Set-Alias -Name ise -Value powershell_ise -Scope Global
	Set-Alias -Name ipython -Value Start-Ipython -Scope Global
	
	# 设置控制台编码为UTF8
	Write-Verbose "设置控制台编码为UTF8"
	$Global:OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding
	$Global:PSDefaultParameterValues["Out-File:Encoding"] = "UTF8"
	
	# 导入PSReadLine模块
	Write-Verbose "导入PSReadLine模块"
	try {
		Import-Module PSReadLine -ErrorAction Stop
	}
 catch {
		Write-Warning "无法导入PSReadLine模块: $($_.Exception.Message)"
	}
	
	# 初始化开发工具
	Write-Verbose "初始化开发工具"
	$tools = @{
		starship = { 
			Write-Verbose "初始化Starship提示符"
			Invoke-Expression (&starship init powershell) 
		}
		sccache  = {
			Write-Verbose "设置sccache用于Rust编译缓存"
			$Global:Env:RUSTC_WRAPPER = 'sccache' 
		}
		zoxide   = { 
			Write-Verbose "初始化zoxide目录跳转工具"
			Invoke-Expression (& { (zoxide init powershell | Out-String) }) 
		}
		fnm      = { 
			Write-Verbose "初始化fnm Node.js版本管理器"
			fnm env --use-on-cd | Out-String | Invoke-Expression 
		}
	}
	
	foreach ($tool in $tools.GetEnumerator()) {
		if (Test-EXEProgram -Name $tool.Key) {
			try {
				& $tool.Value
				Write-Verbose "成功初始化工具: $($tool.Key)"
			}
			catch {
				Write-Warning "初始化工具 $($tool.Key) 时出错: $($_.Exception.Message)"
			}
		}
		else {
			if ($tool.Key -eq 'starship') {
				Write-Host -ForegroundColor Yellow '未安装starship（一款开源提示符美化工具），可以运行以下命令进行安装：
1. choco install starship
2. scoop install starship
3. winget install starship'
			}
			else {
				Write-Verbose "工具 $($tool.Key) 未安装，跳过初始化"
			}
		}
	}
	
	# 载入conda环境（如果环境变量中没有conda命令）
	if (-not (Test-EXEProgram -Name conda)) {
		Write-Verbose "尝试加载Conda环境"
		Add-CondaEnv
	}
	
	# Write-Host "PowerShell环境初始化完成" -ForegroundColor Green
	Write-Debug "PowerShell环境初始化完成" 
}

# 调用环境初始化函数
Init-Environment 

# 配置git,解决中文文件名不能正常显示的问题
# git config --global core.quotepath false

if ($loadProfile) {
	Set-Content -Path $profile  -Value  ". $PSCommandPath"
}