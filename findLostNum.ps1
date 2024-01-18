<#
.synopsis
下载网上的一些广播节目，生放送节目之类的，批量下载有时候视频的某几集被版权了，或者up主删掉了，导致缺少某几集，本脚本就是使用正则表达式匹配缺少的数字，并列出来，方便我们查找
.example
找寻数字1-500，也就是检查1-500集中缺少的集数 listExist把存在的也列出来，存在的用绿色，不存在用红色，对比鲜明
 findLostNum.ps1 -startNum 1 -endNum 500 -numPattern '第(\d+)回' -listExist
#>

param(
    #[Parameter(Mandatory=$true)][int]$startNum
    [int]$startNum = 0,
    [Parameter(Mandatory = $true)][int]$endNum,
    [string]$numPattern = '.*(\d+).*',
    [switch]$listExist
)
<#
function numStrToHalfWidth(){
 $convertTable=@{
 '０'=0;
 '１'=1;
 '２'=2;
 '３'=3;
 '４'=4;
 '５'=5;
 '６'=6;
 '７'=7;
 '９'=9;
 }
}
#>
$resultTable = @{}


$notMatch = New-Object -TypeName System.Collections.ArrayList
# 获取当前目录的所有子项目
$pwdItems = Get-ChildItem
$pwdItems.foreach{
    $filename = $_.Name
    if ($filename -cmatch $numPattern ) {
        $matchNum = [int]($Matches[1]);
        if (($matchNum -le $endNum) -and ($matchNum -ge $startNum )) {
            $resultTable[$matchNum] = $filename
        }
        else {
            Write-Host -ForegroundColor Yellow "matchnum exceed the range, matchNum: $matchNum ,filename: $filename"
        }
    }
    else {
        $null = $notMatch.Add($_)
    }
}
$startNum..$endNum |  ForEach-Object {
    if ($resultTable.ContainsKey($_)) {
        if ($listExist) {
            Write-Host -ForegroundColor Green "exists : $_ ,$($resultTable[$_]) "
        }
    }
    else {
        Write-Host -ForegroundColor Red "not found: $_ "

    }
}

"not match item:"
$notMatch


