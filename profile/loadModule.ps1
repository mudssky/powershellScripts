$moduleParent = Split-Path -Parent $PSScriptRoot
$psutilsRoot = Join-Path $moduleParent 'psutils'
$modulesPath = Join-Path $psutilsRoot 'modules'

Import-Module (Join-Path $modulesPath 'test.psm1')
Import-Module (Join-Path $modulesPath 'cache.psm1')
Import-Module (Join-Path $modulesPath 'wrapper.psm1')

$paths = ($env:PSModulePath -split ';') | Where-Object { $_ }
if ($psutilsRoot -notin $paths) {
    $env:PSModulePath = ($paths + $psutilsRoot) -join ';'
}


