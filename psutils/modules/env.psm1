

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
		# [Parameter(Mandatory = $true)]
		[string]$Path,	

		# Machine: 表示系统级环境变量。对所有用户和进程可见，需要管理员权限。
		# User: 表示用户级环境变量。对当前用户和所有该用户的进程可见。
		# Process: 表示进程级环境变量。仅对当前PowerShell进程可见。
		# 环境变量的类型
		[ValidateSet('Machine', 'User', 'Process')]
		[string]$EnvTarget = 'User'
	)

	$defaultEnvFileList = @('.env.local', '.env')
	if (-not( Test-Path -LiteralPath $Path)) {
		$foundDefaultFile = $false
		# 判断默认环境变量文件
		foreach ($defaultEnvFilePath in $defaultEnvFileList) {
			if (Test-Path -LiteralPath $defaultEnvFilePath) {
				$Path = $defaultEnvFilePath
				$foundDefaultFile = $true
				break
			}
		}
		
		if (-not $foundDefaultFile) {
			Write-Error "env文件不存在: $Path"
			return
		}

	
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



function Import-EnvPath {
	<#
	.SYNOPSIS
		重新加载环境变量中的path
		Process 进程级，当前会话生效
		User 用户级，当前用户生效
		Process 系统级，所有用户生效
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


function Set-EnvPath {
	<#
	.SYNOPSIS
		设置环境变量path,直接整个替换
	.DESCRIPTION
		设置环境变量path,直接整个替换，建议先做好备份
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
		[Parameter(Mandatory = $true)]
		[string]
		# 这里是Path的值
		$PathStr,
		[ValidateSet('Machine', 'User', 'Process')]
		[string]$EnvTarget = 'User'
	)
	
	begin {
		Write-Host 	"current env path:$env:Path"
	}
	
	process {
		[Environment]::SetEnvironmentVariable("Path", $PathStr, $EnvTarget)
	}
	
	end {
		# 导入环境变量
		Import-Envpath -EnvTarget User
	}
}


function Add-EnvPath {
	<#
	.SYNOPSIS
		设置环境变量path,增加一个新的path
	.DESCRIPTION
		设置环境变量path，支持user path和system path
	.NOTES
		Information or caveats about the function e.g. 'This function is not supported in Linux'
	.LINK
		Specify a URI to a help page, this will show when Get-Help -Online is used.
	.EXAMPLE
		Get-EnvParam -ParamName 'Path' -EnvTarget User
		获取当前用户的Path环境变量值

	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]
		$Path,
		[ValidateSet('Machine', 'User', 'Process')]
		[string]$EnvTarget = 'User'
	)
	
	begin {
		
	}
	
	process {
		$absPath = Resolve-Path $Path
		$newPath = $Env:Path + ";$absPath"

		Set-EnvPath -PathStr $newPath -EnvTarget $EnvTarget
	}
	
	end {
		# 导入环境变量
		Import-Envpath -EnvTarget User
	}
}

function Get-EnvParam {
	<#
	.SYNOPSIS
	获取环境变量中的参数，ParamName不指定时获取Path。可以指定EnvTarget 'Machine', 'User', 'Process
	.DESCRIPTION
		设置环境变量path，支持user path和system path
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
		[string]
		$ParamName = 'Path',
		[ValidateSet('Machine', 'User', 'Process')]
		[string]$EnvTarget = 'User'
	)
	
	begin {
		
		Write-Debug "current env path: $env:Path"
	}
	process {
		try {
			$value = [Environment]::GetEnvironmentVariable($ParamName, $EnvTarget)
			if ($value -eq $null) {
				Write-Warning "环境变量 $ParamName 未找到或未设置。"
			}
			return $value
		}
		catch {
			Write-Error "获取环境变量 $ParamName 时出错: $_"
		}
	}
	
}

function Remove-FromEnvPath {
	<#
	.SYNOPSIS
		从环境变量path移除一个path
	.DESCRIPTION
		设置环境变量path，支持user path和system path
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
		[Parameter(Mandatory = $true)]
		[string]
		$Path,
		[ValidateSet('Machine', 'User', 'Process')]
		[string]$EnvTarget = 'User'
	)
	
	begin {
		
	}
	
	process {
		$removePath = Resolve-Path $Path
		$pathList = $env:Path -split ';'
		Write-Host "remove path:$removePath"
		if ($pathList -contains $removePath) {
			$newPathList = $pathList | Where-Object { $_ -ne $removePath }
			$newPath = $newPathList -join ';'
			Set-EnvPath -PathStr $newPath -EnvTarget $EnvTarget
		}
		else {
			Write-Error "path not found in path env"
		}
	}
	
	end {
		# 导入环境变量
		Import-Envpath -EnvTarget User
	}
}

Export-ModuleMember -Function *