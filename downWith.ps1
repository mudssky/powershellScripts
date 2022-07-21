<#
.example
downWithYoutubedl.ps1 -startNum 0 -paramStr '-i' -tool you-get

��ʹ��you-get��ʱ�򣬵��͵�ʹ�÷����ǣ�downWith.ps1 -endNum 3 -paramStr '--playlist' -tool you-get

#>
param(
[int]$startNum = 0,
[int]$endNum=-1,
[string]$paramStr = '',
[string]$tool = 'yt-dlp',
[string]$url=''
)
$str =''
if($url){
$str =$url
}else{
$str = Get-Clipboard;
}

$linkList = $str -split '\n'
# endNum��Ĭ��ֵ��-1��Ҳ���ǲ����ã���ʱendNumΪĬ��ֵ�����б�����
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

