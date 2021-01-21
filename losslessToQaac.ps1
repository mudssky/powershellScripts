
param(
    [string]$qaacParam='--verbose --rate keep -v320 -q2 --copy-artwork',
    [string]$targetPath='.',
    [switch]$nodelete,
    [switch]$he
)

if($he){
    $qaacParam='--verbose --copy-artwork --rate keep --he -v320 -q2 '
}
$losslessFiles= Get-ChildItem -Recurse -File  -LiteralPath $targetPath | Where-Object {($_.Extension  -eq '.flac') -or ($_.Extension  -eq '.wav') }
$fileCounts = $losslessFiles.Length
Write-Host -ForegroundColor Green ('Totally found '+ $fileCounts+' lossless audio files')

$index = 0
foreach($losslessFile in $losslessFiles){
    $index+=1
    Write-Host "`n"
    $progeressPercent=[int]($index/$fileCounts*100)
    $restCounts = $fileCounts-$index
    #Write-Host  -BackgroundColor Gray -ForegroundColor Black ('converting '+$index +' audio file ,progressing '+[int]($index/$fileCounts*100)+'% ,'+($fileCounts-$index)+' rest files' )
    Write-Host  -BackgroundColor Gray -ForegroundColor Black ('converting {0} audio file ,progressing {1}% , {2} rest files' -f $index,$progeressPercent,$restCounts )

    #$audiofileName = $losslessFile.BaseName
    $audiofilePath = $losslessFile.FullName
    $audiofileExt = $losslessFile.Extension
    #$newfilename = $audiofileName+'.m4a'
    $newfilepath=$audiofilePath.SubString(0,$audiofilePath.Length-$audiofileExt.Length)+'.m4a'
    Write-Host -ForegroundColor Green ('audio path:'+ $audiofilePath)
    if($audiofileExt -eq '.wav'){
        $commandStr = ('qaac64.exe  '+$qaacParam+' "' +$audiofilePath +'" -o "' +$newfilepath+'"')
        Write-Host $commandStr
       Invoke-Expression $commandStr
    }elseif($audiofileExt -eq '.flac'){
        # 安装了flac解码的模块以后，qaac就可以直接接受flac文件了，所以不用通过cmd转码了和wav是一样的操作
       # Write-Host $audiofilePath
      #  cmd /c 'ffmpeg  -i $($a) qaac64.exe   --verbose --rate keep -v320 -q2 -loglevel quiet '
      #cmd /c ('ffmpeg -loglevel quiet -i "'+$audiofilePath +'" -f wav - | qaac64.exe '+$qaacParam+'  - -o "'+$newfilepath+'"')
      $commandStr = ('qaac64.exe  '+$qaacParam+' "' +$audiofilePath +'" -o "' +$newfilepath+'"')
      Write-Host $commandStr
     Invoke-Expression $commandStr
    }else{
            Write-Host -ForegroundColor Red 'Error'
    }


    if(Test-Path -LiteralPath  $newfilepath ){
        if($nodelete){
            Write-Host -BackgroundColor Yellow -ForegroundColor Green 'no-delete flag is open'
        } else{
            Write-Host -Verbose -ForegroundColor   Cyan 'convert finshed, deleting source audio file...'
            Remove-Item -Force -LiteralPath  $audiofilePath
        }
    } else
    {
        # 新文件没有创建成功，说明转换没有成功
        Write-Host -ForegroundColor Red 'convert file failed'
        
    }
    
}
Write-Host -ForegroundColor Green 'done'