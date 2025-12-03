#!/usr/bin/env pwsh

<#
.SYNOPSIS
    视频转音频脚本

.DESCRIPTION
    该脚本使用ffmpeg将视频文件转换为音频文件，支持多种预设配置和自定义参数。
    可以提取视频封面、嵌入封面到音频文件、设置时间范围等功能。
    支持bilibili、niconico、youtube等平台的预设配置。

.PARAMETER targetPath
    目标视频文件路径，默认为当前目录

.PARAMETER picPos
    提取封面的时间位置，默认为'00:01:00'

.PARAMETER picext
    封面图片的扩展名，默认为'.png'

.PARAMETER ffmpegParam
    自定义的ffmpeg参数

.PARAMETER preset
    预设配置，支持'bilibili'、'niconico'、'youtube'或空字符串

.PARAMETER embedCover
    是否将封面嵌入到音频文件中，默认为true

.PARAMETER deleteSource
    是否删除源视频文件

.PARAMETER startPos
    音频开始时间位置

.PARAMETER endPos
    音频结束时间位置

.PARAMETER outExt
    输出音频文件的扩展名

.EXAMPLE
    ls *.flv | %{VideoToAudio.ps1 -targetPath $_.Name}
    批量转换FLV文件为音频

.EXAMPLE
    .\VideoToAudio.ps1 -targetPath "video.mp4" -preset "bilibili" -deleteSource
    使用bilibili预设转换视频并删除源文件

.NOTES
    需要安装ffmpeg工具
    支持多种视频格式转换
    可自动提取和嵌入封面图片
    支持时间范围裁剪
