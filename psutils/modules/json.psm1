Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    读取 JSON 文件为 hashtable。

.DESCRIPTION
    封装 `ConvertFrom-Json -AsHashtable` 的常用读取逻辑，并在解析失败时带上调用方提供的标签，
    便于配置脚本输出更明确的错误来源。

.PARAMETER Path
    JSON 文件路径。

.PARAMETER Label
    错误提示中使用的文件标签；为空时使用路径本身。

.PARAMETER Depth
    JSON 解析深度，默认 100。

.OUTPUTS
    hashtable。JSON 顶层对象解析后的键值表。
#>
function Read-JsonHashtableFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [AllowEmptyString()]
        [string]$Label = '',

        [int]$Depth = 100
    )

    $displayName = if ([string]::IsNullOrWhiteSpace($Label)) { $Path } else { $Label }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable -Depth $Depth
    }
    catch {
        throw "解析 ${displayName} 失败：$($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    原子写入 JSON 文件。

.DESCRIPTION
    先写入同目录临时文件，再通过 `Move-Item -Force` 替换目标，避免写入过程中留下半截 JSON。
    调用方可通过 `ShouldProcess` 参数把外层脚本的 `$PSCmdlet` 传入，从而继承 WhatIf/Confirm 语义。

.PARAMETER Path
    目标 JSON 文件路径。

.PARAMETER Value
    要序列化为 JSON 的对象。

.PARAMETER Depth
    JSON 序列化深度，默认 100。

.PARAMETER TempPrefix
    临时文件名前缀。

.PARAMETER ShouldProcess
    可选的外层 cmdlet 对象，用于执行 ShouldProcess 检查。

.PARAMETER Action
    ShouldProcess 使用的动作描述。

.OUTPUTS
    string。目标文件路径。
#>
function Write-JsonFileAtomic {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Value,

        [int]$Depth = 100,

        [ValidateNotNullOrEmpty()]
        [string]$TempPrefix = 'json',

        [AllowNull()]
        [object]$ShouldProcess = $null,

        [ValidateNotNullOrEmpty()]
        [string]$Action = 'Write JSON file'
    )

    $directoryPath = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directoryPath)) {
        $directoryPath = (Get-Location).Path
    }

    if (-not (Test-Path -LiteralPath $directoryPath)) {
        New-Item -ItemType Directory -Path $directoryPath -Force | Out-Null
    }

    $tempFilePath = Join-Path $directoryPath ("{0}.{1}.tmp" -f $TempPrefix, [System.Guid]::NewGuid().ToString('N'))
    $json = $Value | ConvertTo-Json -Depth $Depth
    $shouldWrite = if ($null -ne $ShouldProcess -and $ShouldProcess.PSObject.Methods.Name -contains 'ShouldProcess') {
        $ShouldProcess.ShouldProcess($Path, $Action)
    }
    else {
        $PSCmdlet.ShouldProcess($Path, $Action)
    }

    if ($shouldWrite) {
        try {
            Set-Content -LiteralPath $tempFilePath -Value $json -Encoding utf8NoBOM
            Move-Item -LiteralPath $tempFilePath -Destination $Path -Force
        }
        finally {
            if (Test-Path -LiteralPath $tempFilePath) {
                Remove-Item -LiteralPath $tempFilePath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return $Path
}

<#
.SYNOPSIS
    生成集合去重使用的稳定键。

.DESCRIPTION
    字典和列表按压缩 JSON 生成键；标量转为字符串；空值返回固定文本。
    适用于合并配置列表时判断结构化项是否重复。

.PARAMETER Value
    待生成稳定键的值。

.PARAMETER Depth
    结构化值转 JSON 时使用的深度，默认 100。

.OUTPUTS
    string。稳定的比较键。
#>
function Get-StableJsonKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Value,

        [int]$Depth = 100
    )

    if ($null -eq $Value) {
        return '<null>'
    }

    $isDictionary = $Value -is [System.Collections.IDictionary]
    $isList = $Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [System.Collections.IDictionary]
    if ($isDictionary -or $isList) {
        return ($Value | ConvertTo-Json -Depth $Depth -Compress)
    }

    return [string]$Value
}

Export-ModuleMember -Function @(
    'Read-JsonHashtableFile'
    'Write-JsonFileAtomic'
    'Get-StableJsonKey'
)
