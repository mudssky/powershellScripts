$moduleParent = Split-Path -Parent $PSScriptRoot
$psutilsRoot = Join-Path $moduleParent 'psutils'

Import-Module (Join-Path $psutilsRoot 'psutils.psd1')

$sep = [System.IO.Path]::PathSeparator
$paths = ($env:PSModulePath -split [string]$sep) | Where-Object { $_ }
if ($psutilsRoot -notin $paths) {
    $env:PSModulePath = ($paths + $psutilsRoot) -join $sep
}

