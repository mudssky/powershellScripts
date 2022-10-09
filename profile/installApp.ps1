
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


<#
.Synopsis
	检测win10字体文件夹中是否存在字体
.DESCRIPTION
   详细描述
#>
function Test-Font() {
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
	$win10systemRoot = (Get-ChildItem Env:SystemRoot).Value
	$win10FontsPath = $win10systemRoot + '\Fonts'
	return ($null -ne ((Get-ChildItem $win10FontsPath -Filter "*$Name*")) )
}

# $PSDefaultParameterValues["Write-Host:ForegroundColor"] = "Green"


# cargo install hyperfine
# cargo install gping #带图的ping



$installListMap = @{
	choco  = @(
		'starship' # 跨平台终端提示符美化工具
		# 'twinkle-tray' 	# 一个调节屏幕亮度的软件，win10的亮度调节可太垃圾了。
		# 'eartrumpet' # 替代win10的音量调节
		'bat'
		#可以代替linux下的cat
		'fd'
		#搜索用的命令行工具
		'lsd'
		# 代替linux的ls命令
		'hexyl'
		# 终端查看16进制

		'ripgrep'
		#  文件搜索
	);
	scoop  = @(
		'go',
		'python',
		'aria2',
		'nvm',
		'git'
	)
	winget = @(
		'eartrumpet'
	)
	cargo  = @(
		# 可以用于在不同的工作空间中共享已经构建好的依赖包,提升构建速度
		'sccache'
		# linux sed命令行的rust实现，执行速度快2倍以上
		'sd'
		# 查看磁盘占用情况
		'dust'
		# 统计各种语言的代码行数
		'tokei'
		# 命令行跑分工具
		'hyperfine'
		# rust 版本的top，任务管理器
		'bottom'
		# rust版本tldr 太长不看帮助文档
		'tealdeer'
		# 根据用户输入生成正则表达式
		'grex'
		# 更智能的cd
		'zoxide'
		# 命令行任务管理工具，它可以管理你的长时间运行的命令，支持顺序或并行执行。简单来说，它可以管理一个命令队列。
		'pueue'
		# 监听到文件变动后执行命令
		'watchexec-cli'
		# 监听变动执行cargo操作，和watchexec是同一个开发者
		'cargo-watch'
		# 文件目录管理
		'broot'
	)
}
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
	if ( -not (Test-EXEProgram scoop)) {
		if ($PSCmdlet.ShouldProcess('是否安装', '未检测到scoop')) {
			Write-Host '由于scoop禁止管理员权限安装,请先在非管理员环境安装后,再继续执行
			执行下面的语句安装
			Invoke-WebRequest -useb get.scoop.sh | Invoke-Expression
			'
			return
		}
	}
	if ( -not (Test-EXEProgram choco)) {
		# Write-Host -ForegroundColor Green  '未安装choco，是否安装'
		if ($PSCmdlet.ShouldProcess('是否安装', '未检测到choco')) {
			[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
		}
	}
	if ( -not (Test-Font fira)) {
		if ($PSCmdlet.ShouldProcess('是否安装', '未检测到firacode')) {
			$win10systemRoot = (Get-ChildItem Env:SystemRoot).Value
			$win10FontsPath = $win10systemRoot + '\Fonts'
			Expand-Archive -Path './fonts/FiraCode Windows Compatible.zip' -DestinationPath $win10FontsPath
		}
	}

	chocoInstallApps -installList $installListMap.choco
	scoopInstallApps -installList $scoopInstallList.scoop

	if ( -not (Test-EXEProgram node)) {
		# Write-Host -ForegroundColor Green  '未安装choco，是否安装'
		if ($PSCmdlet.ShouldProcess('是否安装', '未检测到node')) {
			# 使用scoop 安装的nvm 安装node
			nvm install lts
		}
	}
	if ( -not (Test-EXEProgram sccache)) {
		Write-Host -ForegroundColor Yellow '请安装sccache,用于rust编译缓存,提升新安装包的编译速度,cargo install sccache,'
	}
}

installApps -Confirm