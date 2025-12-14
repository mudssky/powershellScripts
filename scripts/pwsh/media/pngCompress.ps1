#!/usr/bin/env pwsh

<#
.SYNOPSIS
    批量压缩PNG图片的脚本

.DESCRIPTION
    该脚本使用FFmpeg将占用空间过大的PNG图片批量转换为WebP格式以减小文件大小。
    只处理超过指定大小阈值的图片文件，支持自定义压缩参数和质量设置。

.PARAMETER targetPath
    要处理的目标目录路径，默认为当前目录（'.'）

.PARAMETER limitSize
    需要压缩的图片大小阈值，小于此值的图片不进行压缩，默认为10MB

.PARAMETER paramStr
    FFmpeg的自定义参数字符串，默认为'-codec libwebp -pix_fmt yuv420p -vf scale=iw:ih -lossless 0 -quality 75'

.PARAMETER noDelete
    开关参数，如果指定则保留原始PNG文件，否则删除原始文件

.EXAMPLE
    .\pngCompress.ps1
    使用默认设置压缩当前目录下超过10MB的PNG图片

.EXAMPLE
    .\pngCompress.ps1 -limitSize 5mb -noDelete
    压缩超过5MB的PNG图片并保留原始文件

.EXAMPLE
    .\pngCompress.ps1 -limitSize 10mb -paramStr '-codec libwebp -vf scale=iw/4:ih/4 -lossless 1 -quality 100 -pix_fmt yuv420p'
    使用自定义参数压缩图片，缩放到1/4大小并使用无损压缩

.NOTES
    需要安装FFmpeg工具
    默认转换为WebP格式以获得更好的压缩率
    支持自定义压缩质量和缩放参数
#>
param(
    # 需要压缩的图片阈值大小，小于这个数值的图片不进行压缩
    [string]$targetPath = '.',
    [int]$limitSize = 10mb,
    [string]$paramStr = '-codec libwebp -pix_fmt yuv420p -vf scale=iw:ih  -lossless 0 -quality 75',
    # 其实不用多设置，默认的设置就是最好的，默认压制出来的就是yuv420p
    #[string]$paramStr='-codec libwebp  -vf scale=iw:ih  -lossless 0 -quality 75',
    [switch]$noDelete
)

#只压缩png格式的图片，先检索目录下的png图片
$count = 0
Get-ChildItem -Recurse -LiteralPath $targetPath | Where-Object { $_.Extension -eq '.png' } | ForEach-Object {
    if ($_.Length -gt $limitSize) {
        Write-Host -ForegroundColor Green "detect large png picture : $($_.FullName) size:$($_.Length/1mb) "
     
        $newfullname = $_.FullName.Substring(0, $_.FullName.Length - 4) + '.webp'
        Invoke-Expression "ffmpeg -i '$($_.FullName)' $paramStr '$($newfullname)'"
        # ffmpeg.exe -i $_.FullName  $paramStr  ($_.FullName.Substring(0,$_.FullName.Length-4)+'.webp')

        if ((Test-Path -LiteralPath $newfullname) -and (-not $noDelete)) {
            Remove-Item -LiteralPath $_.FullName
            Write-Host -ForegroundColor yellow "delete $($_.FullName) complete "
            $count++
        }
        else {
            Write-Host -ForegroundColor red "not find the source file or no delete "
            #break
        }
    }
}

Write-Host -ForegroundColor  Green   "compress $count  png files  complete"





Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
