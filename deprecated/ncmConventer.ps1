# 调用网易云音乐破解工具
# 现在基本没用网易云音乐了，所以可以弃用
param(
    [switch]$nodelete
)

$ncmList = Get-ChildItem -Recurse  *.ncm

foreach ($ncmFile in $ncmList) {
    $ncmFilePath = $ncmFile.FullName
     
    Write-Host -ForegroundColor Green ('conventing file {0}' -f $ncmFilePath )
    ncmdump-windows-amd64.exe  $ncmFile

    Write-Host -ForegroundColor Green ('convent file succeeed,deleting source file...,path:{0}' -f $ncmFilePath )
    if ($nodelete) {
        Write-Host -ForegroundColor Yellow  'nodelete flag  is open'
    }
    else {
        Remove-Item -Force -LiteralPath  $ncmFilePath
    }

    Write-Host -ForegroundColor Black -BackgroundColor Gray 'Done'
}
Write-Host -ForegroundColor Black -BackgroundColor Gray 'All Done'