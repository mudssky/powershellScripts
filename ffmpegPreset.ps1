<#
.synopsis
关于ffmpeg压制视频的快速预设，主要用于缩小直播录制视频的体积。
.example
ffmpegPreset.ps1 -path 'input.flv'

ls *.flv|%{ffmpegPreset.ps1 -path $_.Name}
#>
param(
    [string]$path,
    [string]$ffmpegStr='-vcodec libx264 -acodec copy -crf 23  -preset veryfast',
	[string]$outpath,
    [string]$preset=''
	
)

#[string]$ffmpegStr='-vcodec libx264 -acodec copy -crf 23 -r 30 -preset veryfast',
$presetTable=@{'veryslow'='-vcodec libx264 -acodec copy -crf 23 -r 30 -preset veryslow';
    ''='-vcodec libx264 -acodec copy -crf 23  -preset veryfast';
    'x265'='-vcodec libx265 -acodec copy -crf 23  -preset fast';
    'hevc'='-vcodec libx265 -acodec copy -crf 28  -preset fast';
    '720p'='-vcodec libx264 -acodec copy -crf 23  -preset veryfast -r 30 -s 1280*720';
    '720p28'='-vcodec libx264 -acodec copy -crf 28  -preset veryfast -r 30 -s 1280*720';
    '480p'='-vcodec libx264 -acodec copy -crf 23  -preset veryfast -r 30 -s 854*480';
    'copy'='-c copy'
}

$ffmpegStr=$presetTable[$preset]

#$extLenth=$path.Length-$path.LastIndexOf('.')
if ( -not $outpath){
$outpath=$path.Substring(0,$path.LastIndexOf('.'))+'.mp4'
}

$commandStr = ("ffmpeg.exe -i  '{0}'  {1}  '{2}' "-f $path,$ffmpegStr,$outpath)


Invoke-Expression $commandStr