
[cmdletbinding()]
param() {

}
# $helixPath = Split-Path -Parent $PSScriptRoot 
# $helixPath = Split-Path -Parent $helixPath

# 配置文件位置
# Linux and Mac: ~/.config/helix/config.toml
# Windows: %AppData%\helix\config.toml

$modulePath = Join-Path $PSScriptRoot '../../../psutils'
Import-Module -Name $modulePath -Verbose:$false


if (-not (Test-EXEProgram 'hx') ) {
	scoop install helix
}
else {
	Write-Host "Helix is already installed"
}

$configFolder = "$env:APPDATA/helix"
if (-not (Test-Path $configFolder)) {
	mkdir  $configFolder
}




Copy-Item -Force -Path $PSScriptRoot/config/*.toml  -Destination   $configFolder/
Write-Verbose '覆盖文件成功'



