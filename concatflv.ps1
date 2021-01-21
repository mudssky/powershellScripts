<#
.DESCRIPTION
使用通配符或者正则来匹配文件名，对匹配的视频进行拼接，默认按照文件创建时间顺序来拼接，拼接过程按照给定的ffmpeg参数进行转码
#>
param(

#  脚本执行的目标路径，默认是当前目录
[string]$targetPath='.',
[string]$tempPath='temp',
# 文件的排序方法，因为目前使用的录播软件《B站录播姬》的问题是网络不稳定的时候会出现下载的视频分成好几段的情况，
# 拼接视频的时候使用的命令行语句，使用文件创建时间对文件时间进行排序，就能拼接出时序正常的视频
[string]$sortMethod='CreationTime',
# 支持通配符和正则两种方式，先进行通配符匹配，如果输入参数里有正则的字符串，再用正则过滤一次
[string]$wildcard='',
[string]$regexStr='',
# 预设，存放在哈希表里，方便调用
[string]$regexPreset='flv',
[string]$ffmpegStr='',
[string]$ffmpegPreset='copy',
[string]$outputFilename=''
)

$regexPresetMap = @{
  flv = '[\s\S]+\.flv$';
}
$ffmpegPresetMap = @{
  copy = '-c copy'
}

# 获取文件名列表
function Get-FileList ($targetPath='.', $regexStr, $wildcard=''){
  if ($wildcard) {
    $fileList = Get-ChildItem -File -Filter $targetPath | Where-Object{$_.Name -like $wildcard} | Where-Object{$_.Name -match $regexStr}
  }else{
    $fileList = Get-ChildItem -File -Filter $targetPath | Where-Object{$_.Name -match $regexStr}
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


$fileList = Get-FileList -targetPath $targetPath -regexStr $regexStr -wildcard $wildcard

# 如果文件列表找到的文件数目为0，说明文件名匹配不到，应该报错并且退出
if ($fileList.Count -le 0){
  Write-Host -ForegroundColor Red  -Debug '没有找到匹配的文件'
  exit 1
}

$filenameList = $fileList | Sort-Object -Property $sortMethod | ForEach-Object{ $_.Name }


# 判断是否给定输出的文件名，如果没有给定输出的文件名，就命名为文件名列表的第一个文件名，并且后缀改成mp4
if ($outputFilename) {
  $outputFilename = $filenameList[0].Replace('.flv','.mp4') 
}

# 多余一个文件的时候才需要拼接，
if ($filenameList.Count -ne 1){
  $concatStr = $filenameList -join '|'

  $concatStr = 'concat:' + $concatStr

  $concatCommand = 'ffmpeg.exe -i "{0}"  "{1}" "{2}"' -f $concatStr,$ffmpegStr,$outputFilename

  Invoke-Expression -Command $concatCommand

  # ffmpeg -f concat -safe 0 -i "$tempPath/file.txt" -c copy output.mp4 
} 
else{
  # 只有一个文件的时候就直接执行转码部分
  $concatCommand = 'ffmpeg.exe -i "{0}"  "{1}" "{2}"' -f $filenameList[0],$ffmpegStr,$outputFilename
  Invoke-Expression -Command $concatCommand
}
