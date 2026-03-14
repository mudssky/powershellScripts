
# 模块级别缓存：默认缓存命中结果；未命中结果仅在显式开启时缓存
if (-not $script:ExecutableCommandCache) {
    $script:ExecutableCommandCache = @{}
}

function Test-ExecutableCommandIsWindows {
    [CmdletBinding()]
    param()

    return ($IsWindows -or $env:OS -eq 'Windows_NT')
}

function Get-ExecutableCommandPathExtValue {
    [CmdletBinding()]
    param()

    if (-not (Test-ExecutableCommandIsWindows)) {
        return ''
    }

    $pathExtValue = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')
    if ([string]::IsNullOrWhiteSpace($pathExtValue)) {
        return '.COM;.EXE;.BAT;.CMD'
    }

    return $pathExtValue
}

function Get-ExecutableCommandCacheKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [switch]$AllMatches
    )

    $normalizedName = if (Test-ExecutableCommandIsWindows) {
        $Name.ToLowerInvariant()
    }
    else {
        $Name
    }

    return '{0}|all={1}' -f $normalizedName, $AllMatches.IsPresent
}

function Test-ExecutableCommandIsPathQualified {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ([System.IO.Path]::IsPathRooted($Name)) {
        return $true
    }

    return (
        $Name.IndexOf([System.IO.Path]::DirectorySeparatorChar) -ge 0 -or
        $Name.IndexOf([System.IO.Path]::AltDirectorySeparatorChar) -ge 0
    )
}

function Get-ExecutableCommandExtensions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$PathExtValue
    )

    if (-not [string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($Name))) {
        return @('')
    }

    if (-not (Test-ExecutableCommandIsWindows)) {
        return @('')
    }

    $extensions = [System.Collections.Generic.List[string]]::new()
    $seenExtensions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($extension in $PathExtValue.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $trimmedExtension = $extension.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedExtension)) {
            continue
        }

        if (-not $trimmedExtension.StartsWith('.')) {
            $trimmedExtension = ".$trimmedExtension"
        }

        if ($seenExtensions.Add($trimmedExtension)) {
            $extensions.Add($trimmedExtension) | Out-Null
        }
    }

    if ($extensions.Count -eq 0) {
        return @('.COM', '.EXE', '.BAT', '.CMD')
    }

    return $extensions.ToArray()
}

function Get-ExecutableCommandSearchPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PathValue
    )

    $pathComparer = if (Test-ExecutableCommandIsWindows) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }

    $searchPaths = [System.Collections.Generic.List[string]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)

    foreach ($rawPath in $PathValue.Split([System.IO.Path]::PathSeparator, [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $candidatePath = $rawPath.Trim().Trim('"')
        if ([string]::IsNullOrWhiteSpace($candidatePath)) {
            continue
        }

        if (-not [System.IO.Directory]::Exists($candidatePath)) {
            continue
        }

        $normalizedPath = [System.IO.Path]::GetFullPath($candidatePath)
        if ($seenPaths.Add($normalizedPath)) {
            $searchPaths.Add($normalizedPath) | Out-Null
        }
    }

    return $searchPaths.ToArray()
}

function Test-ExecutableCommandCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not [System.IO.File]::Exists($Path)) {
        return $false
    }

    if (Test-ExecutableCommandIsWindows) {
        return $true
    }

    try {
        $mode = [System.IO.File]::GetUnixFileMode($Path)
        $executeFlags = [int][System.IO.UnixFileMode]::UserExecute `
            -bor [int][System.IO.UnixFileMode]::GroupExecute `
            -bor [int][System.IO.UnixFileMode]::OtherExecute
        return (([int]$mode -band $executeFlags) -ne 0)
    }
    catch {
        return $true
    }
}

function New-ExecutableCommandResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string[]]$MatchedPaths,
        [switch]$AllMatches
    )

    $resolvedPaths = @($MatchedPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $properties = [ordered]@{
        Name  = $Name
        Found = ($resolvedPaths.Count -gt 0)
        Path  = if ($resolvedPaths.Count -gt 0) { $resolvedPaths[0] } else { $null }
    }

    if ($AllMatches) {
        $properties['AllPaths'] = $resolvedPaths
    }

    return [PSCustomObject]$properties
}

