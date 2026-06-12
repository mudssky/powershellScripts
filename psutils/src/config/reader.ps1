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

<#
.SYNOPSIS
    移除 SSH config 行中的行内注释。

.DESCRIPTION
    仅在不处于单引号或双引号包裹时，把 `#` 之后的内容视为注释。
    该 helper 服务于轻量 SSH client config 读取器，不尝试完整复刻 OpenSSH parser。

.PARAMETER Line
    原始 SSH config 单行文本。

.OUTPUTS
    string
    返回移除注释后的行文本。
#>
function Remove-ConfigSshInlineComment {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Line
    )

    $inSingleQuote = $false
    $inDoubleQuote = $false
    for ($index = 0; $index -lt $Line.Length; $index++) {
        $char = $Line[$index]
        if ($char -eq "'" -and -not $inDoubleQuote) {
            $inSingleQuote = -not $inSingleQuote
            continue
        }

        if ($char -eq '"' -and -not $inSingleQuote) {
            $inDoubleQuote = -not $inDoubleQuote
            continue
        }

        if ($char -eq '#' -and -not $inSingleQuote -and -not $inDoubleQuote) {
            return $Line.Substring(0, $index)
        }
    }

    return $Line
}

<#
.SYNOPSIS
    将 SSH config 指令行拆成关键字和值。

.DESCRIPTION
    支持 OpenSSH 常见的 `Keyword value` 与 `Keyword=value` 两种写法。
    空行、注释行或无法识别的行返回 `$null`，由调用方跳过。

.PARAMETER Line
    已移除注释的 SSH config 单行文本。

.OUTPUTS
    PSCustomObject
    返回包含 `Keyword`、`Value` 的对象；无有效指令时返回 `$null`。
#>
function Split-ConfigSshDirective {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Line
    )

    $trimmedLine = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
        return $null
    }

    $equalsIndex = $trimmedLine.IndexOf('=')
    if ($equalsIndex -gt 0) {
        $keyword = $trimmedLine.Substring(0, $equalsIndex).Trim()
        $value = $trimmedLine.Substring($equalsIndex + 1).Trim()
    }
    elseif ($trimmedLine -match '^(?<keyword>\S+)\s+(?<value>.*)$') {
        $keyword = $Matches.keyword
        $value = $Matches.value.Trim()
    }
    else {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($keyword)) {
        return $null
    }

    return [pscustomobject]@{
        Keyword = $keyword
        Value   = $value
    }
}

<#
.SYNOPSIS
    拆分 SSH config 参数列表。

.DESCRIPTION
    按空白拆分参数，并保留单引号或双引号包裹中的空白内容。
    当前用于解析 `Host` pattern 列表。

.PARAMETER Value
    原始参数文本。

.OUTPUTS
    string[]
    返回参数数组。
#>
function Split-ConfigSshArguments {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    $arguments = New-Object 'System.Collections.Generic.List[string]'
    foreach ($match in [regex]::Matches($Value, '("[^"]*"|''[^'']*''|\S+)')) {
        $argument = $match.Value
        if (
            ($argument.Length -ge 2) -and
            (($argument.StartsWith('"') -and $argument.EndsWith('"')) -or ($argument.StartsWith("'") -and $argument.EndsWith("'")))
        ) {
            $argument = $argument.Substring(1, $argument.Length - 2)
        }

        if (-not [string]::IsNullOrWhiteSpace($argument)) {
            $arguments.Add($argument) | Out-Null
        }
    }

    return $arguments.ToArray()
}

<#
.SYNOPSIS
    判断 Host pattern 是否适合作为启动器入口。

.DESCRIPTION
    启动器会执行 `ssh <Host>`，因此只接受单个明确 Host 名称。
    多 pattern、通配符、取反 pattern 或空白名称都不作为可启动入口。

.PARAMETER Patterns
    `Host` 指令后的 pattern 列表。

.OUTPUTS
    bool
    返回该 Host block 是否适合作为直接启动入口。
#>
function Test-ConfigSshLaunchCandidatePattern {
    [CmdletBinding()]
    param(
        [string[]]$Patterns
    )

    if ($null -eq $Patterns -or $Patterns.Count -ne 1) {
        return $false
    }

    $pattern = [string]$Patterns[0]
    if ([string]::IsNullOrWhiteSpace($pattern)) {
        return $false
    }

    return ($pattern -notmatch '[\s\*\?!]')
}

