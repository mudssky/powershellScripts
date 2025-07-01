<#
.SYNOPSIS
使用通配符或正则表达式匹配视频文件并按时间顺序拼接

.DESCRIPTION
该脚本用于批量拼接视频文件，特别适用于处理录播软件因网络不稳定而分段的视频文件。
支持通配符和正则表达式两种文件匹配方式，默认按照文件创建时间顺序进行拼接，
拼接过程中可以使用预设的 FFmpeg 参数进行转码，支持多种输出格式和质量设置。

.PARAMETER targetPath
脚本执行的目标路径，默认为当前目录 ('.')

.PARAMETER sortMethod
文件的排序方法，默认为 'CreationTime'（按创建时间排序），确保拼接的视频时序正确

.PARAMETER wildcard
通配符匹配模式，用于初步筛选文件，支持标准的 PowerShell 通配符语法

.PARAMETER regexStr
正则表达式字符串，用于精确匹配文件名，在通配符匹配后进行二次过滤

.PARAMETER regexPreset
正则表达式预设，默认为 'flv'，可选值：'flv'、'mp4'，对应不同的文件扩展名匹配

.PARAMETER ffmpegStr
自定义的 FFmpeg 转码参数字符串，如果不指定则使用预设参数

.PARAMETER ffmpegPreset
FFmpeg 预设参数，可选值：'crf23'、'crf28'、'x265'、'hevc'、'720p'、'720paac'、'720p28'、'480p'、'm4a'，默认为 'crf23'

.PARAMETER outputFilename
输出文件名，如果不指定则自动根据第一个文件名生成，扩展名根据预设自动调整

.PARAMETER WhatIf
开关参数，如果指定则只显示将要执行的操作而不实际执行，用于预览和调试

.PARAMETER deleteSource
开关参数，如果指定则在拼接完成后自动删除源文件，否则会提示用户确认

.EXAMPLE
concatflv.ps1
使用默认设置拼接当前目录下的所有 .flv 文件

.EXAMPLE
concatflv.ps1 -targetPath "C:\Videos" -regexPreset "mp4" -ffmpegPreset "720p"
拼接 C:\Videos 目录下的 MP4 文件，输出为 720p 分辨率

.EXAMPLE
concatflv.ps1 -wildcard "录播*" -regexStr ".*\.flv$" -WhatIf
预览匹配 "录播" 开头的 .flv 文件的拼接操作

.EXAMPLE
concatflv.ps1 -ffmpegPreset "m4a" -outputFilename "output.m4a" -deleteSource
提取音频为 M4A 格式并自动删除源文件

.EXAMPLE
concatflv.ps1 -ffmpegStr "-vcodec libx264 -acodec aac -crf 20 -preset medium"
使用自定义 FFmpeg 参数进行拼接

.NOTES
- 需要系统中安装 FFmpeg 工具
- 脚本会生成临时的 filelist.txt 文件，完成后自动删除
- 支持的预设包括不同的视频质量、分辨率和音频提取选项
- 当只有一个文件时，脚本会直接进行转码而不是拼接
- 建议在正式运行前使用 -WhatIf 参数预览操作
#>



param(

  #  脚本执行的目标路径，默认是当前目录
  [string]$targetPath = '.',
  # [string]$tempPath = 'temp',
  # 文件的排序方法，因为目前使用的录播软件《B站录播姬》的问题是网络不稳定的时候会出现下载的视频分成好几段的情况，
  # 拼接视频的时候使用的命令行语句，使用文件创建时间对文件时间进行排序，就能拼接出时序正常的视频
  [string]$sortMethod = 'CreationTime',
  # 支持通配符和正则两种方式，先进行通配符匹配，如果输入参数里有正则的字符串，再用正则过滤一次
  [string]$wildcard = '',
  [string]$regexStr = '',
  # 预设，存放在哈希表里，方便调用
  [string]$regexPreset = 'flv',
  [string]$ffmpegStr = '',
  [ValidateSet('crf23', 'crf28', 'x265', 'hevc', '720p', '720paac', '720p28', '480p', 'm4a', '')]
  [string]$ffmpegPreset = 'crf23',
  [string]$outputFilename = '',
  [switch]$WhatIf,
  [switch]$deleteSource
)

