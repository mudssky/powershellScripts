[CmdletBinding(SupportsShouldProcess)]
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
        Rename-Item  -LiteralPath $_.Name   -NewName $newName
    }
}