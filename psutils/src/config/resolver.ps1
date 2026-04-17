Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    读取单个配置来源的值集合。

.DESCRIPTION
    根据来源类型分派到 hashtable、进程环境变量、env 文件或 JSON 文件读取逻辑，
    并统一返回可合并的键值表。

.PARAMETER Source
    标准化后的配置来源描述。

.PARAMETER ErrorOnMissing
    为真时，缺失的文件来源会直接抛错。

.OUTPUTS
    hashtable
    返回该来源解析出的配置键值。
#>
function Read-ConfigSourceValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Source,

        [switch]$ErrorOnMissing
    )

    switch ($Source.Type) {
        'Hashtable' {
            return ConvertTo-ConfigHashtable -InputObject $Source.Data
        }
        'ProcessEnv' {
            $values = @{}
            Get-ChildItem Env: | ForEach-Object {
                $values[$_.Name] = $_.Value
            }

            return $values
        }
        'EnvFile' {
            if (-not (Test-Path -LiteralPath $Source.Path)) {
                if ($ErrorOnMissing) {
                    throw "配置文件不存在: $($Source.Path)"
                }

                return @{}
            }

            return Read-ConfigEnvFile -Path $Source.Path
        }
        'JsonFile' {
            if (-not (Test-Path -LiteralPath $Source.Path)) {
                if ($ErrorOnMissing) {
                    throw "配置文件不存在: $($Source.Path)"
                }

                return @{}
            }

            $rawObject = Get-Content -LiteralPath $Source.Path -Raw | ConvertFrom-Json
            return ConvertTo-ConfigHashtable -InputObject $rawObject
        }
        default {
            throw "不支持的配置来源类型: $($Source.Type)"
        }
    }
}

<#
.SYNOPSIS
    按优先级合并多个配置来源。

.DESCRIPTION
    支持显式 `-Sources`、显式 `-ConfigFile`，以及基于默认 env 发现规则的隐式文件来源。
    后出现的来源覆盖先前值，并可选记录每个键的候选来源轨迹。

.PARAMETER ConfigFile
    按顺序读取的配置文件列表，支持 env 与 JSON。

.PARAMETER Sources
    供脚本调用方直接传入的结构化来源列表。

.PARAMETER BasePath
    解析相对路径与默认 env 发现时使用的基准目录。

.PARAMETER IncludeTrace
    为真时，返回每个键的候选来源轨迹。

.PARAMETER ErrorOnMissing
    为真时，缺失的文件来源会直接抛错。

.OUTPUTS
    PSCustomObject
    返回 `Values`、`Sources` 与 `Trace` 三个成员。
#>
function Resolve-ConfigSources {
    [CmdletBinding()]
    param(
        [string[]]$ConfigFile,
        [hashtable[]]$Sources,
        [string]$BasePath = (Get-Location).Path,
        [switch]$IncludeTrace,
        [switch]$ErrorOnMissing
    )

    $resolvedSources = @()

    if ($PSBoundParameters.ContainsKey('Sources') -and $Sources.Count -gt 0) {
        foreach ($source in $Sources) {
            $resolvedSources += Get-ConfigSourceDescriptor -Source $source -BasePath $BasePath
        }
    }
    else {
        $fileList = if ($PSBoundParameters.ContainsKey('ConfigFile') -and $ConfigFile.Count -gt 0) {
            $ConfigFile
        }
        else {
            (Resolve-DefaultEnvFiles -PrimaryBasePath $BasePath).Paths
        }

        foreach ($path in $fileList) {
            $sourceType = if ($path -match '\.json$') { 'JsonFile' } else { 'EnvFile' }
            $resolvedSources += Get-ConfigSourceDescriptor -Source @{
                Type = $sourceType
                Path = $path
            } -BasePath $BasePath
        }
    }

    $values = @{}
    $sourcesMap = @{}
    $trace = @{}

    foreach ($source in $resolvedSources) {
        $sourceValues = Read-ConfigSourceValues -Source $source -ErrorOnMissing:$ErrorOnMissing
        foreach ($entry in $sourceValues.GetEnumerator()) {
            $values[$entry.Key] = $entry.Value
            $sourcesMap[$entry.Key] = $source.Name

            if ($IncludeTrace) {
                if (-not $trace.ContainsKey($entry.Key)) {
                    $trace[$entry.Key] = [pscustomobject]@{
                        Candidates = New-Object 'System.Collections.Generic.List[object]'
                    }
                }

                $trace[$entry.Key].Candidates.Add([pscustomobject]@{
                    Source = $source.Name
                    Value  = $entry.Value
                })
            }
        }
    }

    return [pscustomobject]@{
        Values  = $values
        Sources = $sourcesMap
        Trace   = $trace
    }
}