$regexPresetMap = @{
  flv = '[\s\S]+\.flv$';
  mp4 = '[\s\S]+\.mp4$';
}
$ffmpegPresetMap = @{
  copy      = '-c copy';
  ''        = '-vcodec libx264 -acodec copy -crf 23  -preset veryfast';
  'crf23'   = '-vcodec libx264 -acodec copy -crf 23  -preset veryfast';
  'crf28'   = '-vcodec libx264 -acodec copy -crf 28  -preset veryfast';
  'x265'    = '-vcodec libx265 -acodec copy -crf 23  -preset fast';
  'hevc'    = '-vcodec libx265 -acodec copy -crf 28  -preset fast';
  '720p'    = '-vcodec libx264 -acodec copy -crf 23  -preset veryfast -r 30 -s 1280*720';
  '720paac' = '-vcodec libx264  -crf 23  -preset veryfast -r 30 -s 1280*720';
  '720p28'  = '-vcodec libx264 -acodec copy -crf 28  -preset veryfast -r 30 -s 1280*720';
  '480p'    = '-vcodec libx264 -acodec copy -crf 23  -preset veryfast -r 30 -s 854*480';
  'm4a'     = ' -acodec copy -vn ';

}

# 获取文件名列表
function Get-FileList ($targetPath = '.', $regexStr, $wildcard = '') {
  if ($wildcard) {
    $fileList = Get-ChildItem -File -Filter $targetPath | Where-Object { $_.Name -like $wildcard } | Where-Object { $_.Name -match $regexStr }
  }
  else {
    $fileList = Get-ChildItem -File -Filter $targetPath | Where-Object { $_.Name -match $regexStr }
  }
  return  $fileList
}



# 先判断有没有设置正则字符串?是否为空串，如果没有设置就会按照预设进行
if ( -not $regexStr ) {
  $regexStr = $regexPresetMap[$regexPreset] 
}
# 判断ffmpeg转码命令字符串有没有进行设置，如果没有设置就会调用预设
if (-not $ffmpegStr ) {
  $ffmpegStr = $ffmpegPresetMap[$ffmpegPreset]
}



$fileList = Get-FileList -targetPath $targetPath -regexStr $regexStr -wildcard $wildcard  | Sort-Object -Property $sortMethod

# 如果文件列表找到的文件数目为0，说明文件名匹配不到，应该报错并且退出
if ($fileList.Count -le 0) {
  Write-Host -ForegroundColor Red  -Debug '没有找到匹配的文件'
  exit 1
}

$filenameList = $fileList | ForEach-Object { $_.Name }


# 判断是否给定输出的文件名，如果没有给定输出的文件名，就命名为文件名列表的第一个文件名，并且后缀改成mp4
if (-not $outputFilename) {
  if ($ffmpegPreset -eq 'm4a') {
    $outputFilename = $fileList[0].Name.Replace('.flv', '.m4a') 
  }
  else {
    $outputFilename = $fileList[0].Name.Replace('.flv', '.mp4') 
  }
}
# whatif 输出会执行的操作和各个参数，用于检查匹配是否成功，防止出现意外
if ($WhatIf) {
  Write-Host  -ForegroundColor Yellow '将拼接的文件列表'
  $filenameList
  Write-Host -Debug -ForegroundColor Green ('ffmpeg 转码参数: {0},  输出文件名:{1}' -f $ffmpegStr, $outputFilename )
  exit 1
}
# 多余一个文件的时候才需要拼接，
if ($filenameList.Count -ne 1) {
  # $concatStr = $filenameList -join '|'
  # $concatStr = 'concat:' + $concatStr
  # $concatCommand = 'ffmpeg.exe -i "{0}"  {1} "{2}"' -f $concatStr, $ffmpegStr, $outputFilename
  # 生成concat文件列表
  $filenameList | ForEach-Object { "file '{0}'" -f $_ } > filelist.txt
  $concatCommand = 'ffmpeg.exe -f concat -safe 0  -i filelist.txt   {0} "{1}"' -f $ffmpegStr, $outputFilename
  Write-Host -ForegroundColor Green  ('执行的ffmpeg命令为： {0}' -f $concatCommand)
  Invoke-Expression -Command $concatCommand

  Write-Host -ForegroundColor Green  '执行完成，删除filelist.txt 文件...'
  Remove-Item -Force 'filelist.txt'
  # ffmpeg -f concat -safe 0 -i "$tempPath/file.txt" -c copy output.mp4 
  concatXML -wildcard $wildcard
} 
else {
  # 只有一个文件的时候就直接执行转码部分
  $concatCommand = 'ffmpeg.exe -i "{0}"  {1} "{2}"' -f $fileList[0].Name, $ffmpegStr, $outputFilename
  Write-Host -ForegroundColor Green  ('执行的ffmpeg命令为： {0}' -f $concatCommand)
  Invoke-Expression -Command $concatCommand
}

if ($deleteSource) {
  $fileList | ForEach-Object { Remove-Item -Force $_; Write-Host -ForegroundColor Green ('delete file succeed,:{0}' -f $_.Name) }
}
else {
  $answerStr = Read-Host  '输入yes或y删除用于拼接的源文件'

  if ($answerStr -like 'y') {
    $fileList | ForEach-Object { Remove-Item -Force $_  ;
      Write-Host -ForegroundColor Green ('delete file succeed,:{0}' -f $_.Name)
    } 
  }

}

