

$modulePath = Resolve-Path -Path (Join-Path $PSScriptRoot '../psutils')
Import-Module -Name $modulePath

$configPath = (Resolve-Path -Path (Join-Path $PSScriptRoot '../profile/installer/apps-config.json')).Path
Install-PackageManagerApps -PackageManager 'homebrew' -ConfigPath $configPath -FilterByOS $true -TargetOS 'Linux' -FilterPredicates {
    param($appInfo)
    $appInfo.tag -contains 'linuxserver'
}

if (-not (Test-EXEProgram -Name 'bun')) {
    # bash ./ubuntu/installer/install_bun.sh
    npm install -g nrm --registry='https://registry.npmmirror.com'
    nrm use taobao
    npm install -g bun 
    }

if (Test-EXEProgram -Name 'bun') {
    Install-PackageManagerApps -PackageManager 'bun' -ConfigPath $configPath
}
