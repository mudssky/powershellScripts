<#
.example
downWithYoutubedl.ps1 -startNum 0 -paramStr '-i' -tool you-get

当使用you-get的时候，典型的使用方法是：downWith.ps1 -endNum 3 -paramStr '--playlist' -tool you-get

#>
param(
[int]$startNum = 0,
[int]$endNum=-1,
[string]$paramStr = '',
[string]$tool = 'youtube-dl',
[string]$url=''
)
$str =''
if($url){
$str =$url
}else{
$str = Get-Clipboard;
}

$linkList = $str -split '\n'
# endNum的默认值是-1，也就是不启用，此时endNum为默认值就是列表长度
if ($endNum -eq -1){
    $endNum = $linkList.Length
}
for($i=$startNum;$i -lt $endNum;$i+=1){
    Write-Host -ForegroundColor Green "downloading link $($linkList[$i]),$($i-$startNum+1) of $($endNum - $startNum) "
    if ($uploadDate){
    Invoke-Expression "$tool $paramStr    '$($linkList[$i])'   "
    }else{
    Invoke-Expression "$tool $paramStr  '$($linkList[$i])'"
    }
}

Write-Host -ForegroundColor Green "download complete"

