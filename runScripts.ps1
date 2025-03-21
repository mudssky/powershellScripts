<#
.SYNOPSIS
    像npm run scripts一样执行命令
.DESCRIPTION
    习惯于npm scripts，但是在go，rust中没有这么方便的执行指令，
    所以用powershell实现类似的效果。
    可以从任意json中读取scripts代码块。并执行对应的命令

    支持以下功能：
    1. 执行scripts.json或package.json中定义的命令
    2. 支持pre/post钩子，如test命令会按pretest -> test -> posttest顺序执行
    3. 支持全局scripts配置
    4. 自动识别.nvmrc并切换Node.js版本

.PARAMETER CommandName
    执行命令的名字，必须在scripts配置中存在

.PARAMETER TemplateName
    初始化时使用的模板名称，可选值：golang, rust, nodejs
    默认值: golang

.PARAMETER listCommands
    列出所有可以执行的命令

.PARAMETER init
    初始化scripts.json配置文件

.PARAMETER autoSwitchNode
    根据.nvmrc文件自动切换Node.js版本

.PARAMETER enableGlobalScripts
    启用全局scripts配置，将会加载脚本所在目录的scripts.json

.EXAMPLE
    # 执行指定命令
    runScripts -CommandName test

.EXAMPLE
    # 列出所有可执行的命令
    runScripts -listCommands

.EXAMPLE
    # 初始化配置文件
    runScripts -init -TemplateName golang

.EXAMPLE
    # 启用全局配置并执行命令
    runScripts -CommandName build -enableGlobalScripts

.NOTES
	版本: 1.0.0
    配置文件搜索顺序：
    1. 当前目录的scripts.json
    2. 当前目录的package.json
    3. 全局scripts.json（需要启用enableGlobalScripts）
#>
[CmdletBinding()]
param(
	[ValidateNotNullOrEmpty()]
	[string]$CommandName = 'invalid',
	[ValidateSet('golang', 'rust', 'nodejs')]
	[string]$TemplateName = 'golang',
	[switch]$ListCommands,
	# 初始化脚本文件
	[switch]$Init,
	# 根据nvmrc切换node版本
	[switch]$AutoSwitchNode,
	[switch]$EnableGlobalScripts

)

trap { 
	Write-Host -ForegroundColor Red "执行过程中发生错误: $_" 
	Write-Host -ForegroundColor Red $_.ScriptStackTrace
	exit 1
}

$CommandMap = @{

}

$scriptsSearchList = @(
	'scripts.json'
	'package.json'
) + ( $EnableGlobalScripts ?
	@("$PSScriptRoot/scripts.json"): @())
# 把本目录的脚本地址放最后
$currentScriptsPath = 'scripts.json'

function RunIfExist {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $True)]
		[hashtable]
		$map ,
		[Parameter(Mandatory = $True)]
		[string]
		$name
	)
	if ($map.ContainsKey($name)) {
		if ($map[$name] -is [string]) {
			Invoke-Expression $map[$name]
			Write-Verbose ('excuted {0} ' -f $map[$name])
		}
		else {

			& $map[$name]
		}
	}
	else {
		Write-Verbose  ('command {0} not found' -f $name)
	}
}

function find-scripts {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $True)]
		[string[]]
		$PathList
	)
	$res = $null
	foreach ($path in $PathList) {
		if (Test-Path $path) {
			$scriptsMap = (Get-Content $path  | ConvertFrom-Json -AsHashtable).scripts
			if ($scriptsMap) {
				$res = $scriptsMap
				$script:currentScriptsPath = $path
				break
			}
		}
		else {
			Write-Verbose ('scripts path not found: {0}' -f $path)
		}
	}
	return $res
}


function switch-node {
	# 检查nvm是否存在
	if (-not (Test-EXEProgram 'nvm')) {
		throw 'nvm not found,switch node error'
	}
	if (Test-Path  '.nvmrc') {
		$nvmrcVersion = Get-Content  '.nvmrc'
		$pattern = [regex]"v?\d+\.\d+\.\d+"
		if ( -not $pattern.IsMatch($nvmrcVersion)) {
			throw 'nvmrc not match version pattern'
		}

		$currentNodeVersion = (node --version)
		Write-Verbose ('current node version is {0},nvmrc is {1}' -f $currentNodeVersion, $nvmrcVersion)
		if ( $currentNodeVersion -match $nvmrcVersion) {
			Write-Verbose 'node version is already match nvmrc,skip switch node'
			#粗略判断一下 node版本已经是当前版本
			return
		}
		nvm use $nvmrcVersion
	}
	else {
		Write-Warning 'not found nvmrc ,skip swicth node'
	}

}



function loadScriptsMap {
	param()
	# 判断读取scripts配置的位置
	if ($CommandMap.Count -eq 0) {
		$scripts	= find-scripts -PathList $scriptsSearchList
		if ( $null -eq $scripts) {
			$scriptsPath = $scriptsSearchList -join ','
		 throw ("找不到scripts脚本相关配置，请在当前目录下的以下文件：{0} 中添加sripts字段" -f $scriptsPath)
		}
		$script:CommandMap = $scripts
	}
}
function RunScript($name) {

	# 排除命令不存在的情况
	if ( -not  $CommandMap.ContainsKey($name) ) {
		$supportCommands = $CommandMap.Keys -join ","
		throw  ("该命令未找到:{0},  当前支持以下命令: {1}" -f $name, $supportCommands )
	}
	# 前置后置脚本直接执行
	if ($name -match "^(pre|post)") {
		RunIfExist -map $CommandMap -name $name
	}
	else {
		# 执行其他脚本时先检查有没有前置，后置脚本，分别执行
		RunIfExist -map $CommandMap  -name "pre$name"
		RunIfExist -map $CommandMap -name $name
		RunIfExist -map $CommandMap -name "post$name"
	}
}

# init在读取配置之前执行
if ($Init) {
	if (Test-Path $scriptsSearchList[0]) {
		Write-Host -ForegroundColor Green 'scripts.json已存在'
	}
	else {
		$templateFullName = "$TemplateName.scripts.json"
		$templatePath = "$PSScriptRoot/templates/$templateFullName"
		if (-not (Test-Path $templatePath)) {
			throw ('模板文件不存在:{0}' -f $templatePath)
		}
		Copy-Item $templatePath $scriptsSearchList[0]
		Write-Host -ForegroundColor Green 'scripts.json已创建'
	}
	exit 0
}
loadScriptsMap
if ($ListCommands) {
	Write-Host -ForegroundColor Green '下面展示scripts字段中的命令:'
	# Format-Table -InputObject $CommandMap -Property Name, Value 
	$CommandMap.GetEnumerator() | Sort-Object Name | Format-Table -AutoSize | Out-Host -Paging
	exit 0
}
if ($AutoSwitchNode) {
	switch-node
	exit 0
}

# 兼容npm，如果有package.json，直接使用npm
if ($currentScriptsPath -eq 'package.json') {
	switch-node
	npm run $CommandName
	exit 0
}
RunScript($CommandName)

