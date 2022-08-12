
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
	# get-command  return $null  when cant find command and  SilentlyContinue flag on 
	return ($null -ne (Get-Command -Name $Name  -CommandType Application  -ErrorAction SilentlyContinue ))
}

# $PSDefaultParameterValues["Write-Host:ForegroundColor"] = "Green"

$chocoInstallList = @(
	'starship'
)

$scoopInstallList = @(
	'go',
	'python',
	'aria2',
	'nvm'
)

function chocoInstallApps() {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[string[]]
		$installList
	)
	foreach ($appName in $installList) {
		if ( -not (Test-EXEProgram $appName)) {
			if ($PSCmdlet.ShouldProcess( '是否安装', "未检测到$appName")) {
				choco install $appName
			}
		}
	}
}
function scoopInstallApps() {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[string[]]
		$installList
	)
	foreach ($appName in $installList) {
		if ( -not (Test-EXEProgram $appName)) {
			if ($PSCmdlet.ShouldProcess( '是否安装', "未检测到$appName")) {
				scoop install $appName 
			}
		}
	}
}
function installApps() {
	[CmdletBinding(SupportsShouldProcess)]
	param()
	if ( -not (Test-EXEProgram choco)) {
		# Write-Host -ForegroundColor Green  '未安装choco，是否安装'
		if ($PSCmdlet.ShouldProcess('是否安装', '未检测到choco')) {
			[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
		}
	}

	if ( -not (Test-EXEProgram scoop)) {
		# Write-Host -ForegroundColor Green  '未安装choco，是否安装'
		if ($PSCmdlet.ShouldProcess('是否安装', '未检测到scoop')) {
			Invoke-WebRequest -useb get.scoop.sh | Invoke-Expression
		}
	}
	chocoInstallApps -installList $chocoInstallList
	scoopInstallApps -installList $scoopInstallList

	if ( -not (Test-EXEProgram node)) {
		# Write-Host -ForegroundColor Green  '未安装choco，是否安装'
		if ($PSCmdlet.ShouldProcess('是否安装', '未检测到node')) {
			# 使用scoop 安装的nvm 安装node
			nvm install lts
		}
	}
	
}

installApps -Confirm