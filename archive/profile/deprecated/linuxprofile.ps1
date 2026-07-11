[CmdletBinding()]
param(
    [switch]$loadProfile
)

. $PSScriptRoot/loadModule.ps1

# 开启基于历史命令的命令补全
Set-PSReadLineOption -PredictionSource History

if (Test-EXEProgram -Name starship) {
    Invoke-Expression (&starship init powershell)
}
else {
    # 不存在starship的时候，提示用户进行安装
    Write-Host -ForegroundColor Green  '未安装startship（一款开源提示符美化），可以运行以下命令进行安装 
	1.choco install starship 
	2.Invoke-Expression (&starship init powershell)'
}

if ($loadProfile) {
    $profileDir = Split-Path -Parent -Path $profile
    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $profile) {
        $current = Get-Content -Path $profile -ErrorAction SilentlyContinue
        if ($current -notcontains ". $PSCommandPath") {
            Add-Content -Path $profile -Value ". $PSCommandPath"
        }
    }
    else {
        New-Item -ItemType File -Path $profile -Force | Out-Null
        Set-Content -Path $profile -Value ". $PSCommandPath"
    }
}
