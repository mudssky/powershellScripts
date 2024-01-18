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


# 获取脚本文件的路径
# function Get-ScriptPath() {
# 当前脚本运行的路径
#  $PSScriptRoot
# 这个变量包含运行脚本模块的完全路径,包括文件名
# 所以会获取当前这个psm1文件的路径
# $PSCommandPath
# }




# 重新加载环境变量中的path，这样你在对应目录中新增一个exe就可以不用重启终端就能直接在终端运行了。
function Import-Envpath() {
	$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
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


function Start-Ipython () {
	python -m IPython
}

function Start-PSReadline() {
	# 安装
	Install-Module -Name PSReadLine -AllowClobber -Force
	# 开启基于历史记录的智能提示
	Set-PSReadLineOption -PredictionSource History
}



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



$internetSettingPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

function Start-Proxy() {
	param(
	
		[string]$URL = 'http://127.0.0.1:8080',
		[string]$username,
		[SecureString]$password
	)
	
	Set-ItemProperty -Path $internetSettingPath -Name ProxyServer -Value $URL
	if ($username -and $password) {
		Set-ItemProperty -Path $internetSettingPath -Name ProxyUser  -Value $username
		Set-ItemProperty -Path $internetSettingPath -Name ProxyPass  -Value $password
	}

	# 启用代理服务
	Set-ItemProperty -Path $internetSettingPath -Name ProxyEnable -Value 1
	# 重启windows代理自动检测服务，使其生效
	# Restart-Service -Name WinHttpAutoProxySvc
}

function Close-Proxy() {
	# 关闭代理服务
	Set-ItemProperty -Path $internetSettingPath -Name ProxyEnable -Value 0
}

# 检查上一条命令是否执行成功，如果上一条命令失败直接退出程序,退出码1
function checkErr([string]$commandName) {
	if (-not $?) {
		# 输出执行失败信息
		write-host -ForegroundColor Red  ('checkErr: {0} exctute failed' -f $commandName)
		throw('{0} error found' -f $commandName)
		exit 1
	}
	else {
		# 上条命令执行成功后输出消息
		write-host -ForegroundColor Green  ('checkErr: {0} exctute successful' -f $commandName)
	}
}

# 设置package.json的scripts字段
function Set-Scripts {
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

# 解析dotenv文件，返回键值对
function Get-Dotenv {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path	# env文件路径
	)
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
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path,	# env文件路径

		# Machine: 表示系统级环境变量。对所有用户和进程可见，需要管理员权限。
		# User: 表示用户级环境变量。对当前用户和所有该用户的进程可见。
		# Process: 表示进程级环境变量。仅对当前PowerShell进程可见。
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
function Get-NeedBinaryDigits($number) {
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


function Test-PathMust() {
	param (
		$path
	)
	if (-not (Test-Path $path)) {
		throw "the path $path is not exist"
	}

}


function Install-Font {  
	param  
	(  
		[System.IO.FileInfo]$fontFile  
	)  
      
	try { 

		#get font name
		$gt = [Windows.Media.GlyphTypeface]::new($fontFile.FullName)
		$family = $gt.Win32FamilyNames['en-us']
		if ($null -eq $family) { $family = $gt.Win32FamilyNames.Values.Item(0) }
		$face = $gt.Win32FaceNames['en-us']
		if ($null -eq $face) { $face = $gt.Win32FaceNames.Values.Item(0) }
		$fontName = ("$family $face").Trim() 
           
		switch ($fontFile.Extension) {  
			".ttf" { $fontName = "$fontName (TrueType)" }  
			".otf" { $fontName = "$fontName (OpenType)" }  
		}  

		write-host "Installing font: $fontFile with font name '$fontName'"

		If (!(Test-Path ("$($env:windir)\Fonts\" + $fontFile.Name))) {  
			write-host "Copying font: $fontFile"
			Copy-Item -Path $fontFile.FullName -Destination ("$($env:windir)\Fonts\" + $fontFile.Name) -Force 
		}
		else { write-host "Font already exists: $fontFile" }

		If (!(Get-ItemProperty -Name $fontName -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" -ErrorAction SilentlyContinue)) {  
			write-host "Registering font: $fontFile"
			New-ItemProperty -Name $fontName -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" -PropertyType string -Value $fontFile.Name -Force -ErrorAction SilentlyContinue | Out-Null  
		}
		else { write-host "Font already registered: $fontFile" }
           
		[System.Runtime.Interopservices.Marshal]::ReleaseComObject($oShell) | out-null 
		Remove-Variable oShell               
             
	}
 catch {            
		write-host "Error installing font: $fontFile. " $_.exception.message
	}
	
} 
 

function Uninstall-Font {  
	param  
	(  
		[System.IO.FileInfo]$fontFile  
	)  
      
	try { 

		#get font name
		$gt = [Windows.Media.GlyphTypeface]::new($fontFile.FullName)
		$family = $gt.Win32FamilyNames['en-us']
		if ($null -eq $family) { $family = $gt.Win32FamilyNames.Values.Item(0) }
		$face = $gt.Win32FaceNames['en-us']
		if ($null -eq $face) { $face = $gt.Win32FaceNames.Values.Item(0) }
		$fontName = ("$family $face").Trim()
           
		switch ($fontFile.Extension) {  
			".ttf" { $fontName = "$fontName (TrueType)" }  
			".otf" { $fontName = "$fontName (OpenType)" }  
		}  

		write-host "Uninstalling font: $fontFile with font name '$fontName'"

		If (Test-Path ("$($env:windir)\Fonts\" + $fontFile.Name)) {  
			write-host "Removing font: $fontFile"
			Remove-Item -Path "$($env:windir)\Fonts\$($fontFile.Name)" -Force 
		}
		else { write-host "Font does not exist: $fontFile" }

		If (Get-ItemProperty -Name $fontName -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" -ErrorAction SilentlyContinue) {  
			write-host "Unregistering font: $fontFile"
			Remove-ItemProperty -Name $fontName -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" -Force                      
		}
		else { write-host "Font not registered: $fontFile" }
           
		[System.Runtime.Interopservices.Marshal]::ReleaseComObject($oShell) | out-null 
		Remove-Variable oShell               
             
	}
 catch {            
		write-host "Error uninstalling font: $fontFile. " $_.exception.message
	}        
}  
  
$currentDirectory = [System.AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\') 
if ($currentDirectory -eq $PSHOME.TrimEnd('\')) {     
	$currentDirectory = $PSScriptRoot 
}

#Loop through fonts in the same directory as the script and install/uninstall them
foreach ($FontItem in (Get-ChildItem -Path $currentDirectory | 
		Where-Object { ($_.Name -like '*.ttf') -or ($_.Name -like '*.otf') })) {  
	Install-Font -fontFile $FontItem.FullName  
}  



Export-ModuleMember -Function *