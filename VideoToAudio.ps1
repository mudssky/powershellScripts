param(
    [string]$targetPath='.',
    [string]$picPos='00:01:00',
    [string]$picext='.png', 
    [string]$ffmpegParam='',
    [string]$preset='',
    [switch]$embedCover=$true,
    [switch]$deleteSource
)

Write-Host  -ForegroundColor Black -BackgroundColor Gray ('[param] targetPath :{0}, picPos:{1}, picext:{2}, ffmpegParam={3}, baseParam:{4}, embedCover:{5} ,deleteSource:{6},$preset:{7} ' -f
                                            $targetPath,$picPos,$picext,$ffmpegParam,$baseParam,$embedCover,$deleteSource,$preset)
Function GenerateCoverFromVideo($video,$picPos,$picext){
        $videopath = $video.FullName
        $videoext = $video.Extension
        $picbasepath=$videopath.Substring(0,$videopath.Length-$videoext.Length)
        $picpath=$picbasepath+$picext
        if(Test-Path -LiteralPath ($picbasepath+'.jpg')){
                Write-Host -ForegroundColor Yellow ('cover picture already exist,{0}' -f ($picbasepath+'.jpg'))
                 $picpath=$picbasepath+'.jpg'
        }
        Elseif(Test-Path -LiteralPath ($picbasepath+'.webp'))
        {
             Write-Host -ForegroundColor Yellow ('cover picture already exist,{0}' -f ($picbasepath+'.webp'))
             $picpath=$picbasepath+'.webp'
        }
         Elseif(Test-Path -LiteralPath ($picbasepath+'.png')){
             Write-Host -ForegroundColor Yellow ('cover picture already exist,{0}' -f ($picbasepath+'.png'))
             $picpath=$picbasepath+'.png'
        }
        Else{
            $picpath=$picbasepath+$picext
            ffmpeg -i $videopath   -ss $picPos  -frames:v 1   $picpath
        }
        return $picpath
}
$count=0;
$videos = Get-ChildItem -Path $targetPath  -File -Recurse -Include *.mp4,*.flv,*.ts,*.webm,*.mkv
$VideoToAudioTable = @{'.mp4'='.m4a';
                       '.flv'='.m4a';
                       '.ts'='.m4a';
                       '.webm'='.ogg';
                       '.mkv'='.ogg';
                                    }
$UnsupportedEmbedFormat = '.oabc','.osss'

$AlbumTag=@{
                       'bilibili'= ' -metadata album=b站投�?';
                       'niconico'= ' -metadata album=niconico投稿 ';
                       'youtube'= ' -metadata album=youtube投稿 '
                       }
 
$fileNameRegexTables=@{
                       'bilibili'= '(?<year>\d{8})\s+(?<title>[\s\S]*?)-(?<comment>\d+)';
                       'niconico'= '(?<year>\d{8})\s+(?<title>[\s\S]*?)-(?<comment>sm\d+)';
                       'youtube'= '(?<year>\d{8})\s+(?<title>[\s\S]*?)-(?<comment>[\d\w]+)'
 
 }

foreach( $video in $videos ){ 
     $videopath=$video.FullName
     $videoext=$video.Extension
     $audiobasepath=$videopath.Substring(0,$videopath.Length-$videoext.Length)
     $newffempegparam=$ffmpegParam
     $regex = $fileNameRegexTables[$preset]
     Write-Host ('$regex: {0}' -f $regex)
     if($preset){
        $video.BaseName -match $regex
        $filenameTag  =$AlbumTag[$preset] +( '-metadata title="{0}" -metadata date="{1}" -metadata comment="{2}" ' -f $Matches['title'],$Matches['year'],$Matches['comment'])
        $newffempegparam = $ffmpegParam + $filenameTag
        #Write-Verbose ('[filenametag]:{0}' -f $ffmpegParam)
     }
     
                     
     # 使用ffmpeg添加封面，所以添加封面的过程和生成音频流的过程同时进行�?
     #先判断对应的格式是否符合，不符合程序就无法继续执�?
     $newaudioext = $VideoToAudioTable[$videoext]
     if($newaudioext){
         # 查表获取对应视频格式的音频格�?
         $newaudiopath=$audiobasepath+$newaudioext
         # 先获取视频封�?
         $picpath = GenerateCoverFromVideo -video $video -picPos $picPos -picext $picext
         Write-Host -ForegroundColor Green ('get/generate cover pic path {0}' -f $picpath)
        
        $ffmpegCommand =  'ffmpeg -i "{0}"  {1} -acodec copy -vn "{2}"' -f $videopath,$newffempegparam,$newaudiopath
        #判断是否开启了内嵌封面选项
        if($embedCover){
                Write-Host -ForegroundColor Black -BackgroundColor Gray 'converting embedCover audio...'
                # 如果是暂不支持内嵌的格式，那么就不用执行内嵌图片的操作了�?
                if($newaudioext -in $UnsupportedEmbedFormat ){
                    Write-Host -ForegroundColor Red  ('UnsupportedEmbedFormat:{0}' -f $videoext)
                    #不支持内嵌的音频流就直接提取
                    
                     Invoke-Expression $ffmpegCommand
                }elseif($newaudioext -eq '.ogg'){
                        Invoke-Expression $ffmpegCommand
                
                }else{
                  #使用ffmpeg产生内嵌的音频，这个过程中也可以添加参数修改音频的元数据�?
                  $ffmpegCommand = 'ffmpeg -i "{0}" -i "{1}" -map 0:v -map 1:a  {2} -codec copy -disposition:v:0 attached_pic -id3v2_version 4 "{3}"' -f $picpath,$videopath,$newffempegparam,$newaudiopath     
                  Invoke-Expression $ffmpegCommand
                }
        }else{
                Write-Host -ForegroundColor Black -BackgroundColor Gray 'converting uncovered audio...'
                #没有内嵌选项的时候也是直接提取�?
                 Invoke-Expression $ffmpegCommand
                
        }
}
        Write-Verbose    ('[ffmpeg command]:{0}' -f $ffmpegCommand)
    if(-not $deleteSource){
        
    }else{    
        Write-Host -ForegroundColor Green ('convert audio succeed ,deleting file:{0} ' -f $videopath)
        Remove-Item -Force -LiteralPath $videopath
        Write-Host -ForegroundColor Black -BackgroundColor Gray 'done'
    }
}

 Write-Host -ForegroundColor Black -BackgroundColor Gray 'All done'
