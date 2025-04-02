<#
.SYNOPSIS
检测字符串中使用的换行符类型。

.DESCRIPTION
此函数用于检测给定字符串中使用的换行符类型。
它可以识别 CRLF (`r`n) 和 LF (`n) 两种换行符。
如果未检测到换行符，则返回默认换行符。

.PARAMETER Content
必需参数。要检测换行符的字符串内容。

.PARAMETER DefaultLineBreak
可选参数。当未检测到换行符时返回的默认换行符。
默认值为 LF (`n)。

.EXAMPLE
Get-LineBreak -Content "Hello`nWorld"
返回 "`n"，因为输入字符串使用 LF 换行符。

.EXAMPLE
Get-LineBreak -Content "Hello`r`nWorld"
返回 "`r`n"，因为输入字符串使用 CRLF 换行符。

.EXAMPLE
Get-LineBreak -Content "HelloWorld" -DefaultLineBreak "`r`n"
返回 "`r`n"，因为输入字符串没有换行符，使用指定的默认值。

.OUTPUTS
返回检测到的换行符或默认换行符。

.NOTES
版本: 1.0
#>

function Get-LineBreak {
    param(
        # 检测的字符串内容
        [Parameter(Mandatory = $true)]
        [string]
        $Content,
        [string]
        $DefaultLineBreak = "`n"
    )

    if ($Content -match "`r`n") {
        Write-Debug "Detected line break: CRLF"
        return "`r`n"
    }
    elseif ($Content -match "`n") {
        Write-Debug "Detected line break: LF"
        return "`n"
    }
    else {
        return $DefaultLineBreak
    }
}

<#
.SYNOPSIS
将 JSONC 格式文件转换为标准 JSON 格式。

.DESCRIPTION
此函数可以将包含注释的 JSONC 文件转换为标准的 JSON 格式。
它会移除所有的单行注释 (//) 和多行注释 (/* */), 以及尾随逗号。

.PARAMETER Path
必需参数。指定要转换的 JSONC 文件的路径。

.PARAMETER OutputFilePath
可选参数。指定输出 JSON 文件的路径。如果不指定，函数将返回转换后的 JSON 字符串。

.EXAMPLE
Convert-JsoncToJson -Path "config.jsonc"
将 config.jsonc 文件转换为 JSON 并返回转换后的内容。

.EXAMPLE
Convert-JsoncToJson -Path "config.jsonc" -OutputFilePath "config.json"
将 config.jsonc 文件转换为 JSON 并保存到 config.json。

.OUTPUTS
如果指定了 OutputFilePath，则输出到文件并显示成功消息。
如果未指定 OutputFilePath，则返回转换后的 JSON 字符串。

.NOTES
版本: 1.0
#>

function Convert-JsoncToJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputFilePath
    )

    # 读取JSONC文件内容
    $jsoncContent = Get-Content -Path $Path -Raw

    # 移除单行注释 (//...)
    $jsonContent = $jsoncContent -replace '(?m)\s*//.*$', ''

    # 移除多行注释 (/*...*/)
    $jsonContent = $jsonContent -replace '(?s)/\*.*?\*/', ''

    # 移除尾随逗号
    $jsonContent = $jsonContent -replace ',\s*([}\]])', '$1'

    # 转换内容为JSON对象以验证有效性
    if ( -not (Test-Json -Json $jsonContent -ErrorAction SilentlyContinue)) {
        Write-Debug '目前7.5.0版本，Test-Json无法处理包含$schema的json'
        Write-Error "转换失败: $_"
    }

    # 输出结果
    if ($OutputFilePath) {
        $jsonContent | Out-File -FilePath $OutputFilePath -Encoding utf8
        Write-Host "转换成功，结果已保存到: $OutputFilePath"
    }
    else {
        $jsonContent
    }
}


Export-ModuleMember -Function *