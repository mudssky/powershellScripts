. $PSScriptRoot/core/platform.ps1
. $PSScriptRoot/core/loadModule.ps1

$profilePlatformContext = Get-ProfilePlatformContext
$profileModuleResult = Import-ProfileCoreModules -ProfileRoot $PSScriptRoot -PlatformContext $profilePlatformContext
Register-ProfileOnIdle -ProfileRoot $PSScriptRoot -ModuleManifest $profileModuleResult.ModuleManifest | Out-Null
