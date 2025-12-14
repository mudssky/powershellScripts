#!/usr/bin/env pwsh

<#
.SYNOPSIS
    从视频文件中提取ASS字幕的脚本

.DESCRIPTION
    该脚本使用ffmpeg工具从MKV和MP4视频文件中提取ASS格式的字幕文件。
    脚本会递归搜索当前目录及其子目录中的所有视频文件，并为每个文件提取字幕。
    输出的字幕文件与原视频文件同名，但扩展名为.ass。

.EXAMPLE
    .\ExtractAss.ps1
    从当前目录及子目录的所有MKV和MP4文件中提取ASS字幕

.NOTES
    需要安装ffmpeg工具
    支持MKV和MP4格式的视频文件
    输出字幕文件格式为ASS（Advanced SubStation Alpha）
    如果视频文件不包含字幕轨道，ffmpeg会报错但不影响其他文件处理
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Get-ChildItem -Recurse *.mkv, *.mp4 |
    ForEach-Object {
        $src = $_.FullName
        $ass = ($_.FullName.Substring(0, $_.FullName.Length - 3) + 'ass')
        if ($PSCmdlet.ShouldProcess($src, "提取字幕到 $ass")) {
            ffmpeg -i $src $ass
        }
    }
