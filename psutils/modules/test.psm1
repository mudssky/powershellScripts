

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

Export-ModuleMember -Function *