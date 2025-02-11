

<#
.Synopsis
	判断环境变量中是否存在可执行程序
.DESCRIPTION
   详细描述
.EXAMPLE
   如何使用此 cmdlet 的示例
.EXAMPLE
   另一个如何使用此 cmdlet 的示例
.INPUTS
   到此 cmdlet 的输入(如果有)
.OUTPUTS
   来自此 cmdlet 的输出(如果有)
.NOTES
   一般注释
.COMPONENT
   此 cmdlet 所属的组件
.ROLE
   此 cmdlet 所属的角色
.FUNCTIONALITY
   最准确描述此 cmdlet 的功能
#>
function Test-EXEProgram() {
	Param
	(	
		[Parameter(Mandatory = $true, 
		 ValueFromPipeline = $true,
		 Position = 0 )]
		[ValidateNotNull()]
		[ValidateNotNullOrEmpty()]
		[string]
		$Name
	)
	process {
		# get-command  return $null  when cant find command and  SilentlyContinue flag on 
		return ($null -ne (Get-Command -Name $Name  -CommandType Application  -ErrorAction SilentlyContinue ))
	}

}


# 判断数组是否为非空
function Test-ArrayNotNull() {
	param(
		$array
	)
	if ( $null -ne $array -and @($array).count -gt 0 ) {
		return $True
	}
	return $False
}

function Test-PathMust() {
	param (
		$Path
	)
	if (-not (Test-Path $Path)) {
		throw "the path $Path is not exist"
	}
}

function Test-PathHasExe {
	<#
	.SYNOPSIS
		判断路径中是否含有exe，或者可执行脚本ps1等。如果路径不存在也返回false
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
	
	
	param(
		[string]
		$Path = '.'
	)
	
	


	# 1. 检查路径是否存在
	if ( -not (Test-Path -Path $Path)) {
		Write-Debug "the path $Path is not exist"
		return $false
	}
	# 2. 检查路径是否是目录
	# 可以用Test-Path指定PathType来判断，Container是目录
	# Test-Path $Path -PathType Leaf
	$item = Get-Item $Path

	if ($item.PSIsContainer) {
		# 目录的情况
		# 遍历单层文件判断是否有可执行文件
		Get-ChildItem $Path -File -ErrorAction SilentlyContinue | where-object { $_.Extension -in '.exe', '.cmd', '.bat', '.ps1' } | ForEach-Object {
			Write-Debug "the path $Path has exe file $($_.FullName)"
			return $true
		}
		Write-Debug "the path $Path has no exe file"
		return $false
	}
 else {
		#   非目录的情况，只需判断路径是否是.exe结尾
		Write-Debug "the path $Path is not a directory"
		return $item.Extension -eq '.exe'

	}

  	

}
Export-ModuleMember -Function *