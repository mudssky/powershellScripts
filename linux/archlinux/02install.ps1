

$modulePath = Resolve-Path -Path (Join-Path $PSScriptRoot '../../psutils')
Import-Module -Name $modulePath

$configPath = (Resolve-Path -Path (Join-Path $PSScriptRoot '../../profile/installer/apps-config.json')).Path
Install-PackageManagerApps -PackageManager 'pacman' -ConfigPath $configPath

if (Test-EXEProgram -Name 'yay') {
    Install-PackageManagerApps -PackageManager 'yay' -ConfigPath $configPath
}

if (Test-EXEProgram -Name 'brew') {
    Write-Host "正在使用 Homebrew 安装软件包..."
    Install-PackageManagerApps -PackageManager 'homebrew' -ConfigPath $configPath
}
