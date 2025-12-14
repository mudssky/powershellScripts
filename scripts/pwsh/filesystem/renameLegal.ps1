#!/usr/bin/env pwsh

<#
.SYNOPSIS
    文件名合法化重命名脚本

.DESCRIPTION
    该脚本用于将文件名中的非法字符替换为合法字符，使文件名符合Windows文件系统要求。
    支持正向转换（非法字符转为合法字符）和反向转换（恢复原始字符）。
    主要处理Windows文件名中不允许的特殊字符。

.PARAMETER reverse
    开关参数，如果指定则执行反向转换，将之前替换的合法字符恢复为原始字符

.EXAMPLE
    .\renameLegal.ps1
    将当前目录下文件名中的非法字符替换为合法字符

.EXAMPLE
    .\renameLegal.ps1 -reverse
    将之前替换的合法字符恢复为原始字符

.NOTES
    支持WhatIf参数预览操作结果
    处理Windows文件名非法字符如：< > : " | ? * 等
    使用字符映射表进行双向转换
    确保文件名符合Windows文件系统规范
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$reverse
)

<#
.SYNOPSIS
    获取一个和输入哈希表key和value调换位置的哈希表
.DESCRIPTION
    Long description
.EXAMPLE
    PS C:\> Get-ReversedMap -inputMap $xxxMap
    Explanation of what the example does
.INPUTS
    Inputs (if any)
.OUTPUTS
    Output (if any)
.NOTES
    General notes
#>
function Get-ReversedMap() {
    param (
        $inputMap
    )
    $reversedMap = @{}
    foreach ($key in $inputMap.Keys) {
        $reversedMap[$inputMap[$key]] = $key
    }
    return $reversedMap
}
# 对windows的非法字符进行转换，利用全角字符替换半角字符
# $replaceTableMap = @{
#     '\' = '、';
#     '/' = '／';
#     ':' = '：';
#     '?' = '？';
#     '<' = '《';
#     '>' = '》';
#     '|' = '｜';
#     '*' = '＊';
#     '"' = '“';
# }

# 如果反向转换的话，就会调用把map反向的函数
# if ($reverse) {
#     $replaceTableMap = Get-ReversedMap -inputMap $replaceTableMap
# }

# Get-ReversedMap -inputMap $replaceTableMap
Get-ChildItem -File | ForEach-Object {
    # $newName = ''
    # $nameCharArr = $_.Name.ToCharArray()
    # for ($i = 0; $i -lt $nameCharArr.Length; $i++) {
    #     $curChar = $nameCharArr[$i]
    #     Write-Host -ForegroundColor Yellow    $curChar
    #     if ($curChar -in $replaceTableMap.Keys) {
    #         Write-Host -ForegroundColor Yellow $curChar
    #         $newName += $replaceTableMap[$curChar]
    #     }
    #     else {
    #         $newName += $curChar
    #     }
    # };
    $newName = rename-legal.exe replace $_.Name
    # Write-Host -ForegroundColor Green ('原名字是{0},新名字是:{1}' -f $_.Name, $newName)
    if ($newName -ne $_.Name) {
        if ($PSCmdlet.ShouldProcess($_.Name, "重命名为 $newName")) { Rename-Item -LiteralPath $_.Name -NewName $newName }
    }
}
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
