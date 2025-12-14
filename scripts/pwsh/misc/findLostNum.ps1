#!/usr/bin/env pwsh

<#
.SYNOPSIS
    查找缺失集数的脚本

.DESCRIPTION
    该脚本用于检查批量下载的视频、音频或其他文件中缺失的集数。
    当下载网络节目、广播节目或连续剧时，某些集数可能因版权问题或被删除而缺失。
    脚本使用正则表达式匹配文件名中的数字，找出指定范围内缺失的集数。

.PARAMETER startNum
    开始检查的数字，默认为0

.PARAMETER endNum
    结束检查的数字（必填参数）

.PARAMETER numPattern
    用于匹配文件名中数字的正则表达式模式，默认为'.*(\\d+).*'

.PARAMETER listExist
    开关参数，如果指定则同时列出存在的集数（绿色显示）和缺失的集数（红色显示）

.EXAMPLE
    .\findLostNum.ps1 -startNum 1 -endNum 500 -numPattern '第(\\d+)回' -listExist
    检查第1回到第500回中缺少的集数，同时显示存在和缺失的集数

.EXAMPLE
    .\findLostNum.ps1 -endNum 100
    检查0到100中缺失的数字，使用默认的数字匹配模式

.EXAMPLE
    .\findLostNum.ps1 -startNum 1 -endNum 50 -numPattern 'EP(\\d+)'
    检查EP1到EP50格式的文件中缺失的集数

.NOTES
    支持自定义正则表达式模式匹配不同的文件命名格式
    使用颜色区分存在（绿色）和缺失（红色）的集数
    适用于检查连续编号的文件系列
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


$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
