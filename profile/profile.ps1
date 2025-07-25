
[CmdletBinding()]
param(
	[switch]$loadProfile,
	# 别名前缀，用于区分自己定义的别名
	[string]$AliasDespPrefix = '[mudssky]'
)
$profileLoadStartTime = Get-Date

# 加载自定义模块 (例如包含 Test-EXEProgram 的文件)
. $PSScriptRoot/loadModule.ps1

# 加载自定义函数包装
. $PSScriptRoot/wrapper.ps1

# 初次使用时，执行loadProfile覆盖本地profile
if ($loadProfile) {
	# 备份逻辑，执行覆盖时备份，防止数据丢失
	if (Test-Path -Path $profile) {
		# 备份文件名添加时间戳，支持多次备份
		$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
		$backupPath = "$profile.$timestamp.bak"
		Write-Warning "发现现有的profile文件，备份为 $backupPath"
		Copy-Item -Path $profile -Destination $backupPath -Force
	}
	Set-Content -Path $profile  -Value  ". $PSCommandPath"
	return 
}
# 自定义别名配置
$userAlias = @(
	[PSCustomObject]@{
		cliName     = 'dust'
		aliasName   = 'du'
		aliasValue  = 'dust'
		description = 'dust 是一个用于清理磁盘空间的命令行工具。它可以扫描指定目录并显示占用空间较大的文件和目录，以便用户确定是否删除它们。'
	}
	[PSCustomObject]@{
		cliName     = 'duf'
		aliasName   = 'df'
		aliasValue  = 'duf'
		description = 'df 是 du 的别名，用于显示目录内容。'
	}
	[PSCustomObject]@{
		cliName     = 'zoxide'
		aliasName   = 'zq'
		aliasValue  = ''
		description = 'zoxide query 用于查询zoxide的数据库，显示最近访问的目录。'
		command     = 'zoxide query'

	}
	[PSCustomObject]@{
		cliName     = 'zoxide'
		aliasName   = 'za'
		aliasValue  = ''
		description = 'zoxide add 用于将当前目录添加到zoxide的数据库中，以便下次快速访问。'
		command     = 'zoxide add'
	}
	[PSCustomObject]@{
		cliName     = 'zoxide'
		aliasName   = 'zr'
		aliasValue  = 'zoxide'
		description = '如果你不希望某个目录再出现在 zoxide 的候选项中'
		command     = 'zoxide remove'

	}
	# scoop下载下来就是btm，不用设置别名
	# [PSCustomObject]@{
	# 	cliName     = 'bottom'
	# 	aliasName   = 'btm'
	# 	aliasValue  = 'bottom'
	# 	description = 'bottom 是一个用于显示系统资源使用情况的命令行工具。它可以实时显示CPU、内存、磁盘和网络等系统资源的使用情况，帮助用户监控系统性能。'
	# }
)


<#
.SYNOPSIS
    显示当前 Profile 加载的自定义别名、函数和关键环境变量。
#>
function Show-MyProfileHelp {
	[CmdletBinding()]
	param(

	)
	Write-Host "--- PowerShell Profile 帮助 ---" -ForegroundColor Cyan

	# 1. 显示自定义别名
	Write-Host "`n[自定义别名]" -ForegroundColor Yellow
	Get-CustomAlias -AliasDespPrefix $AliasDespPrefix | Format-Table -AutoSize

	# 1.5 函数别名
	Write-Host "`n[自定义函数别名]" -ForegroundColor Yellow
	$userAlias | Where-Object { $_.PSObject.Properties.Name -contains 'command' } | Select-Object @{N = '函数名'; E = 'aliasName' }, @{N = '底层命令'; E = 'command' }, @{N = '描述'; E = 'description' } | Format-Table -AutoSize
	
	# 2. 显示自定义函数包装
	# 动态获取自定义函数包装配置
	$customFunctionWrappers = Get-CustomFunctionWrapperInfos
	Write-Host "`n[自定义函数包装]" -ForegroundColor Yellow
	if ($customFunctionWrappers -and $customFunctionWrappers.Count -gt 0) {
		$customFunctionWrappers | Select-Object @{
			N = '函数名'; E = 'functionName'
		}, @{
			N = '描述'; E = 'description'
		} | Format-Table -AutoSize
	}
 else {
		Write-Host "  暂无自定义函数包装" -ForegroundColor Gray
	}
	
	# 3. 显示此 Profile 文件中定义的核心函数
	Write-Host "`n[核心管理函数]" -ForegroundColor Yellow
	# 假设你的自定义函数都在一个模块里，或者你可以用其他方式过滤
	# 这里我们简单地列出几个关键函数
	"Initialize-Environment", "Show-MyProfileHelp", "Add-CondaEnv" | ForEach-Object { 
		try {
			Get-Command $_ -ErrorAction Stop
		}
		catch {
			# 忽略不存在的函数
		}
	} | Format-Table Name, CommandType, Source -AutoSize

	# 4. 显示关键环境变量  
	Write-Host "`n[关键环境变量]" -ForegroundColor Yellow
	$envVars = @(
		'POWERSHELL_SCRIPTS_ROOT',
		'http_proxy',
		'https_proxy',
		'RUSTC_WRAPPER',
		'YAZI_FILE_ONE'
	)
	foreach ($var in $envVars) {
		if ($value = Get-Variable "env:$var" -ErrorAction SilentlyContinue) {
			Write-Host ("{0,-25} : {1}" -f $var, $value.Value)
		}
	}

	Write-Host "`n要重新加载环境, 请运行: Initialize-Environment" -ForegroundColor Green
}


