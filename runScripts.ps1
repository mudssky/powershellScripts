
<#
.SYNOPSIS
	像npm run scripts一样执行命令
.DESCRIPTION
	习惯于npm scripts，但是在go，rust中没有这么方便的执行指令，
	所以用powershell实现类似的效果。
	可以从任意json中读取scripts代码块。并执行对应的命令
.PARAMETER CommandName
执行命令的名字

.PARAMETER listCommands
列出所有可以执行的命令

.EXAMPLE
	# 执行指定命令
	runScripts -CommandName test
.EXAMPLE
	# 列出所有可执行的命令
	runScripts -listCommands
#>
[CmdletBinding()]
param(
	[string]$CommandName = 'invalid',
	[switch]$listCommands
)


$CommandMap = @{

}

$scriptsSearchList = @(
	'scripts.json'
	’package.json‘
)


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
		}
		else {

			& $map[$name]
		}
	}
	else {
		Write-Verbose  ('command{0} not found}-f $name')
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
				break
			}
		}
		else {
			Write-Verbose ('scripts path not found: {0}' -f $path)
		}
	}
	return $res
}


function set-scriptsMap {
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
		return
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

set-scriptsMap
if ($listCommands) {
	Write-Host -ForegroundColor Green '下面展示scripts字段中的命令:'
	Format-Table -InputObject $CommandMap -Property Name, Value 
	exit 0
}
RunScript($CommandName)

