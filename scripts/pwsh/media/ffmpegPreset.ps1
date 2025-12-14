#!/usr/bin/env pwsh

<#
.SYNOPSIS
    FFmpeg视频压制预设脚本

.DESCRIPTION
    该脚本提供FFmpeg视频压制的快速预设配置，主要用于缩小直播录制视频的体积。
    支持多种预设模式和自定义参数，可以批量处理视频文件。

.PARAMETER path
    输入视频文件的路径

.PARAMETER ffmpegStr
    自定义的FFmpeg参数字符串，默认为'-vcodec libx264 -acodec copy -crf 23 -preset veryfast'

.PARAMETER outpath
    输出文件的路径，如果不指定则自动生成

.PARAMETER outExt
    输出文件的扩展名，默认为'.mp4'

.PARAMETER preset
    预设配置名称，支持'720p'、'720p28'等预设

.EXAMPLE
    .\ffmpegPreset.ps1 -path 'input.flv'
    使用默认设置压制单个视频文件

.EXAMPLE
    ls *.flv | %{ffmpegPreset.ps1 -path $_.Name}
    批量压制当前目录下的所有FLV文件

.EXAMPLE
    ls *.flv | %{ffmpegPreset.ps1 -preset '720p28' -path $_.Name}
    使用720p28预设批量压制视频

.EXAMPLE
    ls *.flv | %{ffmpegPreset.ps1 -preset '720p' -path $_.Name}
    使用720p预设批量压制视频

.NOTES
    需要安装FFmpeg工具
    主要用于直播录制视频的体积压缩
    支持自定义编码参数和预设配置
#>
param(
    [string]$path,
    [string]$ffmpegStr = '-vcodec libx264 -acodec copy -crf 23  -preset veryfast',
    [string]$outpath,
    [string]$outExt = '.mp4',
    [string]$preset = ''
	
)

#[string]$ffmpegStr='-vcodec libx264 -acodec copy -crf 23 -r 30 -preset veryfast',
$presetTable = @{'veryslow' = '-vcodec libx264 -acodec copy -crf 23 -r 30 -preset veryslow';
    ''                      = '-vcodec libx264 -acodec copy -crf 23  -preset veryfast';
    'm2ts'                  = ' -vcodec libx265 -acodec flac ';
    'x265'                  = '-vcodec libx265 -acodec copy -crf 23  -preset fast';
    'hevc'                  = '-vcodec libx265 -acodec copy -crf 28  -preset fast';
    '720p'                  = '-vcodec libx264 -acodec copy -crf 23  -preset veryfast -r 30 -s 1280*720';
    '720p28'                = '-vcodec libx264 -acodec copy -crf 28  -preset veryfast -r 30 -s 1280*720';
    '480p'                  = '-vcodec libx264 -acodec copy -crf 23  -preset veryfast -r 30 -s 854*480';
    'copy'                  = '-c copy'
}

$ffmpegStr = if ($presetTable.ContainsKey($preset)) { $presetTable[$preset] } else { $ffmpegStr }

#$extLenth=$path.Length-$path.LastIndexOf('.')
if (-not $outpath) {
    $outpath = $path.Substring(0, $path.LastIndexOf('.')) + $outExt
}

$commandStr = ("ffmpeg -i '{0}' {1} '{2}'" -f $path, $ffmpegStr, $outpath)


Invoke-Expression $commandStr
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
