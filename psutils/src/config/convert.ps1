Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    将任意配置对象规范化为 hashtable。

.DESCRIPTION
    允许上层调用方传入 `hashtable`、`PSCustomObject` 或其他带属性对象，
    统一转换为便于后续合并的键值表。

.PARAMETER InputObject
    待转换的配置对象；传入 `$null` 时返回空表。

.OUTPUTS
    hashtable
    返回浅拷贝后的键值表，避免直接修改调用方原对象。
#>
function ConvertTo-ConfigHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return @{}
    }

    if ($InputObject -is [hashtable]) {
        return @{} + $InputObject
    }

    $result = @{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }

    return $result
}

<#
.SYNOPSIS
    将配置键名转换为下划线风格。

.DESCRIPTION
    统一把 PowerShell 参数名、短横线参数名和普通键名转换为小写下划线格式，
    让 CLI 参数、frontmatter 与默认配置可以共享同一套键名。

.PARAMETER Name
    原始配置键名。

.OUTPUTS
    string
    返回转换后的配置键名。
#>
function ConvertTo-ConfigKeyName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $withUnderscore = $Name -replace '-', '_'
    $withUnderscore = $withUnderscore -creplace '([a-z0-9])([A-Z])', '$1_$2'
    return $withUnderscore.ToLowerInvariant()
}

<#
.SYNOPSIS
    将 PowerShell CLI 参数转换为配置表。

.DESCRIPTION
    仅保留调用方显式传入且有意义的参数，跳过空字符串、空值和指定排除键。
    参数名会转换为下划线风格，便于参与 `Resolve-ConfigSources` 合并。

.PARAMETER Parameters
    `$PSBoundParameters` 或其他 hashtable 参数集合。

.PARAMETER ExcludeKeys
    不应进入配置合并的参数名。

.OUTPUTS
    hashtable
    返回可合并的配置键值。
#>
function ConvertFrom-ConfigCliParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parameters,

        [string[]]$ExcludeKeys = @()
    )

    $excluded = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $ExcludeKeys) {
        $excluded.Add($key) | Out-Null
    }

    $result = @{}
    foreach ($entry in $Parameters.GetEnumerator()) {
        if ($excluded.Contains([string]$entry.Key)) {
            continue
        }

        if ($null -eq $entry.Value) {
            continue
        }

        if ($entry.Value -is [string] -and [string]::IsNullOrWhiteSpace($entry.Value)) {
            continue
        }

        $result[(ConvertTo-ConfigKeyName -Name ([string]$entry.Key))] = $entry.Value
    }

    return $result
}

<#
.SYNOPSIS
    规范化单个配置来源描述。

.DESCRIPTION
    统一补全来源名称、相对路径解析和附带数据，
    让后续读取逻辑只处理一种稳定结构。

.PARAMETER Source
    上层传入的原始来源描述，至少包含 `Type`。

.PARAMETER BasePath
    用于解析相对 `Path` 的基准目录。

.OUTPUTS
    hashtable
    返回包含 `Type`、`Name`、`Path`、`Data`、`ExcludeKeys` 的标准来源描述。
#>
function Get-ConfigSourceDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Source,

        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $sourcePath = if ($Source.ContainsKey('Path')) { [string]$Source['Path'] } else { '' }
    $sourceName = if ($Source.ContainsKey('Name')) { [string]$Source['Name'] } else { '' }
    $sourceData = if ($Source.ContainsKey('Data')) { $Source['Data'] } else { $null }
    $excludeKeys = if ($Source.ContainsKey('ExcludeKeys')) { [string[]]$Source['ExcludeKeys'] } else { @() }

    if (-not [string]::IsNullOrWhiteSpace($sourcePath) -and -not [System.IO.Path]::IsPathRooted($sourcePath)) {
        $resolvedPath = Join-Path $BasePath $sourcePath
    }
    else {
        $resolvedPath = $sourcePath
    }

    $type = [string]$Source.Type
    $name = if ([string]::IsNullOrWhiteSpace($sourceName)) {
        if ($type -eq 'ProcessEnv') {
            'ProcessEnv'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($resolvedPath)) {
            [System.IO.Path]::GetFileName($resolvedPath)
        }
        else {
            $type
        }
    }
    else {
        [string]$Source.Name
    }

    return @{
        Type        = $type
        Name        = $name
        Path        = $resolvedPath
        Data        = $sourceData
        ExcludeKeys = $excludeKeys
    }
}
