
param(
    [string]$path,
    [string]$name
)
#利用环境变量取得用户目录下的startup目录 
$startUpFolder = "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
# 还有一个是所有用户通用的startup  目录，可能需要管理员权限才能修改。
# C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp

# 只有把快捷方式加入到startup目录才能实现快速启动
# Copy-Item $path $startUpFolder

if (-not $name) {
    $name = Split-Path -Path $path -Leaf
}
# path-   
New-Item -ItemType SymbolicLink -Path $startUpFolder -Name $name -Value $path 
Write-Host -ForegroundColor Green ('write  item: {0} to folder {1},link name:{2}' -f $path, $startUpFolder, $name)