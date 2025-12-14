

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
    $bashrcPath = ~/.bashrc
    # 确保.bashrc文件存在
    # if (-not (Test-Path $bashrcPath)) {
    #     New-Item -Path $bashrcPath -ItemType File -Force | Out-Null
    # }
    # 检查bashrc中是否已包含bun路径配置（使用简单字符串匹配避免正则表达式问题）
    if (-not (Select-String -Path $bashrcPath -Pattern '.bun/bin' -SimpleMatch -Quiet)) {
        Add-Content -Path $bashrcPath -Value "export PATH=\"~/.bun/bin:$PATH\""
    }
}

if (Test-EXEProgram -Name 'bun') {
    Install-PackageManagerApps -PackageManager 'bun' -ConfigPath $configPath
}

if ( -not (Test-EXEProgram -Name 'docker')) {
    # bash ./ubuntu/installer/install_docker.sh
    bash ./ubuntu/installer/installDocker.sh
}
