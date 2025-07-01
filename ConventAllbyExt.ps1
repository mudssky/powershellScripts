<#
.SYNOPSIS
    批量音频格式转换脚本

.DESCRIPTION
    该脚本使用ffmpeg工具递归遍历当前目录及其子目录，将指定扩展名的音频文件
    批量转换为目标格式。支持可选的删除源文件功能，并统计转换的文件数量。

.PARAMETER inputExt
    输入文件的扩展名（不包含点号），例如：tta、flac、wav

.PARAMETER outputExt
    输出文件的扩展名（不包含点号），例如：flac、mp3、wav

.PARAMETER deleteSource
    是否删除源文件，默认为true。设置为false可保留原始文件

.EXAMPLE
    .\ConventAllbyExt.ps1 -inputExt tta -outputExt flac -deleteSource $false
    将所有TTA文件转换为FLAC格式，保留原始文件

.EXAMPLE
    .\ConventAllbyExt.ps1 -inputExt wav -outputExt mp3
    将所有WAV文件转换为MP3格式，删除原始文件

.NOTES
    需要安装ffmpeg工具
    脚本会递归处理所有子目录
    显示转换和删除的文件信息
    统计处理的文件总数
#>

param(
    [Parameter(Mandatory = $True)][string]$inputExt,
    [Parameter(Mandatory = $True)][string]$outputExt,
    [bool] $deleteSource = $true
)
$inputExtCounts = 0
Get-ChildItem -Recurse -Force | 
ForEach-Object { if ($_.name.EndsWith('.' + $inputExt)) {
        $inputExtCounts++; ffmpeg -i $_.FullName  ($_.FullName.TrimEnd($inputExt) + $outputExt); if ($deleteSource) {
            Remove-Item -Force -LiteralPath $_.FullName; "convert and deleted: $($_.Fullname)"
        }
    }
}

Write-Host -ForegroundColor Green  "$inputExt counts:$inputExtCounts"; pause