function Set-AliasProfile {
	[CmdletBinding()]
	param (
		[PSCustomObject]$userAlias = $userAlias
	)
	begin {
	}
	
	process {
		# 设置PowerShell别名
		Write-Verbose "设置PowerShell别名"
		Set-CustomAlias -Name ise -Value powershell_ise  -AliasDespPrefix $AliasDespPrefix -Scope Global
		Set-CustomAlias -Name ipython -Value Start-Ipython  -AliasDespPrefix $AliasDespPrefix  -Scope Global
		foreach ($alias in $userAlias) {
			if ($alias.command) {
				Write-Verbose "别名 $($alias.aliasName) 已设置函数，执行函数创建"
				$scriptBlock = [scriptblock]::Create("$($alias.command) `$args")
				New-Item -Path "Function:Global:$($alias.aliasName)" -Value $scriptBlock -Force  | Out-Null
				Write-Verbose "已创建函数: $($alias.name)"
				continue
			}
			# 设置别名时，PowerShell 不需要目标命令当前就存在。它只在你使用该别名时才会去解析命令。因此，可以安全地移除所有 Test-ExeProgram 检查。
			# if (Test-ExeProgram -Name $alias.cliName) {
			Set-CustomAlias -Name $alias.aliasName -Value $alias.aliasValue -Description $alias.description -AliasDespPrefix $AliasDespPrefix -Scope Global
			Write-Verbose "已设置别名: $($alias.aliasName) -> $($alias.aliasValue)"
		}
		# else {
		# 	Write-Warning "未找到 $($alias.cliName) 命令，无法设置别名: $($alias.aliasName)"
		# }
	
	}
	
	end {
		
	}
}

function Initialize-Environment {
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
		Initialize-Environment
		使用默认配置初始化环境
	.EXAMPLE
		Initialize-Environment -EnableProxy $false
		初始化环境但不启用代理
	.EXAMPLE
		Initialize-Environment -ProxyUrl "http://127.0.0.1:8080"
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
	# 设置项目根目录环境变量
	$Global:Env:POWERSHELL_SCRIPTS_ROOT = $PSScriptRoot | Split-Path
	if ($EnableProxy) {
		Write-Verbose "启用代理设置: $ProxyUrl"
		$Global:Env:http_proxy = $ProxyUrl
		$Global:Env:https_proxy = $ProxyUrl
		Write-Debug "已设置代理: $ProxyUrl" 
	}
 else {
		Write-Verbose "跳过代理设置"
	}
	
	# 加载自定义环境变量脚本 (用于存放机密或个人配置)
	if (Test-Path -Path "$ScriptRoot/env.ps1") {
		Write-Verbose "加载自定义环境变量脚本: $ScriptRoot/env.ps1"
		. "$ScriptRoot/env.ps1"
	}
	
	# 设置控制台编码为UTF8
	Write-Verbose "设置控制台编码为UTF8"
	$Global:OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding
	$Global:PSDefaultParameterValues["Out-File:Encoding"] = "UTF8"
	
	# 导入PSReadLine模块
	# pwsh 7.x版本以上是自动启用了，所以也不用导入
	# 	Write-Verbose "导入PSReadLine模块"
	# 	try {
	# 		Import-Module PSReadLine -ErrorAction Stop
	# 	}
	#  catch {
	# 		Write-Warning "无法导入PSReadLine模块: $($_.Exception.Message)"
	# 	}
	
	# 初始化开发工具
	Write-Verbose "初始化开发工具"
	$tools = @{
		starship = { 
			Write-Verbose "初始化Starship提示符"
			$starshipInit = Invoke-WithCache -Key "starship-init-powershell" -MaxAge ([TimeSpan]::FromDays(30)) -ScriptBlock { &starship init powershell }
			Invoke-Expression $starshipInit
		}
		sccache  = {
			Write-Verbose "设置sccache用于Rust编译缓存"
			$Global:Env:RUSTC_WRAPPER = 'sccache' 
		}
		zoxide   = { 
			Write-Verbose "初始化zoxide目录跳转工具"
			$zoxideInit = Invoke-WithCache -Key "zoxide-init-powershell"  -MaxAge ([TimeSpan]::FromDays(30)) -ScriptBlock { zoxide init powershell | Out-String }
			Invoke-Expression $zoxideInit
		}
		# 在windows上使用比nvm麻烦很多，，所以不用了
		# 这个环境变量还需要在husky的git bash，npm使用的cmd里配置
		# fnm      = { 
		# 	Write-Verbose "初始化fnm Node.js版本管理器"
		# 	fnm env --use-on-cd | Out-String | Invoke-Expression 
		# }
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
	
	Set-AliasProfile
	# 载入conda环境（如果环境变量中没有conda命令）
	# if (-not (Test-EXEProgram -Name conda)) {
	# 	Write-Verbose "尝试加载Conda环境"
	# 	Add-CondaEnv
	# }
	
	# Write-Host "PowerShell环境初始化完成" -ForegroundColor Green
	Write-Debug "PowerShell环境初始化完成" 
}



# 调用环境初始化函数
Initialize-Environment 

# 配置git,解决中文文件名不能正常显示的问题
# git config --global core.quotepath false

$profileLoadEndTime = Get-Date
$profileLoadTime = ($profileLoadEndTime - $profileLoadStartTime).TotalMilliseconds
Write-Host "Profile 加载耗时: $($profileLoadTime) 毫秒" -ForegroundColor Green