function Resolve-ExecutableCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string[]]$SearchPaths,
        [Parameter(Mandatory)]
        [string]$PathExtValue,
        [switch]$AllMatches
    )

    $extensions = Get-ExecutableCommandExtensions -Name $Name -PathExtValue $PathExtValue
    $matchComparer = if (Test-ExecutableCommandIsWindows) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }

    $matchedPaths = [System.Collections.Generic.List[string]]::new()
    $seenMatches = [System.Collections.Generic.HashSet[string]]::new($matchComparer)

    if (Test-ExecutableCommandIsPathQualified -Name $Name) {
        $candidateBases = @($Name)
    }
    else {
        $candidateBases = foreach ($searchPath in $SearchPaths) {
            [System.IO.Path]::Combine($searchPath, $Name)
        }
    }

    foreach ($candidateBase in $candidateBases) {
        foreach ($extension in $extensions) {
            $candidatePath = if ([string]::IsNullOrEmpty($extension)) {
                $candidateBase
            }
            else {
                "$candidateBase$extension"
            }

            if (-not (Test-ExecutableCommandCandidate -Path $candidatePath)) {
                continue
            }

            $resolvedPath = [System.IO.Path]::GetFullPath($candidatePath)
            if (-not $seenMatches.Add($resolvedPath)) {
                continue
            }

            $matchedPaths.Add($resolvedPath) | Out-Null
            if (-not $AllMatches) {
                return (New-ExecutableCommandResult -Name $Name -MatchedPaths $matchedPaths.ToArray())
            }
        }
    }

    return (New-ExecutableCommandResult -Name $Name -MatchedPaths $matchedPaths.ToArray() -AllMatches:$AllMatches)
}

