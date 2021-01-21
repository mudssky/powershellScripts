<#
.example
tsCompress.ps1 -deleteSourceFile -paramStr '-vcodec libx264 -crf 23  -preset veryfast  -acodec copy'
在目标目录下执行就会递归查找录制的flv和ts文件进行压制。
paramStr指定ffmepg压制的参数
deleteSourceFile选项加上，就可以自动删除源文件。

#>


param(
[string]$paramStr='-vcodec hevc -crf 23  -preset slow  -acodec copy ',
[string]$targetPath='.',
[switch]$deleteSourceFile
)


$tsList = ls  -Recurse -LiteralPath $($targetPath) | where{($_.Extension -eq '.flv') -or ($_.Extension -eq '.ts') }

$tsList | foreach{
$oldName =  $_.FullName
$extLength = $_.Extension.Length
$newName = $oldName.Substring(0,$oldName.length-$extLength)+'.mp4'
$excuteStr = "ffmpeg -i '$($oldName)'  $paramStr '$($newName)' "
Write-Host -ForegroundColor Green ('[compress]'+$excuteStr)
Invoke-Expression $excuteStr

if ($deleteSourceFile){
    rm -LiteralPath $oldName
}
Write-Host -ForegroundColor Yellow "deleteSourceFile completed： $oldName"
}


