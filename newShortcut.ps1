function New-Shortcut {
	<#
    .SYNOPSIS
        Creates a new Windows shortcut.

    .DESCRIPTION
        The New-Shortcut cmdlet creates a new Windows shortcut with the specified properties.

    .EXAMPLE
        PS C:\> New-Shortcut -TargetPath 'C:\Program Files\MyProgram\MyProgram.exe' -ShortcutPath 'C:\Users\UserName\Desktop\MyProgram.lnk' -Arguments '-option1 -option2' -WorkingDirectory 'C:\Program Files\MyProgram' -IconLocation 'C:\Program Files\MyProgram\MyIcon.ico'

    .EXAMPLE
        PS C:\> New-Shortcut -TargetPath 'C:\Program Files\MyProgram\MyProgram.exe' -ShortcutPath 'C:\Users\UserName\Desktop\MyProgram.lnk'

    .PARAMETER TargetPath
        The path to the program or file the shortcut should point to.

    .PARAMETER ShortcutPath
        The path to the shortcut file.

    .PARAMETER Arguments
        The command-line arguments to pass to the target program.

    .PARAMETER WorkingDirectory
        The working directory for the target program.

    .PARAMETER IconLocation
        The path to the icon file to use for the shortcut.

    .NOTES
        This cmdlet requires administrator privileges to run.
    #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[string] $TargetPath,
		[Parameter(Mandatory = $true, Position = 1)]
		[string] $ShortcutPath,
		[Parameter()]
		[string] $Arguments,
		[Parameter()]
		[string] $WorkingDirectory,
		[Parameter()]
		[string] $IconLocation
	)
	# 创建快捷方式
	$WshShell = New-Object -ComObject WScript.Shell
	$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
	$Shortcut.TargetPath = $TargetPath
	$Shortcut.Arguments = $Arguments
	$Shortcut.WorkingDirectory = $WorkingDirectory
	$Shortcut.IconLocation = $IconLocation
	$Shortcut.Save()
}