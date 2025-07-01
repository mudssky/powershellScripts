<#
.SYNOPSIS
    批量OCR文字识别脚本

.DESCRIPTION
    该脚本使用Tesseract OCR引擎对当前目录下的图片文件进行批量文字识别。
    专门配置为识别日文垂直文本，输出识别结果为同名的文本文件。
    支持多种常见图片格式。

.EXAMPLE
    .\tesseract.ps1
    对当前目录下的所有支持格式图片进行日文OCR识别

.NOTES
    需要安装Tesseract OCR引擎
    需要安装日文语言包（jpn_vert）
    支持的图片格式：jpg, png, jpeg, webp
    使用220 DPI设置以提高识别精度
    专门用于识别日文垂直排列文本
    输出文件为与原图片同名的.txt文件
#>

Get-ChildItem *.jpg, *.png, *.jpeg, *.webp | ForEach-Object { tesseract.exe $_.Name $_.BaseName -l jpn_vert --dpi 220 }