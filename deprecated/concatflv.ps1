
param(
    [string]$targetPath = '.',
    [string]$tempPath = 'temp',
    [string]$sortMethod = 'CreationTime'
)


$flvregex = '[\s\S]+.flv$'
function Get-FileList ($targetPath, $nameregex) {
    $filelist = Get-ChildItem -File  $targetPath | Where-Object { $_.Name -match $nameregex }
    return  $filelist
}

$filelist = Get-FileList -targetPath $targetPath -nameregex $flvregex 

# echo "$filelist  complete"
if (-not( Test-Path $tempPath)) {
    mkdir $tempPath
}
$index = 0
$filelist | Sort-Object -Property $sortMethod | ForEach-Object { $index += 1; Copy-Item $_.Name  "$tempPath/$index.flv"; "file $index.flv" } | Out-File -Encoding ascii "$tempPath/file.txt"


ffmpeg -f concat -safe 0 -i "$tempPath/file.txt" -c copy output.mp4 