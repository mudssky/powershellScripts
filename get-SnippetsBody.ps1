#!/usr/bin/env pwsh

<#
.SYNOPSIS
    生成代码片段主体内容的脚本

.DESCRIPTION
    该脚本用于处理剪贴板中的文本内容，将其转换为适合代码片段的格式。
    主要功能包括转义双引号、处理换行符，并生成符合JSON格式的字符串数组。
    处理后的结果会自动复制回剪贴板。

.EXAMPLE
    .\get-SnippetsBody.ps1
    处理剪贴板中的文本并生成代码片段格式

.NOTES
    需要psutils模块
    自动检测文本中的换行符类型
    处理双引号转义以符合JSON格式
    结果自动复制到剪贴板
#>

function Convert-DoubleQuotes {
    param (
        [string]$inputString
    )

    # 使用 -replace 运算符替换双引号为转义的双引号
    return $inputString -replace '"', '\"'
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Resolve-Path -Path $PSScriptRoot/psutils)

function Get-SnippetsBody {
    [CmdletBinding()]
    param (
		
    )
	
    begin {
		
    }
	
    process {

        $content = Get-Clipboard -Raw
        $lineBreak = Get-LineBreak -Content $content -Debug

        $bodyList = ($content ).Split($lineBreak) | ForEach-Object { '"' + (Convert-DoubleQuotes -inputString $_) + '"' }
        $res = $bodyList -join (',' + $lineBreak)
        $res
        Set-Clipboard -Value $res

    }
	
    end {
		
    }
}



Get-SnippetsBody
