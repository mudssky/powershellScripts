#!/usr/bin/env pwsh
<#+
.SYNOPSIS
    Thin PowerShell browserctl entry for installed browser-host.
.PARAMETER Action
    status, start, stop, attach, detach, diagnose, or recover-owner.
.PARAMETER Target
    windows/wsl or agent-browser/playwright.
.PARAMETER ConfirmServiceName
    Required as browser-runtime for recover-owner.
#>
[CmdletBinding(PositionalBinding = $true)]
param([Parameter(Position = 0)][string]$Action = 'status', [Parameter(Position = 1)][string]$Target, [string]$ConfirmServiceName)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'private/Invoke-BrowserHostControl.ps1')

<#+
.SYNOPSIS
    Validates and dispatches one browserctl command.
.OUTPUTS
    PSCustomObject containing ExitCode.
#>
function Invoke-BrowserControlCommand {
    [CmdletBinding()]
    param([string]$Action = 'status', [string]$Target, [string]$ConfirmServiceName)
    $arguments = switch ($Action) {
        'status' { @('status') }
        'start' { if ($Target -notin @('windows', 'wsl')) { throw 'start target must be windows or wsl' }; @('start', '-Runtime', $Target) }
        'stop' { @('stop') }
        'attach' { if ($Target -notin @('agent-browser', 'playwright')) { throw 'attach target must be agent-browser or playwright' }; @('attach', '-Client', $Target) }
        'detach' { @('detach') }
        'diagnose' { @('diagnose') }
        'recover-owner' { if ($ConfirmServiceName -ne 'browser-runtime') { throw 'recover-owner requires -ConfirmServiceName browser-runtime' }; @('recover-owner', '-ConfirmServiceName', 'browser-runtime') }
        default { throw "unsupported browserctl action: $Action" }
    }
    return Invoke-BrowserHostControl -Arguments $arguments
}

if ($env:PWSH_TEST_SKIP_BROWSER_CONTROL_MAIN -ne '1') {
    try { $result = Invoke-BrowserControlCommand -Action $Action -Target $Target -ConfirmServiceName $ConfirmServiceName; exit $result.ExitCode }
    catch { [Console]::Error.WriteLine((@{ schemaVersion = 1; error = $_.Exception.Message; action = $Action } | ConvertTo-Json -Compress)); exit 2 }
}
