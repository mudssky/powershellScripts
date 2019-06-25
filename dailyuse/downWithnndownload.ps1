<#
.example
downWithYoutubedl.ps1 -startNum 0 -paramStr '-i' 
#>
param(
[int]$startNum = 0,
[int]$endNum=-1,
[string]$paramStr = ''
)

$str = Get-Clipboard;
$linkList = $str.Split('')
# endNum的默认值是-1，也就是不启用，此时endNum为默认值就是列表长度
if ($endNum -eq -1){
    $endNum = $linkList.Length
}
for($i=$startNum;$i -lt $endNum;$i+=1){
    Write-Host -ForegroundColor Green "downloading link $($linkList[$i]),$($i-$startNum+1) of $($endNum - $startNum) "
    nndownload $paramStr  $linkList[$i] -o '{title}-{id}.{ext}'
}

Write-Host -ForegroundColor Green "download complete"

