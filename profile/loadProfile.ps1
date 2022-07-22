# Import-Module './profile.psm1'
$currentScriptPath =  $MyInvocation.MyCommand.Definition
$currentScriptFolder = Split-Path  -Parent   $currentScriptPath 


Set-Content -Path $profile  -Value (Get-Content $currentScriptFolder/profile.ps1)