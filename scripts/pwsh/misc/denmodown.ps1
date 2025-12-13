#!/usr/bin/env pwsh

<#
.SYNOPSIS
    演示视频流下载脚本

.DESCRIPTION
    该脚本包含使用不同工具下载视频流的示例命令。
    包括使用ffmpeg下载RTMP流和使用N_m3u8DL-CLI下载M3U8流的方法。
    文件中的命令可作为参考模板使用。

.EXAMPLE
    根据脚本中的示例命令手动执行相应的下载操作

.NOTES
    需要安装ffmpeg和N_m3u8DL-CLI工具
    脚本包含示例URL和命令格式
    支持RTMP和M3U8流媒体格式
    文件编码可能存在问题，建议检查字符编码
#>

# 使用ffmpeg下载RTMP流的示例
# ffmpeg.exe -i rtmp://210.140.160.75:1935/denmo/mp4:denmov.mp4 -c copy out.mp4

# 使用N_m3u8DL-CLI下载M3U8流的示例
# N_m3u8DL-CLI_v2.6.0.exe 'http://210.140.160.75:1935/denmo/mp4:denmov.mp4/playlist.m3u8'
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

N_m3u8DL-CLI_v3.0.2.exe 'http://210.140.160.75:1935/denmo/mp4:denmov.mp4/playlist.m3u8'

# M3U8流地址示例
# http://210.140.160.75:1935/denmo/mp4:denmov.mp4/chunklist_w1303489742.m3u8
