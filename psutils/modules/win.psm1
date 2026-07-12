
# 这个模块放windows特有的操作



function Add-Startup {
    <#
.SYNOPSIS
    在 Windows 系统中添加一个程序到开机启动项。

.DESCRIPTION
    此函数通过创建一个程序的符号链接（SymbolicLink）或快捷方式，并将其放置到 Windows 的“启动”文件夹中，
    从而实现程序开机自启动。

.PARAMETER Path
    必需参数。要添加到开机启动的程序的完整路径。

.PARAMETER LinkName
    可选参数。在“启动”文件夹中创建的快捷方式或符号链接的名称。如果未指定，则默认为程序的文件名。

.OUTPUTS
    无。函数执行成功后，会在控制台输出成功信息。

.EXAMPLE
    Add-Startup -Path "C:\Program Files\MyApp\MyApp.exe"
    将 "MyApp.exe" 添加到当前用户的开机启动项，链接名称默认为 "MyApp.exe"。

.EXAMPLE
    Add-Startup -Path "C:\Tools\MyScript.ps1" -LinkName "My PowerShell Script"
    将 "MyScript.ps1" 添加到当前用户的开机启动项，并指定链接名称为 "My PowerShell Script"。

.NOTES
    此函数仅适用于 Windows 操作系统。
    它默认将程序添加到当前用户的启动文件夹 (`$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup`)。
    如果需要添加到所有用户的启动文件夹 (`C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp`)，可能需要管理员权限。
    此函数使用 `New-Item -ItemType SymbolicLink` 创建符号链接，而不是传统的快捷方式（.lnk 文件）。

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
        创建 Windows 快捷方式。

    .DESCRIPTION
        通过 WScript.Shell 创建 `.lnk` 文件，支持目标参数、工作目录和图标设置。

    .EXAMPLE
        PS C:\> New-Shortcut -TargetPath 'C:\Program Files\MyProgram\MyProgram.exe' -ShortcutPath 'C:\Users\UserName\Desktop\MyProgram.lnk' -Arguments '-option1 -option2' -WorkingDirectory 'C:\Program Files\MyProgram' -IconLocation 'C:\Program Files\MyProgram\MyIcon.ico'

    .EXAMPLE
        PS C:\> New-Shortcut -TargetPath 'C:\Program Files\MyProgram\MyProgram.exe' -ShortcutPath 'C:\Users\UserName\Desktop\MyProgram.lnk'

    .PARAMETER TargetPath
        快捷方式指向的程序或文件路径。兼容旧参数名 `Path`。

    .PARAMETER ShortcutPath
        快捷方式文件路径。兼容旧参数名 `Destination`。

    .PARAMETER Arguments
        启动目标程序时传入的命令行参数。

    .PARAMETER WorkingDirectory
        目标程序的工作目录。

    .PARAMETER IconLocation
        快捷方式使用的图标路径。

    .OUTPUTS
        None。函数在指定位置创建快捷方式文件。

    .NOTES
        仅支持 Windows；写入受保护目录时可能需要管理员权限。
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Path')]
        [string] $TargetPath,
        [Parameter(Mandatory = $true, Position = 1)]
        [Alias('Destination')]
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


Export-ModuleMember -Function Add-Startup, New-Shortcut