<#
.SYNOPSIS
    创建 SSH config Host block 对象。

.DESCRIPTION
    将解析过程中收集到的字段规范化为稳定对象，供启动器与测试复用。

.PARAMETER SourcePath
    SSH config 文件路径。

.PARAMETER LineNumber
    `Host` 指令所在行号。

.PARAMETER Patterns
    `Host` 指令声明的 pattern 列表。

.PARAMETER Values
    当前 Host block 中识别到的字段表。

.OUTPUTS
    PSCustomObject
    返回结构化 Host block。
#>
function New-ConfigSshHostBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [int]$LineNumber,

        [string[]]$Patterns = @(),

        [hashtable]$Values = @{}
    )

    $isLaunchCandidate = Test-ConfigSshLaunchCandidatePattern -Patterns $Patterns
    $hostName = if ($Patterns.Count -eq 1) { $Patterns[0] } else { ($Patterns -join ' ') }

    return [pscustomobject]@{
        SourcePath        = $SourcePath
        LineNumber        = $LineNumber
        Host              = $hostName
        HostPatterns      = @($Patterns)
        IsLaunchCandidate = $isLaunchCandidate
        HostName          = Get-ConfigValue -Values $Values -Name 'HostName'
        User              = Get-ConfigValue -Values $Values -Name 'User'
        Port              = Get-ConfigValue -Values $Values -Name 'Port'
        RemoteCommand     = Get-ConfigValue -Values $Values -Name 'RemoteCommand'
        RequestTTY        = Get-ConfigValue -Values $Values -Name 'RequestTTY'
    }
}

<#
.SYNOPSIS
    读取 OpenSSH client config 中的 Host block。

.DESCRIPTION
    解析单个 SSH config 文件中的 `Host` block，并提取启动器需要的字段。
    该函数不处理 `Include`、`Match` 条件块或 OpenSSH 的完整继承语义；
    真实连接行为仍交给 `ssh <Host>` 自身解析。

.PARAMETER Path
    SSH client config 文件路径。

.OUTPUTS
    PSCustomObject[]
    返回结构化 Host block 数组。
#>
function Read-ConfigSshClientConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "配置文件不存在: $Path"
    }

    $recognizedKeys = @{
        hostname      = 'HostName'
        user          = 'User'
        port          = 'Port'
        remotecommand = 'RemoteCommand'
        requesttty    = 'RequestTTY'
    }

    $blocks = New-Object 'System.Collections.Generic.List[object]'
    $currentPatterns = $null
    $currentValues = @{}
    $currentLineNumber = 0
    $lineNumber = 0

    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $lineNumber++
        $line = Remove-ConfigSshInlineComment -Line $rawLine
        $directive = Split-ConfigSshDirective -Line $line
        if ($null -eq $directive) {
            continue
        }

        $keyword = $directive.Keyword.ToLowerInvariant()
        if ($keyword -eq 'host') {
            if ($null -ne $currentPatterns) {
                $blocks.Add((New-ConfigSshHostBlock -SourcePath $Path -LineNumber $currentLineNumber -Patterns $currentPatterns -Values $currentValues)) | Out-Null
            }

            $currentPatterns = @(Split-ConfigSshArguments -Value $directive.Value)
            $currentValues = @{}
            $currentLineNumber = $lineNumber
            continue
        }

        if ($keyword -eq 'match') {
            if ($null -ne $currentPatterns) {
                $blocks.Add((New-ConfigSshHostBlock -SourcePath $Path -LineNumber $currentLineNumber -Patterns $currentPatterns -Values $currentValues)) | Out-Null
            }

            $currentPatterns = $null
            $currentValues = @{}
            $currentLineNumber = 0
            continue
        }

        if ($null -eq $currentPatterns) {
            continue
        }

        if ($recognizedKeys.ContainsKey($keyword)) {
            $currentValues[$recognizedKeys[$keyword]] = $directive.Value
        }
    }

    if ($null -ne $currentPatterns) {
        $blocks.Add((New-ConfigSshHostBlock -SourcePath $Path -LineNumber $currentLineNumber -Patterns $currentPatterns -Values $currentValues)) | Out-Null
    }

    return $blocks.ToArray()
}
