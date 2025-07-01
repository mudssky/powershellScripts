<#
.SYNOPSIS
    配置Git个人用户信息的脚本

.DESCRIPTION
    该脚本用于快速配置Git的用户名和邮箱信息。支持全局配置、本地配置和查看当前配置。
    默认配置用户名为"mudssky"，邮箱为"mudssky@gmail.com"。

.PARAMETER local
    开关参数，如果指定则只为当前仓库配置用户信息，否则进行全局配置

.PARAMETER showCurrent
    开关参数，如果指定则显示当前的Git用户配置信息

.EXAMPLE
    .\gitconfig_personal.ps1
    全局配置Git用户信息

.EXAMPLE
    .\gitconfig_personal.ps1 -local
    仅为当前仓库配置用户信息

.EXAMPLE
    .\gitconfig_personal.ps1 -showCurrent
    显示当前的Git用户配置

.NOTES
    需要安装Git工具
    如果需要修改用户名和邮箱，请直接编辑脚本中的相应值
#>
param(
    [switch]$local,
    [switch]$showCurrent
)

if ($showCurrent) {
    git config  user.name 	
    git config  user.email
    exit	
}
if ($local) {
    git config  user.name "mudssky"
    git config  user.email "mudssky@gmail.com"
    exit
}
git config --global user.name "mudssky"
git config --global user.email "mudssky@gmail.com"