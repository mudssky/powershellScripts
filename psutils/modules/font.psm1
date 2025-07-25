<#
.SYNOPSIS
	检查系统是否安装了指定的字体
.DESCRIPTION
	此函数用于检查Windows系统中是否安装了名称匹配的字体。它通过查找系统字体目录中的字体文件来判断。
.PARAMETER Name
	要检查的字体名称或部分名称。
.OUTPUTS
	System.Boolean
	如果找到匹配的字体，则返回 True；否则返回 False。
.EXAMPLE
	Test-Font -Name "Cascadia Code"
	检查是否安装了 "Cascadia Code" 字体。
.EXAMPLE
	if (Test-Font -Name "MyCustomFont") {
		Write-Host "字体已安装"
	}
.NOTES
	作者: PowerShell Scripts
	版本: 1.0.0
	创建日期: 2025-01-07
	用途: 用于在脚本中判断特定字体是否已安装。
	此函数目前仅支持 Windows 操作系统。
#>


function Test-Font {
	[CmdletBinding()]
	
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
	begin {
		$win10systemRoot = (Get-ChildItem Env:SystemRoot).Value
		$win10FontsPath = $win10systemRoot + '\Fonts'
	}
	
	process {
		return ($null -ne ((Get-ChildItem $win10FontsPath -Filter "*$Name*")) )
	}
	
}


<#
.SYNOPSIS
    安装字体文件到系统

.DESCRIPTION
    将指定的字体文件（TTF或OTF格式）安装到Windows系统中。
    函数会自动提取字体名称，复制字体文件到系统字体目录，并在注册表中注册字体。

.PARAMETER fontFile
    要安装的字体文件，支持.ttf和.otf格式

.OUTPUTS
    无返回值，直接安装字体到系统

.EXAMPLE
    Install-Font -fontFile (Get-Item "C:\Fonts\MyFont.ttf")
    安装指定的TTF字体文件

.EXAMPLE
    Get-ChildItem "C:\Fonts\*.ttf" | ForEach-Object { Install-Font -fontFile $_ }
    批量安装目录中的所有TTF字体文件

.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    权限要求: 需要管理员权限来复制文件到系统目录和修改注册表
    支持格式: .ttf (TrueType), .otf (OpenType)
#>
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
 

<#
.SYNOPSIS
    从系统卸载字体文件

.DESCRIPTION
    从Windows系统中卸载指定的字体文件。
    函数会自动提取字体名称，从系统字体目录删除字体文件，并从注册表中移除字体注册信息。

.PARAMETER fontFile
    要卸载的字体文件，支持.ttf和.otf格式

.OUTPUTS
    无返回值，直接从系统卸载字体

.EXAMPLE
    Uninstall-Font -fontFile (Get-Item "C:\Windows\Fonts\MyFont.ttf")
    卸载指定的TTF字体文件

.EXAMPLE
    Get-ChildItem "C:\Windows\Fonts\Custom*.ttf" | ForEach-Object { Uninstall-Font -fontFile $_ }
    批量卸载系统中匹配模式的字体文件

.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    权限要求: 需要管理员权限来删除系统目录文件和修改注册表
    支持格式: .ttf (TrueType), .otf (OpenType)
#>
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
  

Export-ModuleMember -Function Test-Font, Install-Font, Uninstall-Font