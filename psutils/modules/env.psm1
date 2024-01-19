

function Get-Dotenv {
	<#
	.SYNOPSIS
		解析dotenv内容为键值对保存到map中
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
	param (
		# dotenv文件路径
		[Parameter(Mandatory = $true)]
		[string]$Path		)
	$content = Get-Content $Path
	$pairs = @{}
	foreach ($line in $content) {
		if ($line -match '^\s*([^=]+)=(.*)') {
			$key = $Matches[1].Trim()
			$value = $Matches[2].Trim()
			$pairs[$key] = $value
		}
	}
	return $pairs
}




# 载入.env格式文件到环境变量
function Install-Dotenv {
	<#
	.SYNOPSIS
		加载dotenv文件到环境变量
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
	param (
		# dotenv文件路径
		[Parameter(Mandatory = $true)]
		[string]$Path,	

		# Machine: 表示系统级环境变量。对所有用户和进程可见，需要管理员权限。
		# User: 表示用户级环境变量。对当前用户和所有该用户的进程可见。
		# Process: 表示进程级环境变量。仅对当前PowerShell进程可见。
		# 环境变量的类型
		[ValidateSet('Machine', 'User', 'Process')]
		[string]$EnvTarget = 'User'
	)
	if (-not( Test-Path -LiteralPath $Path)) {
		Write-Error "env文件不存在: $Path"
	}
	$envTargetMap = @{
		'Machine' = [System.EnvironmentVariableTarget]::Machine
		'User'    = [System.EnvironmentVariableTarget]::User
		'Process' = [System.EnvironmentVariableTarget]::Process
	}
	$envPairs = Get-Dotenv -Path $Path
	
	foreach ($pair in $envPairs.GetEnumerator()) {
		$target = $envTargetMap[$EnvTarget]
		[System.Environment]::SetEnvironmentVariable($pair.key, $pair.value, $target)
		Write-Verbose "set env $($pair.key) = $($pair.value) to $EnvTarget"
	}	
}



function Import-Envpath {
	<#
	.SYNOPSIS
		重新加载环境变量中的path
	.DESCRIPTION
		重新加载环境变量中的path，这样你在对应目录中新增一个exe就可以不用重启终端就能直接在终端运行了。
	.NOTES
		Information or caveats about the function e.g. 'This function is not supported in Linux'
	.LINK
		Specify a URI to a help page, this will show when Get-Help -Online is used.
	.EXAMPLE
		Test-MyTestFunction -Verbose
		Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines

	#>

	[CmdletBinding()]
	param (
		[ValidateSet('Machine', 'User', 'Process')]
		[string]$EnvTarget = 'User'
	)	

	$env:Path = [System.Environment]::GetEnvironmentVariable("Path", $EnvTarget)
}


Export-ModuleMember -Function *