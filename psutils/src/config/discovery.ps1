Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    按优先级定位默认 env 文件集合。

.DESCRIPTION
    优先检查主目录中的 `.env` 与 `.env.local`；
    仅当主目录完全没有默认 env 文件时，才回退到备用目录。

.PARAMETER PrimaryBasePath
    首选目录，通常是当前工作目录。

.PARAMETER FallbackBasePath
    回退目录，仅在首选目录没有任一默认 env 文件时生效。

.OUTPUTS
    PSCustomObject
    返回包含命中的 `BasePath` 与按优先顺序排列的 `Paths`。
#>
function Resolve-DefaultEnvFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PrimaryBasePath,

        [string]$FallbackBasePath
    )

    $candidateBases = @($PrimaryBasePath)
    if (-not [string]::IsNullOrWhiteSpace($FallbackBasePath)) {
        $candidateBases += $FallbackBasePath
    }

    foreach ($basePath in $candidateBases) {
        if ([string]::IsNullOrWhiteSpace($basePath) -or -not (Test-Path -LiteralPath $basePath -PathType Container)) {
            continue
        }

        $paths = New-Object 'System.Collections.Generic.List[string]'
        foreach ($fileName in @('.env', '.env.local')) {
            $candidatePath = Join-Path $basePath $fileName
            if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
                $paths.Add($candidatePath) | Out-Null
            }
        }

        if ($paths.Count -gt 0) {
            return [pscustomobject]@{
                BasePath = $basePath
                Paths    = @($paths)
            }
        }
    }

    return [pscustomobject]@{
        BasePath = $null
        Paths    = @()
    }
}