function Resolve-ExecutableCommandsBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Names,
        [Parameter(Mandatory)]
        [string[]]$SearchPaths,
        [Parameter(Mandatory)]
        [string]$PathExtValue,
        [switch]$AllMatches
    )

    $pathComparer = if (Test-ExecutableCommandIsWindows) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }

    $requests = [System.Collections.Specialized.OrderedDictionary]::new($pathComparer)
    foreach ($commandName in $Names) {
        if ($requests.Contains($commandName)) {
            continue
        }

        $extensions = Get-ExecutableCommandExtensions -Name $commandName -PathExtValue $PathExtValue
        $candidateFileNames = foreach ($extension in $extensions) {
            if ([string]::IsNullOrEmpty($extension)) {
                $commandName
            }
            else {
                "$commandName$extension"
            }
        }

        $requests[$commandName] = [PSCustomObject]@{
            Name           = $commandName
            CandidateNames = @($candidateFileNames)
            MatchedPaths   = [System.Collections.Generic.List[string]]::new()
            SeenMatches    = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
            Resolved       = $false
        }
    }

    foreach ($searchPath in $SearchPaths) {
        $directoryEntries = [System.Collections.Generic.Dictionary[string, string]]::new($pathComparer)
        try {
            foreach ($candidatePath in [System.IO.Directory]::EnumerateFiles($searchPath)) {
                $candidateName = [System.IO.Path]::GetFileName($candidatePath)
                if (-not $directoryEntries.ContainsKey($candidateName)) {
                    $directoryEntries[$candidateName] = $candidatePath
                }
            }
        }
        catch {
            continue
        }

        foreach ($request in $requests.Values) {
            if ($request.Resolved -and -not $AllMatches) {
                continue
            }

            foreach ($candidateName in $request.CandidateNames) {
                $candidatePath = $null
                if (-not $directoryEntries.TryGetValue($candidateName, [ref]$candidatePath)) {
                    continue
                }

                $resolvedPath = [System.IO.Path]::GetFullPath($candidatePath)
                if (-not $request.SeenMatches.Add($resolvedPath)) {
                    continue
                }

                if (-not (Test-ExecutableCommandCandidate -Path $resolvedPath)) {
                    continue
                }

                $request.MatchedPaths.Add($resolvedPath) | Out-Null
                if (-not $AllMatches) {
                    $request.Resolved = $true
                    break
                }
            }
        }

        if (-not $AllMatches) {
            $hasUnresolvedRequest = $false
            foreach ($request in $requests.Values) {
                if (-not $request.Resolved) {
                    $hasUnresolvedRequest = $true
                    break
                }
            }

            if (-not $hasUnresolvedRequest) {
                break
            }
        }
    }

    foreach ($request in $requests.Values) {
        New-ExecutableCommandResult `
            -Name $request.Name `
            -MatchedPaths $request.MatchedPaths.ToArray() `
            -AllMatches:$AllMatches
    }
}

<#
.SYNOPSIS
    查找当前 shell 环境中可执行的外部命令。

.DESCRIPTION
    基于 PATH（Windows 额外使用 PATHEXT）直接探测外部可执行命令，避免使用
    `Get-Command` 带来的模块自动导入和命令发现回退开销。适合性能敏感场景，
    例如 Profile 启动期的工具存在性检测。

.PARAMETER Name
    要探测的命令名。支持单个字符串或字符串数组，也支持通过管道输入。

.PARAMETER AllMatches
    返回所有命中的路径。默认仅返回首个命中路径。

.PARAMETER CacheMisses
    显式开启当前会话内的未命中缓存。默认只缓存命中结果。

.PARAMETER NoCache
    跳过缓存，强制重新探测。

.INPUTS
    字符串。

.OUTPUTS
    PSCustomObject。默认包含 `Name`、`Found`、`Path`。指定 `-AllMatches` 时额外包含 `AllPaths`。

.EXAMPLE
    Find-ExecutableCommand -Name 'pwsh'

.EXAMPLE
    Find-ExecutableCommand -Name @('starship', 'scoop', 'brew') -CacheMisses

.EXAMPLE
    'git', 'node' | Find-ExecutableCommand -AllMatches

.NOTES
    默认不会缓存未命中结果；若需要极致性能（例如 Profile 启动），由调用方显式指定 `-CacheMisses`。
#>
function Find-ExecutableCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('CommandName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,
        [switch]$AllMatches,
        [switch]$CacheMisses,
        [switch]$NoCache
    )

    begin {
        $pathValue = [Environment]::GetEnvironmentVariable('PATH', 'Process')
        if ($null -eq $pathValue) {
            $pathValue = ''
        }

        $pathExtValue = Get-ExecutableCommandPathExtValue
        $searchPaths = $null
    }

    process {
        $orderedCommandNames = @($Name)
        $resolvedResults = [System.Collections.Specialized.OrderedDictionary]::new()
        $pendingCommandNames = [System.Collections.Generic.List[string]]::new()

        foreach ($commandName in $orderedCommandNames) {
            $cacheKey = Get-ExecutableCommandCacheKey -Name $commandName -AllMatches:$AllMatches
            if (-not $NoCache -and $script:ExecutableCommandCache.ContainsKey($cacheKey)) {
                $cacheEntry = $script:ExecutableCommandCache[$cacheKey]
                $canReuseCacheEntry = $cacheEntry.Result.Found -or $CacheMisses
                if (
                    $canReuseCacheEntry -and
                    $cacheEntry.PathValue -eq $pathValue -and
                    $cacheEntry.PathExtValue -eq $pathExtValue
                ) {
                    $resolvedResults[$commandName] = $cacheEntry.Result
                    continue
                }
            }

            $pendingCommandNames.Add($commandName) | Out-Null
        }

        $pendingResultMap = [System.Collections.Specialized.OrderedDictionary]::new()
        if ($pendingCommandNames.Count -gt 0) {
            if ($null -eq $searchPaths) {
                $searchPaths = Get-ExecutableCommandSearchPaths -PathValue $pathValue
            }

            $canUseBatchResolution = ($pendingCommandNames.Count -gt 1)
            if ($canUseBatchResolution) {
                foreach ($pendingCommandName in $pendingCommandNames) {
                    if (Test-ExecutableCommandIsPathQualified -Name $pendingCommandName) {
                        $canUseBatchResolution = $false
                        break
                    }
                }
            }

            if ($canUseBatchResolution) {
                foreach ($result in @(Resolve-ExecutableCommandsBatch `
                            -Names $pendingCommandNames.ToArray() `
                            -SearchPaths $searchPaths `
                            -PathExtValue $pathExtValue `
                            -AllMatches:$AllMatches)) {
                    $pendingResultMap[$result.Name] = $result
                }
            }
            else {
                foreach ($pendingCommandName in $pendingCommandNames) {
                    $result = Resolve-ExecutableCommand `
                        -Name $pendingCommandName `
                        -SearchPaths $searchPaths `
                        -PathExtValue $pathExtValue `
                        -AllMatches:$AllMatches
                    $pendingResultMap[$pendingCommandName] = $result
                }
            }
        }

        foreach ($commandName in $orderedCommandNames) {
            $result = if ($resolvedResults.Contains($commandName)) {
                $resolvedResults[$commandName]
            }
            else {
                $pendingResultMap[$commandName]
            }

            $cacheKey = Get-ExecutableCommandCacheKey -Name $commandName -AllMatches:$AllMatches
            if ($result -and ($result.Found -or $CacheMisses)) {
                $script:ExecutableCommandCache[$cacheKey] = [PSCustomObject]@{
                    PathValue    = $pathValue
                    PathExtValue = $pathExtValue
                    Result       = $result
                }
            }

            Write-Output $result
        }
    }
}

Export-ModuleMember -Function Find-ExecutableCommand
