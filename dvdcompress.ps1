param(
[switch]$delete=$true
)

ls *.vob |where{$_.Length -ge 100kb}|foreach{
            if($_.Length -le 10mb ){
                ffmpeg.exe -i $_.FullName  ($_.BaseName+'.webp')
            }else{
             ffmpeg.exe -i $_.FullName -vcodec libx264 -acodec flac -crf 18 -preset veryfast ($_.BaseName+'.mkv')
            } 
 } 


 if($delete){
 Write-Host -ForegroundColor Red "delete flag open, deleting dvd files(ifo,vob,bup)..."
 rm -Force *.ifo,*.vob,*.bup
 }