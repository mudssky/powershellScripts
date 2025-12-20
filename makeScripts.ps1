#requires -version 5.0
param(
    [string]$scriptName = 'myAllScripts.ahk',
    # 当前用户快速启动文件夹的位置
    [string]$startUpFolder = "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    # 所有用户通用的快速启动目录 (需要管理员权限)
    # [string]$startUpFolder = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp",
    [switch]$concatNotInclude
)
function New-Shortcut($targetPath, $sourcePath) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($targetPath)
    $shortcut.TargetPath = $sourcePath
    $shortcut.Save()
}

$includeString = ''
# 递归查找scripts目录下的所有ahk脚本，合成为一个脚本
Get-ChildItem -Recurse -Path ./Scripts *.ahk | ForEach-Object {
    if ($concatNotInclude) {
        # -raw获取原始字符串，这样就不会破坏换行符了。
        $ahkStr = Get-Content -Path $_.FullName -Raw
        $includeString += $ahkStr + "`n"
    }
    else {
        # powershell里面要把换行符解释成换行符
        $includeString += "#include  {0} `n" -f $_.FullName
    }
}

$baseStr = Get-Content .\base.ahk -Raw

$finalAHK = $baseStr + "`n" + $includeString

# 使用 UTF8 编码写入文件
Out-File -InputObject $finalAHK -Encoding utf8 -FilePath $scriptName 

$linkPath = Join-Path -Path $startUpFolder -ChildPath $scriptName.Replace('.ahk', '.lnk')

# 如果还没有加入快捷方式到快速启动，就创建一次快捷方式，实现快速启动
if (-not (Test-Path -Path $linkPath)) {
    # New-Item -ItemType SymbolicLink -Path $startUpFolder -Name $scriptName  -Value $scriptName
    New-Shortcut -targetPath $linkPath -sourcePath (Join-Path -Path (Get-Location) -ChildPath $scriptName)
    Write-Host -ForegroundColor Green ('Written shortcut: {0} to folder {1}' -f $scriptName, $startUpFolder)
}

# 杀死旧进程并执行新脚本
$processName = "AutoHotkey" # 或者脚本名，取决于AHK运行方式
# 这里简单起见，直接启动新进程，AHK通常会提示是否替换实例（由#SingleInstance Force控制）
Start-Process -FilePath $scriptName