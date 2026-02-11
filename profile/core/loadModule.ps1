$moduleParent = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$psutilsRoot = Join-Path $moduleParent 'psutils'
$moduleManifest = Join-Path $psutilsRoot 'psutils.psd1'

try {
    Import-Module $moduleManifest -ErrorAction Stop
}
catch {
    Write-Error "[profile/core/loadModule.ps1] Import-Module 失败: $moduleManifest :: $($_.Exception.Message)"
    throw
}

# PSModulePath 去重（不追加额外路径，仅清理重复条目）
$sep = [System.IO.Path]::PathSeparator
$paths = ($env:PSModulePath -split [string]$sep) | Where-Object { $_ }

$pathComparer = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    [System.StringComparer]::OrdinalIgnoreCase
}
else {
    [System.StringComparer]::Ordinal
}

$seenPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
$uniquePaths = [System.Collections.Generic.List[string]]::new()

foreach ($path in $paths) {
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    if ($seenPaths.Add($path)) {
        $uniquePaths.Add($path) | Out-Null
    }
}

$env:PSModulePath = ($uniquePaths.ToArray()) -join $sep
