

$modulePath = Resolve-Path -Path (Join-Path $PSScriptRoot '../psutils')
Import-Module -Name $modulePath

$configPath = (Resolve-Path -Path (Join-Path $PSScriptRoot '../profile/installer/apps-config.json')).Path
Install-PackageManagerApps -PackageManager 'homebrew' -ConfigPath $configPath -FilterByOS $true -TargetOS 'Linux' -FilterPredicates {
    param($appInfo)
    $appInfo.tag -contains 'linuxserver'
}

if (Test-EXEProgram -Name 'npm') {
    Install-PackageManagerApps -PackageManager 'npm' -ConfigPath $configPath
}
