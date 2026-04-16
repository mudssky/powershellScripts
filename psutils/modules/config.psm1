Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Read-ConfigEnvFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $pairs = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*([^=]+)=(.*)$') {
            $pairs[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }

    return $pairs
}

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
            @('.env', '.env.local')
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

function Invoke-WithScopedEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Variables,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    $previousValues = @{}
    $missingKeys = New-Object 'System.Collections.Generic.HashSet[string]'

    foreach ($entry in $Variables.GetEnumerator()) {
        $existingValue = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        if ($null -eq $existingValue) {
            $missingKeys.Add($entry.Key) | Out-Null
        }
        else {
            $previousValues[$entry.Key] = $existingValue
        }

        [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
    }

    try {
        return & $ScriptBlock
    }
    finally {
        foreach ($entry in $Variables.GetEnumerator()) {
            if ($missingKeys.Contains($entry.Key)) {
                [Environment]::SetEnvironmentVariable($entry.Key, $null, 'Process')
                Remove-Item -Path ("Env:{0}" -f $entry.Key) -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable($entry.Key, $previousValues[$entry.Key], 'Process')
            }
        }
    }
}
