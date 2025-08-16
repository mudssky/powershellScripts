<#
.SYNOPSIS
    计算文件夹大小的脚本

.DESCRIPTION
    该脚本用于递归计算指定目录下所有文件的总大小和文件数量。
    结果以GB为单位显示，并统计扫描的文件总数。

.PARAMETER path
    要计算大小的目录路径，默认为当前目录（'.'）

.EXAMPLE
    .\folderSize.ps1
    计算当前目录的大小

.EXAMPLE
    .\folderSize.ps1 -path "C:\Users\Documents"
    计算指定目录的大小

.NOTES
    递归扫描所有子目录和文件
    显示文件总数和总大小（GB）
    结果以绿色文字显示
#>

param(
    [string]$path = '.'
)
$count = 0;
$folderSize = 0;
Get-ChildItem -Recurse -Path $path |   ForEach-Object { $folderSize += $_.length; $count += 1 }

Write-Host -ForegroundColor Green ('共扫描文件数：{0},总文件大小{1:n3}GB,path:{2}' -f $count, ($folderSize / 1gb), $path)