#>
param(
    [string]$targetPath = '.',
    [string]$picPos = '00:01:00',
    [string]$picext = '.png', 
    [string]$ffmpegParam = '',
    [ValidateSet( 'bilibili', 'niconico', 'youtube', '')]
    [string]$preset = '',
    [bool]$embedCover = $true,
    [switch]$deleteSource,
    [string]$startPos = '',
    [string]$endPos = '',
    [string]$outExt = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Write-Host  -ForegroundColor Black -BackgroundColor Gray ('[param] targetPath :{0}, picPos:{1}, picext:{2}, ffmpegParam={3}, baseParam:{4}, embedCover:{5} ,deleteSource:{6},preset:{7} ' -f
    $targetPath, $picPos, $picext, $ffmpegParam, $baseParam, $embedCover, $deleteSource, $preset)
function GenerateCoverFromVideo($video, $picPos, $picext) {
    $videopath = $video.FullName
    $videoext = $video.Extension
    $picbasepath = $videopath.Substring(0, $videopath.Length - $videoext.Length)
    $picpath = $picbasepath + $picext
    if (Test-Path -LiteralPath ($picbasepath + '.jpg')) {
        Write-Host -ForegroundColor Yellow ('cover picture already exist,{0}' -f ($picbasepath + '.jpg'))
        $picpath = $picbasepath + '.jpg'
    }
    elseif (Test-Path -LiteralPath ($picbasepath + '.webp')) {
        Write-Host -ForegroundColor Yellow ('cover picture already exist,{0}' -f ($picbasepath + '.webp'))
        $picpath = $picbasepath + '.webp'
    }
    elseif (Test-Path -LiteralPath ($picbasepath + '.png')) {
        Write-Host -ForegroundColor Yellow ('cover picture already exist,{0}' -f ($picbasepath + '.png'))
        $picpath = $picbasepath + '.png'
    }
    else {
        $picpath = $picbasepath + $picext
        ffmpeg -i $videopath -ss $picPos -frames:v 1 $picpath
    }
    return $picpath
}

$videos = Get-ChildItem -LiteralPath  $targetPath  -File -Recurse -Include *.mp4, *.flv, *.ts, *.webm, *.mkv
$VideoToAudioTable = @{'.mp4' = '.m4a';
    '.flv'                    = '.m4a';
    '.ts'                     = '.m4a';
    '.webm'                   = '.ogg';
    '.mkv'                    = '.ogg';
    '.m4a'                    = '.m4a';
}
$UnsupportedEmbedFormat = '.oabc', '.osss'

$AlbumTag = @{
    'bilibili' = ' -metadata album=b站投稿 ';
    'niconico' = ' -metadata album=niconico投稿 ';
    'youtube'  = ' -metadata album=youtube投稿 '
}
 
$fileNameRegexTables = @{
    'bilibili' = '(?<year>\d{8})\s+(?<title>[\s\S]*?)-(?<comment>[\d\w]+)';
    'niconico' = '(?<year>\d{8})\s+(?<title>[\s\S]*?)-(?<comment>sm\d+)';
    'youtube'  = '(?<year>\d{8})\s+(?<title>[\s\S]*?)-(?<comment>[\d\w]+)'
 
}

foreach ( $video in $videos ) { 
    $videopath = $video.FullName
    $videoext = $video.Extension
    $audiobasepath = $videopath.Substring(0, $videopath.Length - $videoext.Length)
    $newffempegparam = $ffmpegParam
    $regex = $fileNameRegexTables[$preset]
    Write-Host ('$regex: {0}' -f $regex)
    #  判断是否有提取metadata的preset
    if ($preset) {
        $video.BaseName -match $regex
        $filenameTag = $AlbumTag[$preset] + ( '-metadata title="{0}" -metadata date="{1}" -metadata comment="{2}" ' -f $Matches['title'], $Matches['year'], $Matches['comment'])
        $newffempegparam = $ffmpegParam + $filenameTag
        #Write-Verbose ('[filenametag]:{0}' -f $ffmpegParam)
    }
    #  判断是否进行剪切
    if ($startPos -or $endPos) {
        # 只存在开始时间和结束时间的情况，不指定另一边默认为从视频00开始或者到视频末端结束
        if ($endPos -and $startPos) {
            $newffempegparam = $newffempegparam + (' -ss {0} -to {1}' -f $startPos , $endPos)
        }
        elseif ($endPos) {
            $newffempegparam = $newffempegparam + (' -to {0}' -f $endPos)
        }
        elseif ($startPos) {
            $newffempegparam = $newffempegparam + (' -ss {0}' -f $startPos)
        }
    }
     
                     
    # 使用ffmpeg添加封面，所以添加封面的过程和生成音频流的过程同时进行�?
    #先判断对应的格式是否符合，不符合程序就无法继续执�?
    if ($outExt) {
        $newaudioext = $outExt
    }
    else {
        $newaudioext = $VideoToAudioTable[$videoext]
    }

    if ($newaudioext) {
        # 查表获取对应视频格式的音频格�?
        $newaudiopath = $audiobasepath + $newaudioext
        # 先获取视频封�?
        $picpath = GenerateCoverFromVideo -video $video -picPos $picPos -picext $picext
        Write-Host -ForegroundColor Green ('get/generate cover pic path {0}' -f $picpath)
        
        $ffmpegCommand = 'ffmpeg -i "{0}" {1} -acodec copy -vn "{2}"' -f $videopath, $newffempegparam, $newaudiopath
        #判断是否开启了内嵌封面选项
        if ($embedCover) {
            Write-Host -ForegroundColor Black -BackgroundColor Gray 'converting embedCover audio...'
            # 如果是暂不支持内嵌的格式，那么就不用执行内嵌图片的操作了�?
            if ($newaudioext -in $UnsupportedEmbedFormat ) {
                Write-Host -ForegroundColor Red  ('UnsupportedEmbedFormat:{0}' -f $videoext)
                #不支持内嵌的音频流就直接提取
                    
                Invoke-Expression $ffmpegCommand
            }
            elseif ($newaudioext -eq '.ogg') {
                Invoke-Expression $ffmpegCommand
                
            }
            else {
                #使用ffmpeg产生内嵌的音频，这个过程中也可以添加参数修改音频的元数据�?
                $ffmpegCommand = 'ffmpeg -i "{0}" -i "{1}" -map 0:v -map 1:a {2} -codec copy -disposition:v:0 attached_pic -id3v2_version 4 "{3}"' -f $picpath, $videopath, $newffempegparam, $newaudiopath     
                Invoke-Expression $ffmpegCommand
            }
        }
        else {
            Write-Host -ForegroundColor Black -BackgroundColor Gray 'converting uncovered audio...'
            #没有内嵌选项的时候也是直接提取�?
            Invoke-Expression $ffmpegCommand
                
        }
    }
    Write-Verbose    ('[ffmpeg command]:{0}' -f $ffmpegCommand)
    if (-not $deleteSource) {
        
    }
    else {    
        Write-Host -ForegroundColor Green ('convert audio succeed ,deleting file:{0} ' -f $videopath)
        Remove-Item -Force -LiteralPath $videopath
        Write-Host -ForegroundColor Black -BackgroundColor Gray 'done'
    }
}

Write-Host -ForegroundColor Black -BackgroundColor Gray 'All done'
