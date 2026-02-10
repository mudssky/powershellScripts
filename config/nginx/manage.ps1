[CmdletBinding()] 
param(
    [ValidateSet('Enable', 'Disable', 'ListEnabled', 'ListAvailable', 'Show', 'RemoveAvailable', 'Verify', 'TestEndpoint')]
    [string]$Action = 'ListEnabled',

    [string]$Name,
    [ValidateSet('available', 'enabled', 'repo')] [string]$Source = 'available',
    [string]$Url,
    [string]$BasicUser,
    [string]$BasicPassword,
    [string]$BearerToken,
    [switch]$OverwriteAvailable,
    [switch]$UseSystemctl,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'Manage-NginxConf.psm1'
Import-Module $modulePath -Force

switch ($Action) {
    'ListEnabled' { Get-NginxEnabledConfs }
    'ListAvailable' { Get-NginxAvailableConfs }
    'Show' { if (-not $Name) { throw '需要 -Name' }; Get-NginxConfContent -Name $Name -Source $Source }
    'RemoveAvailable' { if (-not $Name) { throw '需要 -Name' }; Remove-NginxConf -Name $Name -Force:$Force.IsPresent -UseSystemctl:$UseSystemctl.IsPresent }
    'Verify' { if (-not $Name) { throw '需要 -Name' }; Verify-NginxConf -Name $Name -Url $Url -BasicUser $BasicUser -BasicPassword $BasicPassword -BearerToken $BearerToken }
    'TestEndpoint' { if (-not $Url) { throw '需要 -Url' }; Test-NginxEndpoint -Url $Url -BasicUser $BasicUser -BasicPassword $BasicPassword -BearerToken $BearerToken }
    'Enable' { if (-not $Name) { throw '需要 -Name' }; . (Join-Path $PSScriptRoot 'enableNginxConf.ps1') -Name $Name -OverwriteAvailable:$OverwriteAvailable.IsPresent -UseSystemctl:$UseSystemctl.IsPresent -BasicUser $BasicUser -BasicPassword $BasicPassword }
    'Disable' { if (-not $Name) { throw '需要 -Name' }; Disable-NginxConf -Name $Name -UseSystemctl:$UseSystemctl.IsPresent }
}

