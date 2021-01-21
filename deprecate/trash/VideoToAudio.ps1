param(
    [string]$targetPath='.',
    [string]$picPos='00:02:00',
    [string]$picext='.png',
    [string]$kid3Param,
    [switch]$embedCover,
    [switch]$nodelete
)

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
            ffmpeg -i $videopath   -ss $picPos -frames:v 1  $picpath
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


foreach( $video in $videos ){
     $videopath=$video.FullName
     $videoext=$video.Extension
     $audiobasepath=$videopath.Substring(0,$videopath.Length-$videoext.Length)
     # ����ȡ��Ӧ��Ƶ��ʽ����Ƶ��ʽ
     $newaudiopath=$audiobasepath+$VideoToAudioTable[$videoext]
     if($newaudiopath){
        ffmpeg -i $videopath -acodec copy -vn $newaudiopath
     }else{
         #�����Ƶ�ĸ�ʽ�����鲻������ô�˳����� 
         Write-Host -ForegroundColor Red '��ʽƥ��ʧ�ܣ��ű��˳�����'
         exit -1
     }
        # switch ($videoext){
        #     '.mp4' {
        #          $newaudiopath=$audiobasepath+$VideoToAudioTable[$videoext]
        #         ffmpeg -i $videopath -acodec copy -vn $newaudiopath
        #     }
        #     '.flv' {
        #         $newaudiopath=$audiobasepath+$videoext
        #         ffmpeg -i $videopath -acodec copy -vn $newaudiopath
        #     }
        #     '.webm'{
        #         $newaudiopath=$audiobasepath+$videoext
        #         ffmpeg -i $videopath -acodec copy -vn $newaudiopath
        #     }
        #     '.mkv'{
        #         $newaudiopath=$audiobasepath+'.opus'
        #         ffmpeg -i $videopath -acodec copy -vn $newaudiopath
        #     }
        #     Default {
        #          Write-Host -ForegroundColor Red '��ʽƥ��ʧ�ܣ��ű��˳�����'
        #            exit -1
        #     } }

    # �����·��û�б���ֵ��˵����ʽƥ��ʧ�ܣ�Ҫ�˳��ű�?
    #if ( -not $newaudiopath ){
    #   Write-Host -ForegroundColor Red '��ʽƥ��ʧ�ܣ��ű��˳�'
    #    exit -1
    #}
    
    if($embedCover){
        # ʹ��kid3����Ƶ��ӷ���
        Write-Host -ForegroundColor Green ('write cover tag to file {0}' -f $newaudiopath )
        $picpath = GenerateCoverFromVideo -video $video -picPos $picPos -picext $picext

        $command = 'kid3-cli.exe -c "set picture {0}" {1} "{2}"' -f $picpath,$kid3Param,$newaudiopath
        # kid3-cli.exe -c "set picture $picpath"  $newaudiopath
        write -Verbose   ('[verbose]: kid3 command:' + $command)
        Invoke-Expression $command
    }

    if($nodelete){
        Write-Host -ForegroundColor Yellow 'nodelele flag is open'
    }else{
        Write-Host -ForegroundColor Green ('convert audio succeed ,deleting file:{0} ' -f $videopath)
        Remove-Item -Force -LiteralPath $videopath
        Write-Host -ForegroundColor Black -BackgroundColor Gray 'done'
    }
}

 Write-Host -ForegroundColor Black -BackgroundColor Gray 'All done'
