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
    返回包含 `Type`、`Name`、`Path`、`Data` 的标准来源描述。
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
        Type = $type
        Name = $name
        Path = $resolvedPath
        Data = $sourceData
    }
}
