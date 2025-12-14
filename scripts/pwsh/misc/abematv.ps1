#!/usr/bin/env pwsh

<#
.SYNOPSIS
    AbemaTV视频流下载脚本

.DESCRIPTION
    该脚本使用streamlink工具下载AbemaTV或其他流媒体平台的视频流。
    支持自定义输出文件名和多线程下载以提高下载速度。

.PARAMETER url
    要下载的视频流URL地址

.PARAMETER filename
    输出文件名，默认为'out.mp4'

.EXAMPLE
    .\abematv.ps1 -url "https://abema.tv/video/xxx" -filename "video.mp4"
    下载指定URL的视频流并保存为video.mp4

.EXAMPLE
    .\abematv.ps1 -url "https://abema.tv/video/xxx"
    下载视频流并保存为默认文件名out.mp4

.NOTES
    需要安装streamlink工具
    使用10个线程进行HLS片段下载以提高速度
    自动选择最佳质量进行下载
#>
param(
    [string]$url,
    [string]$filename = 'out.mp4'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

streamlink $url best --hls-segment-thread 10 -o $filename
