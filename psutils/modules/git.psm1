function Get-GitIgnorePatterns {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$GitIgnorePath = (Join-Path -Path (Get-Location) -ChildPath '.gitignore')
    )

    $patterns = @()
    try {
        if (-not (Test-Path -LiteralPath $GitIgnorePath)) {
            Write-Verbose "GitIgnore file not found: $GitIgnorePath"
            return @()
        }

        $lines = Get-Content -LiteralPath $GitIgnorePath -ErrorAction Stop
        foreach ($line in $lines) {
            $t = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($t)) { continue }

            if ($t.StartsWith('\#')) {
                $t = $t.Substring(1)
            }
            elseif ($t.StartsWith('#')) {
                continue
            }

            if ($t.StartsWith('!')) { continue }

            while ($t.StartsWith('/')) { $t = $t.Substring(1) }
            if ($t.EndsWith('/')) { $t = $t.TrimEnd('/') }

            if (-not [string]::IsNullOrWhiteSpace($t)) { $patterns += $t }
        }
    }
    catch {
        Write-Error $_.Exception.Message
        return @()
    }
    return (@($patterns | Select-Object -Unique))
}

function New-7ZipExcludeArgs {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$GitIgnorePath = (Join-Path -Path (Get-Location) -ChildPath '.gitignore'),
        [Parameter()]
        [string[]]$AdditionalExcludes = @()
    )

    $baseExcludes = @(
        'node_modules',
        'prisma/*.db',
        'public/oss',
        'public/upload',
        'log/',
        '.next/',
        '.git/',
        '*.log',
        '*.tmp'
    )

    $gitPatterns = Get-GitIgnorePatterns -GitIgnorePath $GitIgnorePath

    $normalizedBase = $baseExcludes | ForEach-Object {
        $p = $_.Trim()
        while ($p.StartsWith('/')) { $p = $p.Substring(1) }
        if ($p.EndsWith('/')) { $p = $p.TrimEnd('/') }
        $p
    }

    $normalizedAdditional = @()
    foreach ($a in $AdditionalExcludes) {
        if ([string]::IsNullOrWhiteSpace($a)) { continue }
        $p = $a.Trim()
        while ($p.StartsWith('/')) { $p = $p.Substring(1) }
        if ($p.EndsWith('/')) { $p = $p.TrimEnd('/') }
        $normalizedAdditional += $p
    }

    $all = @($normalizedBase + $gitPatterns + $normalizedAdditional) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique

    $excludeArgs = $all | ForEach-Object { "-xr!$_" }
    return $excludeArgs
}

Export-ModuleMember -Function Get-GitIgnorePatterns, New-7ZipExcludeArgs
