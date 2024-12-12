

function Get-HistoryCommandRank([int]$top = 10) {
 $count = 0; Get-Content  $env:USERPROFILE\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt | 
 ForEach-Object { ($_ -split ' ')[0]; $count += 1 } | 
 Group-Object | Sort-Object -Property Count  -Descending  -Top $top |
	Format-Table -Property Name, Count, @{Label = "Percentage"; Expression = { '{0:p2}' -f ($_.Count / $count) } } -AutoSize
}

# 获取脚本执行目录
function Get-ScriptFolder() {
	$currentScriptPath = $MyInvocation.MyCommand.Definition
	$currentScriptFolder = Split-Path  -Parent   $currentScriptPath 
	return $currentScriptFolder
}




function Start-Ipython () {
	python -m IPython
}

function Start-PSReadline() {
	# 安装
	Install-Module -Name PSReadLine -AllowClobber -Force
	# 开启基于历史记录的智能提示
	Set-PSReadLineOption -PredictionSource History
}






function New-Shortcut {
	[CmdletBinding()]
	param (
		# 需要创建快捷方式的目标路径
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Path,
		[Parameter(Mandatory = $true, Position = 1)]
		[string]$Destination 
	)
	
	begin {
	
	}
	
	process {
		$shell = New-Object -ComObject "WScript.Shell"
		$link = $shell.CreateShortcut($Destination)
		$link.TargetPath = $Path
		$link.Save()
	}
	
	end {
		
	}
}


# 设置package.json的scripts字段
function Set-Script {
	[CmdletBinding()]
	param (
		[string]$key , # 脚本名
		[string]$value,
		[string]$path # package.json路径
	)
	
	$jsonMap = Get-Content $path | ConvertFrom-Json -AsHashtable
	if ($jsonMap.scripts.ContainsKey($key)) {
		$jsonMap.scripts.$key = $value
	}
	else {
		$jsonMap.scripts.Add($key, $value)
	}
	ConvertTo-Json $jsonMap -Depth 100 | Out-File $path

}

# 更新semver字符串
function Update-Semver {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Version,	# 版本字符串
		[ValidateSet('major', 'minor', 'patch')]
		[string]$UpdateType = 'patch'     
	)
	$regexPattern = "^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$"
	$regexResult = $Version -match $regexPattern
	if (-not $regexResult) {
		Write-Error "无法解析SemVer版本字符串"
		return 
	}
	# 从正则表达式匹配结果中获取版本号各部分
	$majorVersion = [int]$matches["major"]
	$minorVersion = [int]$matches["minor"]
	$patchVersion = [int]$matches["patch"]
	switch ($UpdateType) {
		'major' {
			$majorVersion++
		}
		'minor' {
			$minorVersion++
		}
		'patch' {
			$patchVersion++
		}
	}
	$newVersion = "$($majorVersion).$($minorVersion).$($patchVersion)"
	return $newVersion
}



##############################################################################
#.SYNOPSIS
# get a formated length of file , 当数值超过1024会采用更大的单位，直到GB
#
#.DESCRIPTION
# 获得格式化的文件大小字符串
#
#.PARAMETER TypeName
# 数值类型
#
#.PARAMETER ComObject
# 
#
#.PARAMETER Force
# 
#
#.EXAMPLE
#  
##############################################################################
function Get-FormatLength($length) {
	if ($length -gt 1gb) {
		return  "$( "{0:f2}" -f  $length/1gb)GB"
	}
	elseif ($length -gt 1mb) {
		return  "$( "{0:f2}" -f  $length/1mb)MB"
	}
	elseif ($length -gt 1kb) {
		return  "$( "{0:f2}" -f  $length/1kb)KB"
	}
	else {
		return "$length B"
	}    
}



##############################################################################
#.SYNOPSIS
# get needed digits to represent a decimal number
#
#.DESCRIPTION
# 获得一个数字需要多少二进制位来表示
#
#.PARAMETER number
#输入的数字
#
#.EXAMPLE
#  
##############################################################################
function Get-NeedBinaryDigit($number) {
	# 由于powershell中最大的数字就是int64,2左移62位的时候就溢出了，所以最大比较到2左移61位。也就是2的62次方，2的63次方就会溢出int64
	# int64 有64位，其中一位是符号位， 所以表达的最大数就是 2的63次方-1（最高位下标是63）
	if ($number -gt ([int64]::MaxValue)) {
		Write-Host -ForegroundColor Red "the number is exceed the area of int64"
	}
	else {
		for ($i = 62; $i -gt 0; $i -= 1) {
			if ( ([int64](1) -shl $i) -lt $number) {
				return ($i + 1)
			}
		}
	}
}

<#
.SYNOPSIS
    获取一个和输入哈希表key和value调换位置的哈希表
.DESCRIPTION
    Long description
.EXAMPLE
    PS C:\> Get-ReversedMap -inputMap $xxxMap
    Explanation of what the example does
.INPUTS
    Inputs (if any)
.OUTPUTS
    Output (if any)
.NOTES
    General notes
#>
function Get-ReversedMap() {
	param (
		$inputMap
	)
	$reversedMap = @{}
	foreach ($key in $inputMap.Keys) {
		$reversedMap[$inputMap[$key]] = $key
	}
	return $reversedMap
}


Export-ModuleMember -Function *