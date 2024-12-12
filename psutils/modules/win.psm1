
# 这个模块放windows特有的操作



function Add-Startup {
    <#
.SYNOPSIS
    win系统 添加一个程序到开机启动
.DESCRIPTION
    创建一个程序的快捷方式，并将其添加到开机启动startup目录
.NOTES
    Information or caveats about the function e.g. 'This function is not supported in Linux'
.LINK
    Specify a URI to a help page, this will show when Get-Help -Online is used.
.EXAMPLE
    Test-MyTestFunction -Verbose
    Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
#>


    param(
        [string]$Path,
        # 快捷方式名称，默认为文件名
        [string]$LinkName
    )
    #利用环境变量取得用户目录下的startup目录 
    $startUpFolder = "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    # 还有一个是所有用户通用的startup  目录，可能需要管理员权限才能修改。
    # C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp

    # 只有把快捷方式加入到startup目录才能实现快速启动
    # Copy-Item $Path $startUpFolder

    if (-not $LinkName) {
        $LinkName = Split-Path -Path $Path -Leaf
    }

    New-Item -ItemType SymbolicLink -Path $startUpFolder -Name $LinkName -Value $Path 
    Write-Host -ForegroundColor Green ('write  item: {0} to folder {1},link name:{2}' -f $Path, $startUpFolder, $LinkName)
}


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


Export-ModuleMember -Function *