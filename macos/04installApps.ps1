
$modulePath = Resolve-Path -Path (Join-Path $PSScriptRoot '../psutils')
Import-Module -Name $modulePath

$configPath = (Resolve-Path -Path (Join-Path $PSScriptRoot '../profile/installer/apps-config.json')).Path
$fontInstallerPath = (Resolve-Path -Path (Join-Path $PSScriptRoot '../profile/installer/installFont.ps1')).Path

& $fontInstallerPath

Install-PackageManagerApps -PackageManager 'homebrew' -ConfigPath $configPath -FilterByOS $true -TargetOS 'macOS' -FilterPredicates {
    param($appInfo)
    $appInfo.tag -contains 'macbook' -and -not ($appInfo.name -like 'font-*')
}
