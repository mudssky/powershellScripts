<#
 .SYNOPSIS
 使用yt-dlp下载视频
.DESCRIPTION
使用yt-dlp下载视频
.EXAMPLE
指定下载工具
downWithYoutubedl.ps1 -startNum 0 -paramStr '-i' -tool you-get
.EXAMPLE 
下载前3个
downWith.ps1 -endNum 3 -paramStr '--playlist' -tool you-get
.EXAMPLE

带有cookie下载
downWith.ps1  -paramStr  '--cookies-from-browser chrome'
或者
downWith.ps1  -withCookie
#>
[CmdletBinding()]
param(
    [int]$startNum = 0,
    [int]$endNum = -1,
    [string]$paramStr = '',
    [string]$tool = 'yt-dlp',
    [string]$url = '',
    [switch]$withCookie
)
$str = ''
if ($url) {
    $str = $url
}
else {
    $str = Get-Clipboard;
}

$linkList = $str -split '\n'
if ($endNum -eq -1) {
    $endNum = $linkList.Length
}

if ($withCookie) {
    $paramStr += ' --cookies-from-browser chrome'
}

for ($i = $startNum; $i -lt $endNum; $i += 1) {
    Write-Host -ForegroundColor Green "downloading link $($linkList[$i]),$($i-$startNum+1) of $($endNum - $startNum) "
    Invoke-Expression "$tool $paramStr    '$($linkList[$i])'   "
}

Write-Host -ForegroundColor Green "download complete"

