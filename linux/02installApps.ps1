

$modulePath = Resolve-Path -Path (Join-Path $PSScriptRoot '../psutils')
Import-Module -Name $modulePath

$configPath = (Resolve-Path -Path (Join-Path $PSScriptRoot '../profile/installer/apps-config.json')).Path
Install-PackageManagerApps -PackageManager 'homebrew' -ConfigPath $configPath

if (Test-ModuleInstalled -ModuleName 'npm') {
    Install-PackageManagerApps -PackageManager 'npm' -ConfigPath $configPath
}
