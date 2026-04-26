Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    严格读取 dotenv 风格配置文件。

.DESCRIPTION
    仅接受 `KEY=VALUE` 形式的非空非注释行；
    遇到非法行时立即抛错，避免静默吞掉配置问题。

.PARAMETER Path
    要读取的 env 文件路径。

.OUTPUTS
    hashtable
    返回按原始键名保存的键值表。
#>
function Read-ConfigEnvFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $pairs = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
            continue
        }

        if ($line -notmatch '^\s*([^=]+)=(.*)$') {
            throw '无效 env 行'
        }

        $pairs[$Matches[1].Trim()] = $Matches[2].Trim()
    }

    return $pairs
}

<#
.SYNOPSIS
    读取 PowerShell data file 配置。

.DESCRIPTION
    使用 PowerShell 原生 `Import-PowerShellDataFile` 读取 `.psd1`，
    并转换成普通 hashtable，供配置来源合并器消费。

.PARAMETER Path
    `.psd1` 文件路径。

.OUTPUTS
    hashtable
    返回 data file 中声明的键值。
#>
function Read-ConfigPowerShellDataFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "配置文件不存在: $Path"
    }

    return ConvertTo-ConfigHashtable -InputObject (Import-PowerShellDataFile -LiteralPath $Path)
}

<#
.SYNOPSIS
    转换 Markdown frontmatter 标量值。

.DESCRIPTION
    将简单 YAML 子集中的布尔值、整数和引号字符串转换为 PowerShell 值；
    非特殊格式保持字符串，避免引入完整 YAML 解析依赖。

.PARAMETER Value
    frontmatter 中冒号右侧的原始值。

.OUTPUTS
    object
    返回转换后的标量值。
#>
function ConvertFrom-ConfigFrontMatterScalar {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    $rawValue = $Value.Trim()
    if ($rawValue -match '^(true|false)$') {
        return [bool]::Parse($rawValue)
    }

    if ($rawValue -match '^-?\d+$') {
        return [int]$rawValue
    }

    $isSingleQuoted = $rawValue.Length -ge 2 -and $rawValue.StartsWith("'") -and $rawValue.EndsWith("'")
    $isDoubleQuoted = $rawValue.Length -ge 2 -and $rawValue.StartsWith('"') -and $rawValue.EndsWith('"')
    if ($isSingleQuoted -or $isDoubleQuoted) {
        return $rawValue.Substring(1, $rawValue.Length - 2)
    }

    return $rawValue
}

<#
.SYNOPSIS
    读取 Markdown frontmatter 与正文。

.DESCRIPTION
    解析文件开头的简单 frontmatter。第一版仅支持 `key: value`、布尔值、整数和字符串。
    返回 Metadata 与 Content，供配置合并和 prompt loader 复用。

.PARAMETER Path
    Markdown 文件路径。

.OUTPUTS
    PSCustomObject
    返回包含 `Metadata` 与 `Content` 的对象。
#>
function Read-ConfigMarkdownFrontMatter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "配置文件不存在: $Path"
    }

    $lines = @(Get-Content -LiteralPath $Path)
    $metadata = @{}

    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') {
        return [pscustomobject]@{
            Metadata = $metadata
            Content  = ($lines -join [Environment]::NewLine)
        }
    }

    $endIndex = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -eq '---') {
            $endIndex = $index
            break
        }

        if ($lines[$index] -notmatch '^\s*([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)\s*$') {
            $lineNumber = $index + 1
            throw "无效 Markdown frontmatter 行: ${Path}:$lineNumber"
        }

        $key = ConvertTo-ConfigKeyName -Name $Matches[1]
        $metadata[$key] = ConvertFrom-ConfigFrontMatterScalar -Value $Matches[2]
    }

    if ($endIndex -lt 0) {
        throw "Markdown frontmatter 缺少结束标记: $Path"
    }

    $bodyLines = if (($endIndex + 1) -lt $lines.Count) {
        $lines[($endIndex + 1)..($lines.Count - 1)]
    }
    else {
        @()
    }

    return [pscustomobject]@{
        Metadata = $metadata
        Content  = ($bodyLines -join [Environment]::NewLine)
    }
}
