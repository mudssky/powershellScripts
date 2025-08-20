[CmdletBinding()]
param (
    [ValidateSet('vscode', 'trae')]
    [string]$Mode = 'vscode'
)

<#
.SYNOPSIS
    提取JSONC文件的内部内容

.DESCRIPTION
    从JSONC文件或字符串中提取大括号内的内容，去除外层的空白字符，
    并确保内容以逗号结尾，用于合并多个JSONC文件的设置。

.PARAMETER Path
    JSONC文件的路径。如果提供此参数，将从文件读取内容。

.PARAMETER JsoncString
    JSONC格式的字符串。如果未提供Path参数，将使用此字符串。

.OUTPUTS
    System.String
    返回提取的内部JSON内容，确保以逗号结尾

.EXAMPLE
    Get-JsoncInnerContent -Path "settings.jsonc"
    从settings.jsonc文件中提取内部内容

.EXAMPLE
    Get-JsoncInnerContent -JsoncString '{"key": "value"}'
    从字符串中提取内部内容，返回 '"key": "value",'

.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 用于合并多个VSCode设置文件
#>
function Get-JsoncInnerContent {
    [CmdletBinding()]
    param (
        [string]$Path,
        [string]$JsoncString
    )

    if ($Path) {
        $JsoncString = Get-Content -Raw  $Path
    }
    # (?s) 的作用是开启.匹配所有字符的模式，后面.*?关闭贪婪模式，这样使得可以移除括号附近的空白字符
    $isMatch = $JsoncString -match '(?s)^[^{}]*{\s*(.*?)\s*}[^{}]*$'
    if ($isMatch) {
        $innerString = $matches[1]
        # 添加尾部逗号
        if (-not $innerString.EndsWith(',')) {
            $innerString += ',' 
        }
        return $innerString
    }
    else {
        throw "match failed: $Path,$JsoncString"
    }
    
}

$settingsList = [System.Collections.Generic.List[string]]::new()
switch ($Mode) {
    'vscode' { 
        Get-ChildItem -Recurse  -Filter *.jsonc   -Path $PSScriptRoot/settings | ForEach-Object {
            $jsoncString = Get-JsoncInnerContent -Path $_.FullName;
            $settingsList.Add($jsoncString)
        }
    }
    'trae' {
     
        Get-ChildItem -Recurse  -Filter *.jsonc   -Path $PSScriptRoot/settings | ForEach-Object {
            $jsoncString = Get-JsoncInnerContent -Path $_.FullName;
            $settingsList.Add($jsoncString)
        } 
    }
    Default {}
}


$newSettings = ($settingsList -join "`n").TrimEnd(",")
"{$newSettings}" | Set-Content -Path $PSScriptRoot/settings.jsonc