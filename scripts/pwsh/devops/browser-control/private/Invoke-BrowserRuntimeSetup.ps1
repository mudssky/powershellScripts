<#+
.SYNOPSIS
    Discovers and invokes the authoritative self-hosted-compose Windows setup script.
#>
function Resolve-BrowserRuntimeSetupSourceRoot {
    [CmdletBinding()]
    param([string]$SourceRoot, [string]$EnvironmentSourceRoot = $env:SELFHOSTED_COMPOSE_ROOT, [string]$StartDirectory = (Get-Location).Path)
    $relativeSetup = 'native-services/browser-runtime/windows/setup-browser-runtime.ps1'
    $testRoot = {
        param($Candidate)
        return (Test-Path -LiteralPath (Join-Path $Candidate 'package.json') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $Candidate 'native-services/browser-runtime/service.config.ts') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $Candidate $relativeSetup) -PathType Leaf)
    }
    if (-not [string]::IsNullOrWhiteSpace($SourceRoot)) {
        $candidate = [IO.Path]::GetFullPath($SourceRoot)
        if (-not (& $testRoot $candidate)) { throw "SourceRoot is not a self-hosted-compose checkout: $candidate" }
        return $candidate
    }
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentSourceRoot)) {
        $candidate = [IO.Path]::GetFullPath($EnvironmentSourceRoot)
        if (-not (& $testRoot $candidate)) { throw "SELFHOSTED_COMPOSE_ROOT is not a self-hosted-compose checkout: $candidate" }
        return $candidate
    }
    $current = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($StartDirectory))
    while ($null -ne $current) {
        if (& $testRoot $current.FullName) { return $current.FullName }
        $current = $current.Parent
    }
    throw 'self-hosted-compose checkout was not found; run from the checkout or pass -SourceRoot'
}

function Invoke-BrowserRuntimeSetup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Runtime, [string]$SourceRoot, [string]$RuntimeRoot, [string]$ProfileRoot)
    if ($Runtime -ne 'windows') { throw 'setup target must be windows' }
    $resolvedSourceRoot = Resolve-BrowserRuntimeSetupSourceRoot -SourceRoot $SourceRoot
    $setupScript = Join-Path $resolvedSourceRoot 'native-services/browser-runtime/windows/setup-browser-runtime.ps1'
    $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $setupScript, '-SourceRoot', $resolvedSourceRoot)
    if (-not [string]::IsNullOrWhiteSpace($RuntimeRoot)) { $arguments += @('-RuntimeRoot', $RuntimeRoot) }
    if (-not [string]::IsNullOrWhiteSpace($ProfileRoot)) { $arguments += @('-ProfileRoot', $ProfileRoot) }
    & powershell.exe @arguments
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE }
}
