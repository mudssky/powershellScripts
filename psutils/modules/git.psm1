<#
.SYNOPSIS
    读取 .gitignore 中的排除模式。
.DESCRIPTION
    忽略空行、注释和反向规则，规范化前导与尾随斜杠，并返回去重后的模式列表。
.PARAMETER GitIgnorePath
    要读取的 .gitignore 文件路径，默认为当前目录下的 .gitignore。
.OUTPUTS
    System.String[]
    返回可用于归档排除规则的模式数组；文件不存在或读取失败时返回空数组。
#>
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

<#
.SYNOPSIS
    生成 7-Zip 递归排除参数。
.DESCRIPTION
    合并内置排除项、.gitignore 模式和调用方附加模式，并转换为 7-Zip 的 -xr! 参数。
.PARAMETER GitIgnorePath
    要读取的 .gitignore 文件路径，默认为当前目录下的 .gitignore。
.PARAMETER AdditionalExcludes
    需要额外排除的文件、目录或通配模式。
.OUTPUTS
    System.String[]
    返回可直接传给 7-Zip 的排除参数数组。
#>
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
