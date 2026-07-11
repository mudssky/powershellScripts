<#
.example
downWithYoutubedl.ps1 -startNum 0 -paramStr '-i' 
#>
param(
    [int]$startNum = 0,
    [int]$endNum = -1,
    [string]$paramStr = ''
)

$str = Get-Clipboard;
$linkList = $str.Split('')
# endNum��Ĭ��ֵ��-1��Ҳ���ǲ����ã���ʱendNumΪĬ��ֵ�����б�����
if ($endNum -eq -1) {
    $endNum = $linkList.Length
}
for ($i = $startNum; $i -lt $endNum; $i += 1) {
    Write-Host -ForegroundColor Green "downloading link $($linkList[$i]),$($i-$startNum+1) of $($endNum - $startNum) "
    youtube-dl $paramStr  $linkList[$i]
}

Write-Host -ForegroundColor Green "download complete"

