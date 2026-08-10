<#+
.SYNOPSIS
    Invokes the installed browser-host control with fixed argv.
.PARAMETER Arguments
    Validated browser-host arguments.
.PARAMETER BrowserHostPath
    Optional installed helper path for testing or relocation.
.OUTPUTS
    PSCustomObject containing ExitCode.
#>
function Invoke-BrowserHostControl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments, [string]$BrowserHostPath = $env:BROWSER_HOST_CONTROL_PATH)
    if ([string]::IsNullOrWhiteSpace($BrowserHostPath)) { $BrowserHostPath = Join-Path $HOME '.local\share\selfhosted-compose\browser-runtime\browser-host.ps1' }
    if (-not (Test-Path -LiteralPath $BrowserHostPath -PathType Leaf)) {
        $action = if ($Arguments.Count -gt 0) { $Arguments[0] } else { 'unknown' }
        [Console]::Error.WriteLine((@{ schemaVersion = 1; error = 'installed browser-host control is missing'; action = $action } | ConvertTo-Json -Compress))
        return [pscustomobject]@{ ExitCode = 127 }
    }
    & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $BrowserHostPath @Arguments
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE }
}
