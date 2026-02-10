[CmdletBinding()] 
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [string]$RepoConfPath,

    [switch]$OverwriteAvailable,

    [switch]$UseSystemctl,

    [string]$BasicUser,

    [string]$BasicPassword,

    [switch]$DryRun
)

<#
.SYNOPSIS
在本仓库（config/nginx）下启用指定的 Nginx 配置（方案二：sites-available/enabled）
.DESCRIPTION
该脚本用于将仓库中的 `config/nginx/sites-available/<Name>.conf` 安装到系统路径 `/etc/nginx/sites-available/<Name>` 并在 `/etc/nginx/sites-enabled/<Name>` 创建软链接，使其生效；在启用前自动运行 `nginx -t` 进行语法校验，成功后执行平滑重载。可选生成 Basic Auth 的 htpasswd。
.PARAMETER Name
配置名（不带扩展名），例如 `ollama-basic` 或 `ollama-bearer`。
.PARAMETER RepoConfPath
指定仓库中的 `.conf` 路径；未指定时默认使用 `config/nginx/sites-available/<Name>.conf`。
.PARAMETER OverwriteAvailable
目标 `/etc/nginx/sites-available/<Name>` 已存在时允许覆盖。
.PARAMETER UseSystemctl
重载与启动优先使用 `systemctl`。
.PARAMETER BasicUser
当启用 Basic Auth 模板时，创建/更新 `/etc/nginx/.htpasswd` 的用户名。
.PARAMETER BasicPassword
当启用 Basic Auth 模板时，创建/更新 `/etc/nginx/.htpasswd` 的密码。
.PARAMETER DryRun
演练模式：仅打印将执行的操作，不对系统进行更改。
.EXAMPLE
sudo pwsh -File ./config/nginx/enableNginxConf.ps1 -Name ollama-basic -BasicUser ollama -BasicPassword 'your-secret'
.EXAMPLE
sudo pwsh -File ./config/nginx/enableNginxConf.ps1 -Name ollama-bearer
.NOTES
需要系统已安装 Nginx；若使用 Basic Auth，需要 `htpasswd`（Debian/Ubuntu: `apache2-utils`，RHEL/CentOS: `httpd-tools`）。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'Manage-NginxConf.psm1'
Import-Module $modulePath -Force

Write-Output "即将启用配置: $Name"
if (-not $RepoConfPath) {
    $RepoConfPath = Join-Path (Join-Path $PSScriptRoot 'sites-available') ("$Name.conf")
}
Write-Output "使用仓库模板路径: $RepoConfPath"
if ($DryRun) { Write-Output "运行于 DryRun 模式：不会对系统进行任何变更" }

try {
    if ($BasicUser) {
        if ($DryRun) {
            Write-Output "[DryRun] 将创建/更新 htpasswd: 用户=$BasicUser"
        }
        else {
            try {
                New-NginxHtpasswd -User $BasicUser -Password $BasicPassword
            }
            catch {
                Write-Warning "创建 htpasswd 失败：$($_.Exception.Message)"
                Write-Warning "尝试以 sudo 或将 FilePath 指向可写路径（默认 /etc/nginx/.htpasswd）"
            }
        }
    }

    if ($DryRun) {
        Write-Output "[DryRun] 将执行 Enable-NginxConf：Name=$Name, Overwrite=$($OverwriteAvailable.IsPresent), UseSystemctl=$($UseSystemctl.IsPresent)"
    }
    else {
        Start-Nginx -UseSystemctl:$UseSystemctl.IsPresent
        Enable-NginxConf -Name $Name -RepoConfPath $RepoConfPath -OverwriteAvailable:$OverwriteAvailable.IsPresent -UseSystemctl:$UseSystemctl.IsPresent
        Write-Output "配置 $Name 已启用并重载 Nginx"
    }
}
catch {
    Write-Error "启用配置失败：$($_.Exception.Message)"
    exit 1
}
