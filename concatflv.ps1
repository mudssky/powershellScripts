<#
.DESCRIPTION
使用通配符或者正则来匹配文件名，对匹配的视频进行拼接，默认按照文件创建时间顺序来拼接，拼接过程按照给定的ffmpeg参数进行转码
#>
param(

  #  脚本执行的目标路径，默认是当前目录
  [string]$targetPath = '.',
  [string]$tempPath = 'temp',
  # 文件的排序方法，因为目前使用的录播软件《B站录播姬》的问题是网络不稳定的时候会出现下载的视频分成好几段的情况，
  # 拼接视频的时候使用的命令行语句，使用文件创建时间对文件时间进行排序，就能拼接出时序正常的视频
  [string]$sortMethod = 'CreationTime',
  # 支持通配符和正则两种方式，先进行通配符匹配，如果输入参数里有正则的字符串，再用正则过滤一次
  [string]$wildcard = '',
  [string]$regexStr = '',
  # 预设，存放在哈希表里，方便调用
  [string]$regexPreset = 'flv',
  [string]$ffmpegStr = '',
  [string]$ffmpegPreset = '-vcodec libx264 -acodec copy -crf 23  -preset veryfast',
  [string]$outputFilename = '',
  [switch]$WhatIf,
  [switch]$deleteSource
)

$regexPresetMap = @{
  flv = '[\s\S]+\.flv$';
}
$ffmpegPresetMap = @{
  copy     = '-c copy';
  ''       = '-vcodec libx264 -acodec copy -crf 23  -preset veryfast'
  'crf28'  = '-vcodec libx264 -acodec copy -crf 23  -preset veryfast'
  'x265'   = '-vcodec libx265 -acodec copy -crf 23  -preset fast';
  'hevc'   = '-vcodec libx265 -acodec copy -crf 28  -preset fast';
  '720p'   = '-vcodec libx264 -acodec copy -crf 23  -preset veryfast -r 30 -s 1280*720';
  '720p28' = '-vcodec libx264 -acodec copy -crf 28  -preset veryfast -r 30 -s 1280*720';
  '480p'   = '-vcodec libx264 -acodec copy -crf 23  -preset veryfast -r 30 -s 854*480';

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


$fileList = Get-FileList -targetPath $targetPath -regexStr $regexStr -wildcard $wildcard  | Sort-Object -Property $sortMethod -Descending

# 如果文件列表找到的文件数目为0，说明文件名匹配不到，应该报错并且退出
if ($fileList.Count -le 0) {
  Write-Host -ForegroundColor Red  -Debug '没有找到匹配的文件'
  exit 1
}

$filenameList = $fileList | ForEach-Object { $_.Name }


# 判断是否给定输出的文件名，如果没有给定输出的文件名，就命名为文件名列表的第一个文件名，并且后缀改成mp4
if (-not $outputFilename) {
  $outputFilename = $fileList[0].Name.Replace('.flv', '.mp4') 
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
  $concatStr = $filenameList -join '|'

  $concatStr = 'concat:' + $concatStr

  $concatCommand = 'ffmpeg.exe -i "{0}"  {1} "{2}"' -f $concatStr, $ffmpegStr, $outputFilename

  Invoke-Expression -Command $concatCommand

  # ffmpeg -f concat -safe 0 -i "$tempPath/file.txt" -c copy output.mp4 
} 
else {
  # 只有一个文件的时候就直接执行转码部分
  $concatCommand = 'ffmpeg.exe -i "{0}"  {1} "{2}"' -f $fileList[0].Name, $ffmpegStr, $outputFilename
  Invoke-Expression -Command $concatCommand
}

if ($deleteSource) {
  $fileList | ForEach-Object { Remove-Item -Force $_ }
}
else {
  $answerStr = Read-Host  '输入yes或y删除'

  if ($answerStr -like 'y') {
    $fileList | ForEach-Object { Remove-Item -Force $_  ;
      Write-Host -ForegroundColor Green ('delete file succeed,:{0}' -f $_.Name)
    } 
    
    
  }

}

