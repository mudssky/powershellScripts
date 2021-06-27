param(
    [switch]$delete,
    [string]$crf = 23
)

Get-ChildItem *.vob | Where-Object { $_.Length -ge 100kb } | ForEach-Object {
    if ($_.Length -le 10mb ) {
        ffmpeg.exe -i $_.FullName  ($_.BaseName + '.webp')
    }
    else {
        ffmpeg.exe -i $_.FullName -vcodec libx264 -acodec copy -crf $crf -preset veryfast ($_.BaseName + '.mkv')
    } 
} 


if ($delete) {
    Write-Host -ForegroundColor Red "delete flag open, deleting dvd files(ifo,vob,bup)..."
    Remove-Item -Force *.ifo, *.vob, *.bup
}