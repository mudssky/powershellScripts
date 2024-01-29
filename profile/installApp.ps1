
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

[CmdletBinding(SupportsShouldProcess)]
param(
	# [switch]$Confirm
)

. $PSScriptRoot/loadModule.ps1

$installListMap = @{
	choco  = @(
		# 'twinkle-tray' 	# 一个调节屏幕亮度的软件，win10的亮度调节可太垃圾了。
		# 'eartrumpet' # 替代win10的音量调节
		'bat'
		#可以代替linux下的cat
		'fd'
		#搜索用的命令行工具
		'lsd'
		# 代替linux的ls命令

		# 命令行跑分工具
		'hyperfine'
	);
	scoop  = @(
		@{
			name    = 'nvm'
			cliName = 'nvm'
		},
		@{
			name = 'git'
		},	
		@{
			name       = 'gsudo'
			cliName    = 'nvm'
			desciption = 'win提权'
		},	
		@{
			name    = 'starship'
			cliName = 'starship'
		},	
		@{
			name    = 'ffmpeg'
			cliName = 'ffmpeg'
		},	
		@{
			name = 'fzf'
			# go编写的模糊查找神器
		},	
		@{
			name    = 'ripgrep'
			cliName = 'rg'
			# rust正则查找神奇rg
		},
		@{

			name = 'cht'
			# https://github.com/chubin/cheat.sh
		},	
		@{
			name    = 'aria2'
			cliName = 'aria2c'
		},	
		@{
			name = 'vhs'
		},
		@{
			name = 'duf'
			# 录制终端操作到gif
		},
		@{
			name = 'dust'
			#rust ，代替linux du
		}

		@{
			name = 'caddy'
			#golang的web服务器，类似nginx
		},
		@{
			name = 'jq' #命令行处理json
		}
		@{
			name = 'tokei' #rust git仓库代码统计
		}
		# 	@{
		# 	name    = 'lux' #下载器，但是感觉有yt-dlp就够了
	
		# }
	);
	winget = @(
		'eartrumpet'
	);
	cargo  = @(
		# 可以用于在不同的工作空间中共享已经构建好的依赖包,提升构建速度
		'sccache'
		# linux sed命令行的rust实现，执行速度快2倍以上
		'sd'
		# 查看磁盘占用情况
		'dust' 
		# 统计各种语言的代码行数
		'tokei'
		# git仓库统计信息
		# 'onefetch'
		# rust 版本的top，任务管理器bottom
		'btm'
		# rust版本tldr 太长不看帮助文档
		'tldr'
		# 根据用户输入生成正则表达式
		'grex'
		# 更智能的cd
		'zoxide'
		# 命令行任务管理工具，它可以管理你的长时间运行的命令，支持顺序或并行执行。简单来说，它可以管理一个命令队列。
		'pueue'
		# 监听到文件变动后执行命令
		'watchexec'
		# 监听变动执行cargo操作，和watchexec是同一个开发者
		'cargo-watch'
		# 文件目录管理
		'broot'
		# 终端查看16进制
		'hexyl'
		#  文件搜索
		# 'rg'
		# 统计代码行数
		'cloc'
		
	);
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
				choco install $appName -y
			}
		}
	}
}
function scoopInstallApps() {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[array]
		$installList
	)
	foreach ($appInfo in $installList) {
		$cliName = $appInfo.cliName  ? $appInfo.cliName : $appInfo.name 
		$appName = $appInfo.name
		echo "cliName: $cliName  , appName: $appName"
		if ( -not (Test-EXEProgram  $cliName)) {
			if ($PSCmdlet.ShouldProcess( '是否安装', "未检测到$appName")) {
				scoop install $appName 
			}
		}
 }

}


function cargoInstallApps() {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[array]
		$installList
	)

	$specialdict = @{
		'dust'      = @{
			# 'bin'='dust'
			'command' = 'cargo install du-dust';
		};
		'pueue'     = @{
			'command' = 'cargo install --locked pueue';
		};
		'tldr'      = @{
			'command' = 'cargo install  tealdeer';
		};
		'watchexec' = @{
			'command' = 'cargo install --locked watchexec-cli';
		};
		# 'rg'        = @{
		# 	'command' = 'cargo install  ripgrep';
		# };
		'btm'       = @{
			'command' = 'cargo install  bottom';
		};
	}

	foreach ($appName in $installList) {
		if ( -not (Test-EXEProgram $appName)) {
			if ($PSCmdlet.ShouldProcess( '是否安装', "未检测到$appName")) {
				if ($appName -in $specialdict.Keys) {
					Invoke-Expression $specialdict[$appName].command
				}
				else {				
					cargo install $appName 
				}
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
	if (-not (Test-EXEProgram g)) {
		# 运行g的安装脚本 ，属于go的版本管理器
	 Invoke-WebRequest https://raw.githubusercontent.com/voidint/g/master/install.ps1 -useb | Invoke-Expression
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
	# echo hello 
	chocoInstallApps -installList $installListMap.choco
	scoopInstallApps -installList $installListMap.scoop
	cargoInstallApps -installList $installListMap.cargo

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


installApps 
